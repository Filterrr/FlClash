import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/plugins/vpn.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'application.dart';
import 'common/common.dart';
import 'l10n/l10n.dart';
import 'models/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  clashLib?.initMessage();

  // 并行化独立的启动任务
  final results = await Future.wait<dynamic>([
    PackageInfo.fromPlatform(),
    system.version,
    preferences.getConfig(),
    preferences.getClashConfig(),
  ]);
  globalState.packageInfo = results[0] as PackageInfo;
  final version = results[1] as int;
  final config = (results[2] as Config?) ?? Config();
  final clashConfig = (results[3] as ClashConfig?) ?? ClashConfig();

  // 本地化加载依赖 config，需在 config 之后
  await AppLocalizations.load(
    other.getLocaleForString(config.appSetting.locale) ??
        WidgetsBinding.instance.platformDispatcher.locale,
  );

  // 平台初始化可并行
  await Future.wait<dynamic>([
    android?.init() ?? Future.value(),
    window?.init(config.windowProps, version) ?? Future.value(),
  ]);

  final appState = AppState(
    mode: clashConfig.mode,
    version: version,
    selectedMap: config.currentSelectedMap,
  );
  final appFlowingState = AppFlowingState();
  appState.navigationItems = navigation.getItems(
    openLogs: config.appSetting.openLogs,
    hasProxies: false,
  );
  tray.update(
    appState: appState,
    appFlowingState: appFlowingState,
    config: config,
    clashConfig: clashConfig,
  );
  HttpOverrides.global = FlClashHttpOverrides();
  runAppWithPreferences(
    const Application(),
    appState: appState,
    appFlowingState: appFlowingState,
    config: config,
    clashConfig: clashConfig,
  );
}

@pragma('vm:entry-point')
Future<void> vpnService() async {
  WidgetsFlutterBinding.ensureInitialized();
  globalState.isVpnService = true;
  globalState.packageInfo = await PackageInfo.fromPlatform();
  final version = await system.version;
  final config = await preferences.getConfig() ?? Config();
  final clashConfig = await preferences.getClashConfig() ?? ClashConfig();
  await AppLocalizations.load(
    other.getLocaleForString(config.appSetting.locale) ??
        WidgetsBinding.instance.platformDispatcher.locale,
  );

  final appState = AppState(
    mode: clashConfig.mode,
    selectedMap: config.currentSelectedMap,
    version: version,
  );

  await globalState.init(
    appState: appState,
    config: config,
    clashConfig: clashConfig,
  );

  await app?.tip(appLocalizations.startVpn);

  globalState
      .updateClashConfig(
    appState: appState,
    clashConfig: clashConfig,
    config: config,
    isPatch: false,
  )
      .then(
    (_) async {
      await globalState.handleStart();

      tile?.addListener(
        TileListenerWithVpn(
          onStop: () async {
            await app?.tip(appLocalizations.stopVpn);
            await globalState.handleStop();
            clashCore.shutdown();
            exit(0);
          },
        ),
      );

      // 使用 AdaptiveTimer 替代硬编码的更新列表，降低后台 CPU 唤醒频率
      globalState.startListenUpdate();
      globalState.updateFunctionLists = [
        () {
          globalState.updateTraffic(config: config);
        }
      ];
    },
  );

  vpn?.setServiceMessageHandler(
    ServiceMessageHandler(
      onProtect: (Fd fd) async {
        await vpn?.setProtect(fd.value);
        clashLib?.setFdMap(fd.id);
      },
      onProcess: (ProcessData process) async {
        final packageName = await vpn?.resolverProcess(process);
        clashLib?.setProcessMap(
          ProcessMapItem(
            id: process.id,
            value: packageName ?? "",
          ),
        );
      },
      onLoaded: (String groupName) {
        final currentSelectedMap = config.currentSelectedMap;
        final proxyName = currentSelectedMap[groupName];
        if (proxyName == null) return;
        globalState.changeProxy(
          config: config,
          groupName: groupName,
          proxyName: proxyName,
        );
      },
    ),
  );
}

@immutable
class ServiceMessageHandler with ServiceMessageListener {
  final Function(Fd fd) _onProtect;
  final Function(ProcessData process) _onProcess;
  final Function(String providerName) _onLoaded;

  const ServiceMessageHandler({
    required Function(Fd fd) onProtect,
    required Function(ProcessData process) onProcess,
    required Function(String providerName) onLoaded,
  })  : _onProtect = onProtect,
        _onProcess = onProcess,
        _onLoaded = onLoaded;

  @override
  onProtect(Fd fd) {
    _onProtect(fd);
  }

  @override
  onProcess(ProcessData process) {
    _onProcess(process);
  }

  @override
  onLoaded(String providerName) {
    _onLoaded(providerName);
  }
}

@immutable
class TileListenerWithVpn with TileListener {
  final Function() _onStop;

  const TileListenerWithVpn({
    required Function() onStop,
  }) : _onStop = onStop;

  @override
  void onStop() {
    _onStop();
  }
}
