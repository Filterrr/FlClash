import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/plugins/vpn.dart';
import 'package:fl_clash/state.dart';

/// 核心生命周期管理
/// 负责 Clash 核心的初始化、启动、停止、重启等操作
mixin CoreManager on GlobalStateBase {
  Future<void> initCore({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
  }) async {
    await globalState.init(
      appState: appState,
      config: config,
      clashConfig: clashConfig,
    );
    await applyProfile(
      appState: appState,
      config: config,
      clashConfig: clashConfig,
    );
  }

  Future<void> updateClashConfig({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    await config.currentProfile?.checkAndUpdate();
    final useClashConfig = clashConfig.copyWith();
    if (clashConfig.tun.enable != globalState.lastTunEnable &&
        globalState.lastTunEnable == false &&
        !Platform.isAndroid) {
      final code = await system.authorizeCore();
      switch (code) {
        case AuthorizeCode.none:
          break;
        case AuthorizeCode.success:
          globalState.lastTunEnable = useClashConfig.tun.enable;
          await restartCore(
            appState: appState,
            clashConfig: clashConfig,
            config: config,
          );
          return;
        case AuthorizeCode.error:
          useClashConfig.tun = useClashConfig.tun.copyWith(
            enable: false,
          );
      }
    }
    if (config.appSetting.openLogs) {
      clashCore.startLog();
    } else {
      clashCore.stopLog();
    }
    final res = await clashCore.updateConfig(
      UpdateConfigParams(
        profileId: config.currentProfileId ?? "",
        config: useClashConfig,
        params: ConfigExtendedParams(
          isPatch: isPatch,
          isCompatible: true,
          selectedMap: config.currentSelectedMap,
          overrideDns: config.overrideDns,
          testUrl: config.appSetting.testUrl,
          udp: useClashConfig.udp,
        ),
      ),
    );
    if (res.isNotEmpty) throw res;
    globalState.lastTunEnable = useClashConfig.tun.enable;
    globalState.lastProfileModified =
        await config.getCurrentProfile()?.profileLastModified;
  }

  handleStart() async {
    await clashCore.startListener();
    if (globalState.isVpnService) {
      await vpn?.startVpn();
      globalState.startListenUpdate();
      return;
    }
    globalState.startTime ??= DateTime.now();
    await service?.init();
    globalState.startListenUpdate();
  }

  restartCore({
    required AppState appState,
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    await clashService?.startCore();
    await initCore(
      appState: appState,
      clashConfig: clashConfig,
      config: config,
    );
    if (globalState.isStart) {
      await handleStart();
    }
  }

  Future handleStop() async {
    globalState.startTime = null;
    await clashCore.stopListener();
    clashLib?.stopTun();
    await service?.destroy();
    globalState.stopListenUpdate();
  }

  Future applyProfile({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    clashCore.requestGc();
    await updateClashConfig(
      appState: appState,
      clashConfig: clashConfig,
      config: config,
      isPatch: false,
    );
    await updateGroups(appState);
    await updateProviders(appState);
  }

  updateProviders(AppState appState) async {
    appState.providers = await clashCore.getExternalProviders();
  }

  Future<void> updateGroups(AppState appState) async {
    appState.groups = await clashCore.getProxiesGroups();
  }

  changeProxy({
    required Config config,
    required String groupName,
    required String proxyName,
  }) async {
    await clashCore.changeProxy(
      ChangeProxyParams(
        groupName: groupName,
        proxyName: proxyName,
      ),
    );
    if (config.appSetting.closeConnections) {
      clashCore.closeConnections();
    }
  }
}

/// 流量与连接管理
/// 负责流量更新、运行时间等操作
mixin TrafficManager on GlobalStateBase {
  updateTraffic({
    required Config config,
    AppFlowingState? appFlowingState,
  }) async {
    final onlyProxy = config.appSetting.onlyProxy;
    final traffic = await clashCore.getTraffic(onlyProxy);
    if (Platform.isAndroid && globalState.isVpnService == true) {
      vpn?.startForeground(
        title: clashLib?.getCurrentProfileName() ?? "",
        content: "$traffic",
      );
    } else {
      if (appFlowingState != null) {
        appFlowingState.addTraffic(traffic);
        appFlowingState.totalTraffic =
            await clashCore.getTotalTraffic(onlyProxy);
      }
    }
  }
}

/// GlobalState 基类，提供共享属性
abstract class GlobalStateBase {
  AdaptiveTimer? adaptiveTimer;
  var isVpnService = false;
  DateTime? startTime;
  List<Function> updateFunctionLists = [];
  Function? _trafficUpdateCallback;
  bool lastTunEnable = false;
  int? lastProfileModified;

  bool get isStart => startTime != null && startTime!.isBeforeNow;

  set trafficUpdateCallback(Function? callback) =>
      _trafficUpdateCallback = callback;

  void startListenUpdate() {}
  void stopListenUpdate() {}
}
