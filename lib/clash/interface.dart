import 'dart:async';

import 'package:fl_clash/models/models.dart';

mixin ClashInterface {
  FutureOr<bool> init(String homeDir);

  FutureOr<void> shutdown();

  FutureOr<bool> get isInit;

  forceGc();

  FutureOr<String> validateConfig(String data);

  Future<String> asyncTestDelay(String proxyName);

  Future<String> asyncTestSpeed(String proxyName, String url, int timeout);

  FutureOr<String> updateConfig(UpdateConfigParams updateConfigParams);

  FutureOr<String> getProxies();

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams);

  Future<bool> startListener();

  Future<bool> stopListener();

  FutureOr<String> getExternalProviders();

  FutureOr<String>? getExternalProvider(String externalProviderName);

  Future<String> updateGeoData({
    required String geoType,
    required String geoName,
  });

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  });

  Future<String> updateExternalProvider(String providerName);

  FutureOr<String> getTraffic(bool value);

  FutureOr<String> getTotalTraffic(bool value);

  resetTraffic();

  startLog();

  stopLog();

  /// 轻量回收:只触发一次 GC,不把空闲页还给内核。前台高频路径用。
  lightGc();

  /// 前后台切换:core 据此调整 GC 百分比(后台更积极)。
  setBackgroundMode(bool isBackground);

  /// 切换 core 日志级别。取值与 LogLevel 枚举同序(0=debug … 4=silent)。
  setLogLevel(int level);

  FutureOr<String> getConnections();

  FutureOr<bool> closeConnection(String id);

  FutureOr<bool> closeConnections();
}
