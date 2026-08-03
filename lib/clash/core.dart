import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/clash/interface.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
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
    return connectionsRaw.map((e) => Connection.fromJson(e)).toList();
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

  requestGc() {
    clashInterface.forceGc();
  }
}

final clashCore = ClashCore();
