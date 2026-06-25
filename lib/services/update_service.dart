// crypto is a transitive dependency (see pubspec.lock). Importing it directly
// here keeps pubspec.yaml untouched as required. Add `crypto: ^3.0.3` to
// pubspec.yaml as a direct dependency to silence this lint cleanly.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/update.dart';
import 'package:fl_clash/plugins/update.dart';
import 'package:path/path.dart' as p;

class UpdateService {
  static const List<String> _mirrors = [
    "https://ghproxy.com/",
    "https://mirror.ghproxy.com/",
  ];

  static const Duration _progressThrottle = Duration(milliseconds: 200);

  static const int _chunkSize = 64 * 1024;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: httpTimeoutDuration,
    receiveTimeout: const Duration(minutes: 30),
  ));

  /// Parse GitHub release JSON into [UpdateInfo], including assets and any
  /// SHA256 hashes embedded in the release body (lines formatted as
  /// "<filename> <sha256>").
  UpdateInfo parseReleaseInfo(Map<String, dynamic> data) {
    final tagName = (data['tag_name'] ?? '') as String;
    final body = (data['body'] ?? '') as String;
    final publishedAt =
        DateTime.tryParse((data['published_at'] ?? '') as String) ??
            DateTime.now();
    final assets = <UpdateAsset>[];
    final assetsRaw = data['assets'];
    if (assetsRaw is List) {
      for (final item in assetsRaw) {
        if (item is Map) {
          final name = (item['name'] ?? '') as String;
          final url = (item['browser_download_url'] ?? '') as String;
          final size = (item['size'] ?? 0) as num;
          if (name.isEmpty || url.isEmpty) continue;
          assets.add(UpdateAsset(
            name: name,
            browserDownloadUrl: url,
            size: size.toInt(),
          ));
        }
      }
    }
    return UpdateInfo(
      version: tagName.replaceAll('v', ''),
      tagName: tagName,
      releaseNotes: body,
      assets: assets,
      publishedAt: publishedAt,
      sha256Map: _parseSha256Map(body),
    );
  }

  Map<String, String> _parseSha256Map(String body) {
    final result = <String, String>{};
    final hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim().replaceAll('`', '').replaceAll('*', '');
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length == 2 && hex64.hasMatch(parts[1])) {
        result[parts[0]] = parts[1].toLowerCase();
      }
    }
    return result;
  }

  /// Select the asset matching the current platform/arch.
  ///
  /// Android: prefers arm64-v8a, then armeabi-v7a, then x86_64. ABI detection
  /// is async (device_info_plus) and this method is synchronous per contract,
  /// so arm64-v8a (the dominant Android ABI) is preferred. Controller may
  /// pre-select the asset if finer ABI matching is required.
  ///
  /// Windows: prefers a setup .exe, falls back to a .zip archive.
  UpdateAsset? selectAssetForCurrentPlatform(UpdateInfo info) {
    if (Platform.isAndroid) {
      const abiPreference = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
      final androidAssets = info.assets
          .where((a) => a.name.toLowerCase().contains('android'))
          .toList();
      for (final abi in abiPreference) {
        final match = _firstMatch(
            androidAssets, (n) => n.contains(abi));
        if (match != null) return match;
      }
      return null;
    }
    if (Platform.isWindows) {
      final winAssets = info.assets.where((a) {
        final n = a.name.toLowerCase();
        return n.contains('windows') || n.contains('win');
      }).toList();
      final exe = _firstMatch(winAssets, (n) => n.endsWith('.exe'));
      if (exe != null) return exe;
      return _firstMatch(winAssets, (n) => n.endsWith('.zip'));
    }
    return null;
  }

  UpdateAsset? _firstMatch(
      List<UpdateAsset> assets, bool Function(String) test) {
    for (final a in assets) {
      if (test(a.name.toLowerCase())) return a;
    }
    return null;
  }

  /// Download [asset] into the temp directory. Tries GitHub direct URL first,
  /// then each mirror on failure. [onProgress] is throttled to ~200ms.
  /// Supports cancellation via [cancelToken]. Returns the local file path.
  Future<String> download({
    required UpdateAsset asset,
    required void Function(DownloadProgress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final urls = <String>[
      asset.browserDownloadUrl,
      ..._mirrors.map((m) => m + asset.browserDownloadUrl),
    ];
    final savePath = p.join(await appPath.tempPath, asset.name);
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadSingle(
          url: url,
          savePath: savePath,
          fallbackTotal: asset.size,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        return savePath;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          throw UpdateException('download cancelled', UpdateStatus.downloading);
        }
        lastError = e;
      } catch (e) {
        lastError = e;
      }
    }
    throw UpdateException(
      'download failed: $lastError',
      UpdateStatus.downloading,
    );
  }

  Future<void> _downloadSingle({
    required String url,
    required String savePath,
    required int fallbackTotal,
    required void Function(DownloadProgress) onProgress,
    CancelToken? cancelToken,
  }) async {
    DateTime lastTime = DateTime.now();
    int lastReceived = 0;
    DateTime? lastEmit;
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, rtotal) {
        final now = DateTime.now();
        final dtMs = now.difference(lastTime).inMilliseconds;
        final speed = dtMs > 0
            ? ((received - lastReceived) * 1000) ~/ dtMs
            : 0;
        final effectiveTotal = rtotal > 0 ? rtotal : fallbackTotal;
        final done = rtotal > 0 && received >= rtotal;
        final shouldEmit = lastEmit == null ||
            now.difference(lastEmit!) >= _progressThrottle ||
            done;
        if (shouldEmit) {
          onProgress(DownloadProgress(
            downloaded: received,
            total: effectiveTotal,
            speed: speed,
          ));
          lastEmit = now;
          lastTime = now;
          lastReceived = received;
        }
      },
      cancelToken: cancelToken,
      deleteOnError: true,
    );
  }

  /// Verify SHA256 of [filePath] against [expectedSha256]. Returns true when
  /// [expectedSha256] is null/empty (no hash to check). Streams the file in
  /// 64KB chunks instead of loading it fully into memory.
  Future<bool> verifySha256(String filePath, String? expectedSha256) async {
    if (expectedSha256 == null || expectedSha256.isEmpty) return true;
    final expected = expectedSha256.toLowerCase();
    final file = File(filePath);
    if (!await file.exists()) return false;
    final raf = await file.open();
    try {
      final sink = _DigestSink();
      final hasher = sha256.startChunkedConversion(sink);
      while (true) {
        final data = await raf.read(_chunkSize);
        if (data.isEmpty) break;
        hasher.add(data);
      }
      hasher.close();
      final actual = sink.digest?.toString();
      return actual != null && actual == expected;
    } finally {
      await raf.close();
    }
  }

  /// Install the downloaded package.
  ///
  /// Android: launches the system install intent via [UpdatePlugin]
  /// (FileProvider content URI + ACTION_VIEW).
  /// Windows: starts the setup executable detached, then exits the current
  /// process so the installer can replace files. Uses [Process.start] with
  /// [ProcessStartMode.detached] instead of [Process.run] because a blocking
  /// [Process.run] would deadlock an installer that waits for the app to close.
  Future<void> install(String filePath) async {
    if (Platform.isAndroid) {
      final ok = await updatePlugin?.installApk(filePath) ?? false;
      if (!ok) {
        throw UpdateException(
            'install apk failed', UpdateStatus.installing);
      }
      return;
    }
    if (Platform.isWindows) {
      await Process.start(
        filePath,
        [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
    throw UpdateException(
        'unsupported platform', UpdateStatus.installing);
  }

  /// Restart the application.
  ///
  /// Android: relaunches MainActivity and kills the current process.
  /// Windows: starts a new instance detached, then exits.
  Future<void> restart() async {
    if (Platform.isAndroid) {
      await updatePlugin?.restartApp();
      return;
    }
    if (Platform.isWindows) {
      await Process.start(
        Platform.resolvedExecutable,
        [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
  }
}

/// Minimal [Sink<Digest>] used to collect the final hash from
/// [sha256.startChunkedConversion]. Avoids a dependency on
/// package:convert's AccumulatorSink.
class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

final updateService = UpdateService();
