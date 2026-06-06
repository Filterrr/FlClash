import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/background_memory_manager.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/state/profile_controller.dart';
import 'package:fl_clash/state/backup_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common/common.dart';
import 'models/models.dart';

class AppController {
  final BuildContext context;
  late AppState appState;
  late AppFlowingState appFlowingState;
  late Config config;
  late ClashConfig clashConfig;
  late Function updateClashConfigDebounce;
  late Function updateGroupDebounce;
  late Function addCheckIpNumDebounce;
  late Function applyProfileDebounce;

  // 拆分出的子控制器
  late final ProfileController profileController;
  late final BackupController backupController;
  late Function savePreferencesDebounce;
  late Function changeProxyDebounce;

  AppController(this.context) {
    appState = context.read<AppState>();
    config = context.read<Config>();
    clashConfig = context.read<ClashConfig>();
    appFlowingState = context.read<AppFlowingState>();
    // 初始化子控制器
    profileController = ProfileController(context);
    backupController = BackupController(context);
    updateClashConfigDebounce = debounce<Function()>(() async {
      await updateClashConfig();
    });
    savePreferencesDebounce = debounce<Function()>(() async {
      await savePreferences();
    });
    applyProfileDebounce = debounce<Function()>(() async {
      await applyProfile(isPrue: true);
    });
    changeProxyDebounce = debounce((String groupName, String proxyName) async {
      await changeProxy(
        groupName: groupName,
        proxyName: proxyName,
      );
      await updateGroups();
    });
    addCheckIpNumDebounce = debounce(() {
      appState.checkIpNum++;
    });
    updateGroupDebounce = debounce(() async {
      await updateGroups();
    });
  }

  restartCore() async {
    await globalState.restartCore(
      appState: appState,
      clashConfig: clashConfig,
      config: config,
    );
  }

  updateStatus(bool isStart) async {
    if (isStart) {
      await globalState.handleStart();
      updateRunTime();
      updateTraffic();
      globalState.updateFunctionLists = [
        updateRunTime,
        updateTraffic,
      ];
      globalState.trafficUpdateCallback = updateTraffic;
      final currentLastModified =
          await config.getCurrentProfile()?.profileLastModified;
      if (currentLastModified == null ||
          globalState.lastProfileModified == null) {
        addCheckIpNumDebounce();
        return;
      }
      if (currentLastModified <= (globalState.lastProfileModified ?? 0)) {
        addCheckIpNumDebounce();
        return;
      }
      applyProfileDebounce();
    } else {
      await globalState.handleStop();
      await clashCore.resetTraffic();
      appFlowingState.traffics = [];
      appFlowingState.totalTraffic = Traffic();
      appFlowingState.runTime = null;
      await Future.delayed(
        Duration(milliseconds: 300),
      );
      addCheckIpNumDebounce();
    }
  }

  updateRunTime() {
    final startTime = globalState.startTime;
    if (startTime != null) {
      final startTimeStamp = startTime.millisecondsSinceEpoch;
      final nowTimeStamp = DateTime.now().millisecondsSinceEpoch;
      appFlowingState.runTime = nowTimeStamp - startTimeStamp;
    } else {
      appFlowingState.runTime = null;
    }
  }

  updateTraffic() {
    globalState.updateTraffic(
      config: config,
      appFlowingState: appFlowingState,
    );
  }

  addProfile(Profile profile) async {
    await profileController.addProfile(profile);
  }

  deleteProfile(String id) async {
    await profileController.deleteProfile(id);
  }

  updateProviders() {
    globalState.updateProviders(appState);
  }

  Future<void> updateProfile(Profile profile) async {
    await profileController.updateProfile(profile);
  }

  Future<void> updateClashConfig({bool isPatch = true}) async {
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    await commonScaffoldState?.loadingRun(() async {
      await globalState.updateClashConfig(
        appState: appState,
        clashConfig: clashConfig,
        config: config,
        isPatch: isPatch,
      );
    });
  }

  Future applyProfile({bool isPrue = false}) async {
    if (isPrue) {
      await globalState.applyProfile(
        appState: appState,
        config: config,
        clashConfig: clashConfig,
      );
    } else {
      final commonScaffoldState = globalState.homeScaffoldKey.currentState;
      if (commonScaffoldState?.mounted != true) return;
      await commonScaffoldState?.loadingRun(() async {
        await globalState.applyProfile(
          appState: appState,
          config: config,
          clashConfig: clashConfig,
        );
      });
    }
    addCheckIpNumDebounce();
  }

  changeProfile(String? value) async {
    if (value == config.currentProfileId) return;
    config.currentProfileId = value;
  }

  autoUpdateProfiles() async {
    await profileController.autoUpdateProfiles();
  }

  updateProfiles() async {
    await profileController.updateProfiles();
  }

  Future<void> updateGroups() async {
    await globalState.updateGroups(appState);
  }

  updateSystemColorSchemes(SystemColorSchemes systemColorSchemes) {
    appState.systemColorSchemes = systemColorSchemes;
  }

  savePreferences() async {
    debugPrint("[APP] savePreferences");
    await preferences.saveConfig(config);
    await preferences.saveClashConfig(clashConfig);
  }

  changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    await globalState.changeProxy(
      config: config,
      groupName: groupName,
      proxyName: proxyName,
    );
    addCheckIpNumDebounce();
  }

  handleBackOrExit() async {
    if (config.appSetting.minimizeOnExit) {
      if (system.isDesktop) {
        await savePreferencesDebounce();
      }
      await system.back();
    } else {
      await handleExit();
    }
  }

  handleExit() async {
    try {
      await updateStatus(false);
      await clashCore.shutdown();
      await clashService?.destroy();
      await proxy?.stopProxy();
      await savePreferences();
    } catch (_) {}
    system.exit();
  }

  autoCheckUpdate() async {
    if (!config.appSetting.autoCheckUpdate) return;
    final res = await request.checkForUpdate();
    checkUpdateResultHandle(data: res);
  }

  checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool handleError = false,
  }) async {
    if (data != null) {
      final tagName = data['tag_name'];
      final body = data['body'];
      final submits = other.parseReleaseBody(body);
      final textTheme = context.textTheme;
      globalState.showMessage(
        title: appLocalizations.discoverNewVersion,
        message: TextSpan(
          text: "$tagName \n",
          style: textTheme.headlineSmall,
          children: [
            TextSpan(
              text: "\n",
              style: textTheme.bodyMedium,
            ),
            for (final submit in submits)
              TextSpan(
                text: "- $submit \n",
                style: textTheme.bodyMedium,
              ),
          ],
        ),
        onTab: () {
          launchUrl(
            Uri.parse("https://github.com/$repository/releases/latest"),
          );
        },
        confirmText: appLocalizations.goDownload,
      );
    } else if (handleError) {
      globalState.showMessage(
        title: appLocalizations.checkUpdate,
        message: TextSpan(
          text: appLocalizations.checkUpdateError,
        ),
      );
    }
  }

  init() async {
    final isDisclaimerAccepted = await handlerDisclaimer();
    if (!isDisclaimerAccepted) {
      handleExit();
    }
    if (!config.appSetting.silentLaunch) {
      window?.show();
    }
    await globalState.initCore(
      appState: appState,
      clashConfig: clashConfig,
      config: config,
    );
    await _initStatus();
    autoUpdateProfiles();
    autoCheckUpdate();
    SubscriptionExpiryChecker.checkOnStartup(config.profiles);
  }

  _initStatus() async {
    if (Platform.isAndroid) {
      globalState.updateStartTime();
    }
    if (globalState.isStart) {
      await updateStatus(true);
    } else {
      await updateStatus(config.appSetting.autoRun);
    }
  }

  setDelay(Delay delay) {
    appState.setDelay(delay);
  }

  toPage(int index, {bool hasAnimate = false}) {
    if (index > appState.currentNavigationItems.length - 1) {
      return;
    }
    appState.currentLabel = appState.currentNavigationItems[index].label;
    if ((config.appSetting.isAnimateToPage || hasAnimate)) {
      globalState.pageController?.animateToPage(
        index,
        duration: kTabScrollDuration,
        curve: Curves.easeOut,
      );
    } else {
      globalState.pageController?.jumpToPage(index);
    }
  }

  toProfiles() {
    final index = appState.currentNavigationItems.indexWhere(
      (element) => element.label == "profiles",
    );
    if (index != -1) {
      toPage(index);
    }
  }

  initLink() {
    linkManager.initAppLinksListen(
      (url) {
        globalState.showMessage(
          title: "${appLocalizations.add}${appLocalizations.profile}",
          message: TextSpan(
            children: [
              TextSpan(text: appLocalizations.doYouWantToPass),
              TextSpan(
                text: " $url ",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: Theme.of(context).colorScheme.primary,
                ),
              ),
              TextSpan(
                  text:
                      "${appLocalizations.create}${appLocalizations.profile}"),
            ],
          ),
          onTab: () {
            addProfileFormURL(url);
          },
        );
      },
    );
  }

  showSnackBar(String message) {
    globalState.showSnackBar(context, message: message);
  }

  Future<bool> showDisclaimer() async {
    return await globalState.showCommonDialog<bool>(
          dismissible: false,
          child: AlertDialog(
            title: Text(appLocalizations.disclaimer),
            content: Container(
              width: dialogCommonWidth,
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  appLocalizations.disclaimerDesc,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop<bool>(false);
                },
                child: Text(appLocalizations.exit),
              ),
              TextButton(
                onPressed: () {
                  config.appSetting = config.appSetting.copyWith(
                    disclaimerAccepted: true,
                  );
                  Navigator.of(context).pop<bool>(true);
                },
                child: Text(appLocalizations.agree),
              )
            ],
          ),
        ) ??
        false;
  }

  Future<bool> handlerDisclaimer() async {
    if (config.appSetting.disclaimerAccepted) {
      return true;
    }
    return showDisclaimer();
  }

  addProfileFormURL(String url) async {
    if (globalState.navigatorKey.currentState?.canPop() ?? false) {
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    toProfiles();
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    final profile = await commonScaffoldState?.loadingRun<Profile>(
      () async {
        return await Profile.normal(
          url: url,
        ).update();
      },
      title: "${appLocalizations.add}${appLocalizations.profile}",
    );
    if (profile != null) {
      await addProfile(profile);
    }
  }

  addProfileFormFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    final bytes = platformFile?.bytes;
    if (bytes == null) {
      return null;
    }
    if (!context.mounted) return;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    toProfiles();
    final commonScaffoldState = globalState.homeScaffoldKey.currentState;
    if (commonScaffoldState?.mounted != true) return;
    final profile = await commonScaffoldState?.loadingRun<Profile?>(
      () async {
        await Future.delayed(const Duration(milliseconds: 300));
        return await Profile.normal(label: platformFile?.name).saveFile(bytes);
      },
      title: "${appLocalizations.add}${appLocalizations.profile}",
    );
    if (profile != null) {
      await addProfile(profile);
    }
  }

  addProfileFormQrCode() async {
    final url = await globalState.safeRun(picker.pickerConfigQRCode);
    if (url == null) return;
    addProfileFormURL(url);
  }

  updateViewWidth(double width) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appState.viewWidth = width;
    });
  }

  List<Proxy> _sortOfName(List<Proxy> proxies) {
    return List.of(proxies)
      ..sort(
        (a, b) => other.sortByChar(
          other.getPinyin(a.name),
          other.getPinyin(b.name),
        ),
      );
  }

  List<Proxy> _sortOfDelay(List<Proxy> proxies) {
    return proxies = List.of(proxies)
      ..sort(
        (a, b) {
          final aDelay = appState.getDelay(a.name);
          final bDelay = appState.getDelay(b.name);
          if (aDelay == null && bDelay == null) {
            return 0;
          }
          if (aDelay == null || aDelay == -1) {
            return 1;
          }
          if (bDelay == null || bDelay == -1) {
            return -1;
          }
          return aDelay.compareTo(bDelay);
        },
      );
  }

  List<Proxy> getSortProxies(List<Proxy> proxies) {
    return switch (config.proxiesStyle.sortType) {
      ProxiesSortType.none => proxies,
      ProxiesSortType.delay => _sortOfDelay(proxies),
      ProxiesSortType.name => _sortOfName(proxies),
    };
  }

  String getCurrentSelectedName(String groupName) {
    final group = appState.getGroupWithName(groupName);
    return group?.getCurrentSelectedName(
            config.currentSelectedMap[groupName] ?? '') ??
        '';
  }

  updateTun() {
    clashConfig.tun = clashConfig.tun.copyWith(
      enable: !clashConfig.tun.enable,
    );
  }

  updateSystemProxy() {
    config.networkProps = config.networkProps.copyWith(
      systemProxy: !config.networkProps.systemProxy,
    );
  }

  updateStart() {
    updateStatus(!appFlowingState.isStart);
  }

  changeMode(Mode mode) {
    clashConfig.mode = mode;
    if (mode == Mode.global) {
      config.updateCurrentGroupName(GroupName.GLOBAL.name);
    }
    addCheckIpNumDebounce();
  }

  updateAutoLaunch() {
    config.appSetting = config.appSetting.copyWith(
      autoLaunch: !config.appSetting.autoLaunch,
    );
  }

  updateVisible() async {
    final visible = await window?.isVisible();
    if (visible != null && !visible) {
      window?.show();
      backgroundMemoryManager.onWindowShown();
    } else {
      window?.hide();
      backgroundMemoryManager.onWindowHidden();
    }
  }

  updateMode() {
    final index = Mode.values.indexWhere((item) => item == clashConfig.mode);
    if (index == -1) {
      return;
    }
    final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
    clashConfig.mode = Mode.values[nextIndex];
  }

  Future<bool> exportLogs() async {
    final logsRaw = appFlowingState.logs.map(
      (item) => item.toString(),
    );
    final data = await Isolate.run<List<int>>(() async {
      final logsRawString = logsRaw.join("\n");
      return utf8.encode(logsRawString);
    });
    return await picker.saveFile(
          other.logFile,
          Uint8List.fromList(data),
        ) !=
        null;
  }

  Future<List<int>> backupData() async {
    return await backupController.backupData();
  }

  updateTray([bool focus = false]) async {
    tray.update(
      appState: appState,
      appFlowingState: appFlowingState,
      config: config,
      clashConfig: clashConfig,
      focus: focus,
    );
  }

  recoveryData(
    List<int> data,
    RecoveryOption recoveryOption,
  ) async {
    await backupController.recoveryData(data, recoveryOption);
  }

  /// 对当前配置的代理节点进行去重
  /// 返回被移除的重复节点数量
  Future<int> deduplicateProfileNodes() async {
    return await profileController.deduplicateProfileNodes();
  }

  clearEffect(String profileId) async {
    await profileController.clearEffect(profileId);
  }
}
