import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';

class Request {
  late final Dio _dio;
  String? userAgent;

  Request() {
    _dio = Dio(BaseOptions(
      validateStatus: (status) => status != null && status < 500,
    ));
  }

  Future<Response> getFileResponseForUrl(String url) async {
    try {
      final response = await _dio
          .get(
            url,
            options: Options(
              headers: {
                "User-Agent": globalState.appController.clashConfig.globalUa
              },
              responseType: ResponseType.bytes,
            ),
          )
          .timeout(
            httpTimeoutDuration * 6,
          );
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'HTTP ${response.statusCode}',
        );
      }
      return response;
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        message: e.toString(),
      );
    }
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    try {
      final response = await _dio.get<Uint8List>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      if (response.statusCode != null && response.statusCode! >= 400) {
        return null;
      }
      final data = response.data;
      if (data == null) return null;
      return MemoryImage(data);
    } catch (e) {
      debugPrint("getImage error ===> $e");
      return null;
    }
  }

  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final response = await _dio
          .get(
            "https://api.github.com/repos/$repository/releases/latest",
            options: Options(
              responseType: ResponseType.json,
            ),
          )
          .timeout(httpTimeoutDuration);
      if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.failed,
        );
      }
      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'];
      if (tagName is! String || tagName.trim().isEmpty) {
        return const UpdateCheckResult(
          status: UpdateCheckStatus.failed,
        );
      }
      final version = globalState.packageInfo.fullVersion;
      final compare = other.compareVersions(tagName, version);
      if (compare > 0) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.available,
          data: data,
        );
      }
      return const UpdateCheckResult(
        status: UpdateCheckStatus.upToDate,
      );
    } catch (e) {
      debugPrint("checkForUpdate error ===> $e");
      return const UpdateCheckResult(
        status: UpdateCheckStatus.failed,
      );
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    "https://ipwho.is/": IpInfo.fromIpwhoIsJson,
    "https://api.ip.sb/geoip/": IpInfo.fromIpSbJson,
    "https://ipapi.co/json/": IpInfo.fromIpApiCoJson,
    "https://ipinfo.io/json/": IpInfo.fromIpInfoIoJson,
  };

  Future<IpInfo?> checkIp({CancelToken? cancelToken}) async {
    for (final source in _ipInfoSources.entries) {
      try {
        final response = await _dio
            .get<Map<String, dynamic>>(source.key, cancelToken: cancelToken)
            .timeout(httpTimeoutDuration);
        if (response.statusCode != 200 || response.data == null) {
          continue;
        }
        return source.value(response.data!);
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          throw "cancelled";
        }
        debugPrint("checkIp error ===> $e");
      }
    }
    return null;
  }

  Future<bool> pingHelper() async {
    try {
      final response = await _dio
          .get(
            "http://$localhost:$helperPort/ping",
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String) == helperTag;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper(String arg) async {
    try {
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/start",
            data: {
              "path": appPath.corePath,
              "arg": arg,
            },
            options: Options(
              responseType: ResponseType.plain,
              contentType: 'application/json',
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopCoreByHelper() async {
    try {
      final response = await _dio
          .post(
            "http://$localhost:$helperPort/stop",
            options: Options(
              responseType: ResponseType.plain,
            ),
          )
          .timeout(
            const Duration(
              milliseconds: 2000,
            ),
          );
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      final data = response.data as String;
      return data.isEmpty;
    } catch (_) {
      return false;
    }
  }
}

final request = Request();
