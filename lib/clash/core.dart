import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/clash/interface.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class ClashCore {
  static ClashCore? _instance;
  late ClashInterface clashInterface;

  ClashCore._internal() {
    if (Platform.isAndroid) {
      clashInterface = clashLib!;
    } else {
      clashInterface = clashService!;
    }
  }

  factory ClashCore() {
    _instance ??= ClashCore._internal();
    return _instance!;
  }

  Future<void> _initGeo(ClashConfig clashConfig) async {
    final homePath = await appPath.getHomeDirPath();
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    // 按 geodata-loader 模式只复制所需的一套 geo 数据，减少首次启动 I/O
    final geoFileNameList = switch (clashConfig.geodataLoader) {
      geodataLoaderMemconservative => [
          mmdbFileName,
          geoSiteFileName,
          asnFileName,
        ],
      _ => [
          geoIpFileName,
          geoSiteFileName,
          asnFileName,
        ],
    };
    try {
      final filesToWrite = <(String, Uint8List)>[];
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(
          join(homePath, geoFileName),
        );
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final data = await rootBundle.load('assets/data/$geoFileName');
        filesToWrite.add((
          join(homePath, geoFileName),
          data.buffer.asUint8List(),
        ));
      }
      if (filesToWrite.isNotEmpty) {
        // 写盘放到后台 isolate，避免大文件 IO 阻塞主 isolate
        await Isolate.run(() => _writeGeoFiles(filesToWrite));
      }
    } catch (e) {
      exit(0);
    }
  }

  /// 在后台 isolate 中执行：先写临时文件再原子 rename，避免慢磁盘上 fsync 阻塞
  static Future<void> _writeGeoFiles(List<(String, Uint8List)> files) async {
    for (final (path, bytes) in files) {
      final tempFile = File('$path.tmp');
      await tempFile.writeAsBytes(bytes);
      await tempFile.rename(path);
    }
  }

  Future<bool> init({
    required ClashConfig clashConfig,
    required Config config,
  }) async {
    await _initGeo(clashConfig);
    final homeDirPath = await appPath.getHomeDirPath();
    return await clashInterface.init(homeDirPath);
  }

  shutdown() async {
    await clashInterface.shutdown();
  }

  FutureOr<bool> get isInit => clashInterface.isInit;

  FutureOr<String> validateConfig(String data) {
    return clashInterface.validateConfig(data);
  }

  Future<String> updateConfig(UpdateConfigParams updateConfigParams) async {
    return await clashInterface.updateConfig(updateConfigParams);
  }

  Future<List<Group>> getProxiesGroups() async {
    final proxiesRawString = await clashInterface.getProxies();
    return Isolate.run<List<Group>>(() {
      if (proxiesRawString.isEmpty) return [];
      final proxies = (json.decode(proxiesRawString) ?? {}) as Map;
      if (proxies.isEmpty) return [];
      final groupNames = [
        UsedProxy.GLOBAL.name,
        ...(proxies[UsedProxy.GLOBAL.name]["all"] as List).where((e) {
          final proxy = proxies[e] ?? {};
          return GroupTypeExtension.valueList.contains(proxy['type']);
        })
      ];
      final groupsRaw = groupNames.map((groupName) {
        final group = proxies[groupName];
        group["all"] = ((group["all"] ?? []) as List)
            .map(
              (name) => proxies[name],
            )
            .where((proxy) => proxy != null)
            .toList();
        return group;
      }).toList();
      return groupsRaw
          .map(
            (e) => Group.fromJson(e),
          )
          .toList();
    });
  }

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    return await clashInterface.changeProxy(changeProxyParams);
  }

  Future<List<Connection>> getConnections() async {
    final res = await clashInterface.getConnections();
    final connectionsData = json.decode(res) as Map;
    final connectionsRaw = connectionsData['connections'] as List? ?? [];
    // 顺手把规则命中 / ASN / GeoIP 这类扩展信息按 id 旁挂起来。
    // 走 codegen 模型加字段要同步两个生成文件,这里零侵入。
    // 连接列表本身是全量的,整体替换即可,不做增量。
    final extras = <String, ConnectionExtra>{};
    for (final item in connectionsRaw) {
      if (item is Map) {
        final id = item['id']?.toString();
        if (id != null && id.isNotEmpty) {
          extras[id] = ConnectionExtra.fromJson(
            Map<String, dynamic>.from(item),
          );
        }
      }
    }
    connectionExtraStore.replaceAll(extras);
    return connectionsRaw.map((e) => Connection.fromJson(e)).toList();
  }

  /// 即发即弃的调用:core 未就绪 / 已退出时直接放弃。
  ///
  /// 这些调用点(切换配置、界面按钮)从不 await,所以失败必须在内部消化,
  /// 否则每次都会冒出一个未处理的异步异常。
  void _bestEffort(FutureOr<dynamic> Function() action) {
    try {
      final result = action();
      if (result is Future) {
        unawaited(result.catchError((Object e) {
          debugPrint("best effort call failed ===> $e");
        }));
      }
    } catch (e) {
      debugPrint("best effort call failed ===> $e");
    }
  }

  closeConnection(String id) {
    _bestEffort(() => clashInterface.closeConnection(id));
  }

  closeConnections() {
    _bestEffort(() => clashInterface.closeConnections());
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    final externalProvidersRawString =
        await clashInterface.getExternalProviders();
    return Isolate.run<List<ExternalProvider>>(
      () {
        final externalProviders =
            (json.decode(externalProvidersRawString) as List<dynamic>)
                .map(
                  (item) => ExternalProvider.fromJson(item),
                )
                .toList();
        return externalProviders;
      },
    );
  }

  Future<ExternalProvider?> getExternalProvider(
      String externalProviderName) async {
    final externalProvidersRawString =
        await clashInterface.getExternalProvider(externalProviderName);
    if (externalProvidersRawString == null) {
      return null;
    }
    if (externalProvidersRawString.isEmpty) {
      return null;
    }
    return ExternalProvider.fromJson(json.decode(externalProvidersRawString));
  }

  Future<String> updateGeoData({
    required String geoType,
    required String geoName,
  }) {
    return clashInterface.updateGeoData(geoType: geoType, geoName: geoName);
  }

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) {
    return clashInterface.sideLoadExternalProvider(
        providerName: providerName, data: data);
  }

  Future<String> updateExternalProvider({
    required String providerName,
  }) async {
    return clashInterface.updateExternalProvider(providerName);
  }

  startListener() async {
    await clashInterface.startListener();
  }

  stopListener() async {
    await clashInterface.stopListener();
  }

  Future<Delay> getDelay(String proxyName) async {
    final data = await clashInterface.asyncTestDelay(proxyName);
    return Delay.fromJson(json.decode(data));
  }

  Future<SpeedResult> getSpeed(String proxyName, String url, int timeout) async {
    final data = await clashInterface.asyncTestSpeed(proxyName, url, timeout);
    return SpeedResult.fromJson(json.decode(data));
  }

  Future<Traffic> getTraffic(bool value) async {
    final trafficString = await clashInterface.getTraffic(value);
    return Traffic.fromMap(json.decode(trafficString));
  }

  Future<Traffic> getTotalTraffic(bool value) async {
    final totalTrafficString = await clashInterface.getTotalTraffic(value);
    return Traffic.fromMap(json.decode(totalTrafficString));
  }

  resetTraffic() {
    clashInterface.resetTraffic();
  }

  startLog() {
    clashInterface.startLog();
  }

  stopLog() {
    clashInterface.stopLog();
  }

  /// 读取 core 运行时内存 / GC 快照。
  ///
  /// core 未就绪时返回空快照,而不是抛错 —— 诊断页在 core 起来之前
  /// 被打开是常态。
  Future<CoreMemoryStats> getMemoryStats() async {
    final raw = await clashInterface.getMemoryStats();
    if (raw.isEmpty) return CoreMemoryStats.empty;
    try {
      return CoreMemoryStats.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return CoreMemoryStats.empty;
    }
  }

  /// 分流诊断:给定域名 / IP / host:port,返回命中的规则与落点。
  Future<RuleMatchResult> matchRule(String target) async {
    final raw = await clashInterface.matchRule(target);
    if (raw.isEmpty) return RuleMatchResult.empty;
    try {
      return RuleMatchResult.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return RuleMatchResult.empty;
    }
  }

  requestGc() {
    clashInterface.forceGc();
  }

  /// 轻量回收:只触发一次 GC,不把空闲页还给内核。
  ///
  /// 前台空闲路径专用(AdaptiveTimer 进入 idle)。那边的旧实现走的是
  /// requestGc -> FreeOSMemory,两次 STW 却换不来实际收益,故单列一条。
  lightGc() {
    _bestEffort(() => clashInterface.lightGc());
  }

  /// 前后台切换:core 据此调整 GC 百分比。
  setBackgroundMode(bool isBackground) {
    _bestEffort(() => clashInterface.setBackgroundMode(isBackground));
  }

  /// 切换 core 日志级别(0=debug … 4=silent)。
  setLogLevel(int level) {
    _bestEffort(() => clashInterface.setLogLevel(level));
  }
}

final clashCore = ClashCore();
