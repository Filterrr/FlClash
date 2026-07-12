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

  Future<void> _initGeo() async {
    final homePath = await appPath.getHomeDirPath();
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    const geoFileNameList = [
      mmdbFileName,
      geoIpFileName,
      geoSiteFileName,
      asnFileName,
    ];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(
          join(homePath, geoFileName),
        );
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final data = await rootBundle.load('assets/data/$geoFileName');
        List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
      }
    } catch (e, stackTrace) {
      // 降级：地理数据提取失败时仅记录日志并跳过，不再直接 exit(0) 终止整个应用
      debugPrint('Failed to initialize geo data: $e\n$stackTrace');
    }
  }

  Future<bool> init({
    required ClashConfig clashConfig,
    required Config config,
  }) async {
    await _initGeo();
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
      final raw = json.decode(proxiesRawString);
      // FFI 返回结构可能异常：解码失败或非 Map 时降级为空，避免 CastError
      if (raw is! Map) return [];
      final proxies = raw.cast<String, dynamic>();
      if (proxies.isEmpty) return [];
      final globalGroup = proxies[UsedProxy.GLOBAL.name];
      if (globalGroup is! Map) return [];
      final groupNames = [
        UsedProxy.GLOBAL.name,
        ...((globalGroup["all"] as List? ?? [])
            .where((e) {
              final proxy = proxies[e] ?? {};
              return GroupTypeExtension.valueList.contains(proxy['type']);
            })
            .toList())
      ];
      final groupsRaw = groupNames.map((groupName) {
        final group = proxies[groupName];
        if (group is Map) {
          group["all"] = ((group["all"] as List? ?? []))
              .map(
                (name) => proxies[name],
              )
              .where((proxy) => proxy != null)
              .toList();
        }
        return group;
      }).toList();
      return groupsRaw
          .whereType<Map>()
          .map(
            (e) => Group.fromJson(e.cast<String, dynamic>()),
          )
          .toList();
    });
  }

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    return await clashInterface.changeProxy(changeProxyParams);
  }

  Future<List<Connection>> getConnections() async {
    final res = await clashInterface.getConnections();
    if (res.isEmpty) return [];
    final raw = json.decode(res);
    // 与 getProxiesGroups 同理：FFI 返回异常时降级，避免 FormatException / CastError
    if (raw is! Map) return [];
    final connectionsData = raw.cast<String, dynamic>();
    final connectionsRaw = connectionsData['connections'] as List? ?? [];
    return connectionsRaw
        .whereType<Map>()
        .map((e) => Connection.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  closeConnection(String id) {
    clashInterface.closeConnection(id);
  }

  closeConnections() {
    clashInterface.closeConnections();
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    final externalProvidersRawString =
        await clashInterface.getExternalProviders();
    return Isolate.run<List<ExternalProvider>>(
      () {
        final raw = json.decode(externalProvidersRawString);
        if (raw is! List) return <ExternalProvider>[];
        final externalProviders = raw
            .whereType<Map>()
            .map(
              (item) => ExternalProvider.fromJson(item.cast<String, dynamic>()),
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
    if (externalProvidersRawString == null ||
        externalProvidersRawString.isEmpty) {
      return null;
    }
    final raw = json.decode(externalProvidersRawString);
    if (raw is! Map) return null;
    return ExternalProvider.fromJson(raw.cast<String, dynamic>());
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
    if (data.isEmpty) return Delay.fromJson(const {});
    final raw = json.decode(data);
    if (raw is! Map) return Delay.fromJson(const {});
    return Delay.fromJson(raw.cast<String, dynamic>());
  }

  Future<SpeedResult> getSpeed(String proxyName, String url, int timeout) async {
    final data = await clashInterface.asyncTestSpeed(proxyName, url, timeout);
    if (data.isEmpty) return SpeedResult.fromJson(const {});
    final raw = json.decode(data);
    if (raw is! Map) return SpeedResult.fromJson(const {});
    return SpeedResult.fromJson(raw.cast<String, dynamic>());
  }

  Future<Traffic> getTraffic(bool value) async {
    final trafficString = await clashInterface.getTraffic(value);
    final raw = json.decode(trafficString.isEmpty ? '{}' : trafficString);
    if (raw is! Map) return Traffic.fromMap(const {});
    return Traffic.fromMap(raw.cast<String, dynamic>());
  }

  Future<Traffic> getTotalTraffic(bool value) async {
    final totalTrafficString = await clashInterface.getTotalTraffic(value);
    final raw = json.decode(totalTrafficString.isEmpty ? '{}' : totalTrafficString);
    if (raw is! Map) return Traffic.fromMap(const {});
    return Traffic.fromMap(raw.cast<String, dynamic>());
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

  requestGc() {
    clashInterface.forceGc();
  }
}

final clashCore = ClashCore();
