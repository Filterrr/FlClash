import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/archive.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/background_memory_manager.dart';
import 'package:fl_clash/models/update.dart';
import 'package:fl_clash/services/update_service.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
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
  late Function savePreferencesDebounce;
  late Function changeProxyDebounce;

  AppController(this.context) {
    appState = context.read<AppState>();
    config = context.read<Config>();
    clashConfig = context.read<ClashConfig>();
    appFlowingState = context.read<AppFlowingState>();
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
    config.setProfile(profile);
    if (config.currentProfileId != null) return;
    await changeProfile(profile.id);
  }

  deleteProfile(String id) async {
    config.deleteProfileById(id);
    clearEffect(id);
    if (config.currentProfileId == id) {
      if (config.profiles.isNotEmpty) {
        final updateId = config.profiles.first.id;
        changeProfile(updateId);
      } else {
        changeProfile(null);
        updateStatus(false);
      }
    }
  }

  updateProviders() {
    globalState.updateProviders(appState);
  }

  Future<void> updateProfile(Profile profile) async {
    final newProfile = await profile.update();
    config.setProfile(
      newProfile.copyWith(isUpdating: false),
    );
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
    for (final profile in config.profiles) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(
            profile.autoUpdateDuration,
          )
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        await updateProfile(profile);
      } catch (e) {
        appFlowingState.addLog(
          Log(
            logLevel: LogLevel.info,
            payload: e.toString(),
          ),
        );
      }
    }
  }

  updateProfiles() async {
    for (final profile in config.profiles) {
      if (profile.type == ProfileType.file) {
        continue;
      }
      await updateProfile(profile);
    }
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
    } catch (_) {}
    // 单独处理偏好保存，避免其失败被上面的 catch 静默吞掉导致配置丢失
    try {
      await savePreferences();
    } catch (e) {
      debugPrint('Failed to save preferences on exit: $e');
    }
    system.exit();
  }

  autoCheckUpdate() async {
    if (!config.appSetting.autoCheckUpdate) return;
    final result = await request.checkForUpdate();
    handleUpdateCheckResult(
      result: result,
      manual: false,
    );
  }

  handleUpdateCheckResult({
    required UpdateCheckResult result,
    required bool manual,
  }) {
    switch (result.status) {
      case UpdateCheckStatus.available:
        startInAppUpdate(
          data: result.data,
          handleError: manual,
          showDialog: true,
          dismissible: !manual,
        );
        return;
      case UpdateCheckStatus.upToDate:
        if (!manual) return;
        globalState.showMessage(
          title: appLocalizations.checkUpdate,
          message: TextSpan(
            text: appLocalizations.checkUpdateError,
          ),
        );
        return;
      case UpdateCheckStatus.failed:
        if (!manual) return;
        globalState.showMessage(
          title: appLocalizations.checkUpdate,
          message: TextSpan(
            text: appLocalizations.checkError,
          ),
        );
        return;
    }
  }

  checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool handleError = false,
  }) async {
    if (data != null) {
      final tagName = data['tag_name'] as String? ?? '';
      final version = normalizeVersion(tagName);
      final body = (data['body'] ?? '') as String;
      final paragraphs = body
          .split('\n')
          .where((s) => s.trim().isNotEmpty)
          .toList();
      final publishedAt = data['published_at'] as String? ?? '';
      final dateText = publishedAt.isNotEmpty
          ? (() {
              final dt = DateTime.tryParse(publishedAt);
              if (dt == null) return '';
              final y = dt.year.toString();
              final m = dt.month.toString().padLeft(2, '0');
              final d = dt.day.toString().padLeft(2, '0');
              return '$y-$m-$d';
            })()
          : '';
      final textTheme = context.textTheme;
      globalState.showMessage(
        title: appLocalizations.discoverNewVersion,
        message: TextSpan(
          text: "v$version\n",
          style: textTheme.headlineSmall,
          children: [
            if (dateText.isNotEmpty)
              TextSpan(
                text: "$dateText\n\n",
                style: textTheme.bodySmall,
              )
            else
              TextSpan(
                text: "\n",
                style: textTheme.bodyMedium,
              ),
            for (final p in paragraphs)
              TextSpan(
                text: "$p\n",
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

  /// 启动应用内更新流程。
  /// [data] 是 GitHub release API 返回的完整 JSON。
  /// [handleError] 为 true 时,无更新也显示提示(用户手动检查场景)。
  /// [showDialog] 为 true 时显示 UpdateDialog;
  /// 为 false 时只显示简单提示(降级到 checkUpdateResultHandle)。
  /// [dismissible] 为 true 时对话框可点击外部关闭(自动检查场景)。
  startInAppUpdate({
    required Map<String, dynamic>? data,
    bool handleError = false,
    bool showDialog = true,
    bool dismissible = false,
  }) async {
    if (data == null) {
      if (handleError) {
        globalState.showMessage(
          title: appLocalizations.checkUpdate,
          message: TextSpan(
            text: appLocalizations.checkUpdateError,
          ),
        );
      }
      return;
    }

    if (!showDialog) {
      checkUpdateResultHandle(data: data, handleError: handleError);
      return;
    }

    final info = updateService.parseReleaseInfo(data);
    final asset = updateService.selectAssetForCurrentPlatform(info);
    if (asset == null) {
      // 当前平台暂不支持应用内更新,降级到浏览器下载提示。
      checkUpdateResultHandle(data: data, handleError: handleError);
      return;
    }

    final state = ValueNotifier<UpdateDialogState>(
      const UpdateDialogState(status: UpdateStatus.available),
    );
    CancelToken? cancelToken;

    Future<void> startFlow() async {
      cancelToken = CancelToken();
      await _runUpdateFlow(
        info: info,
        asset: asset,
        state: state,
        cancelToken: cancelToken!,
      );
    }

    await showUpdateDialog(
      context: context,
      updateInfo: info,
      state: state,
      dismissible: dismissible,
      onUpdate: startFlow,
      onRetry: startFlow,
      onRestart: () {
        updateService.restart();
      },
      onCancel: () {
        final token = cancelToken;
        if (token != null) {
          _cancelUpdate(cancelToken: token, state: state);
        }
        globalState.navigatorKey.currentState?.pop();
      },
    );
  }

  /// 实际执行 下载 → 校验 → 安装 流程。
  /// 通过 [state] 驱动对话框 UI 切换:
  /// downloading → verifying → installing → (Windows: 进程退出)
  ///                                  → (Android: readyToRestart)
  /// 任意阶段失败时切换为 failed。
  _runUpdateFlow({
    required UpdateInfo info,
    required UpdateAsset asset,
    required ValueNotifier<UpdateDialogState> state,
    required CancelToken cancelToken,
  }) async {
    state.value = state.value.copyWith(
      status: UpdateStatus.downloading,
      progress: null,
      errorMessage: null,
    );
    try {
      final filePath = await updateService.download(
        asset: asset,
        cancelToken: cancelToken,
        onProgress: (p) {
          state.value = state.value.copyWith(
            status: UpdateStatus.downloading,
            progress: p,
          );
        },
      );

      state.value = state.value.copyWith(
        status: UpdateStatus.verifying,
        progress: null,
      );
      final ok = await updateService.verifySha256(
        filePath,
        info.sha256Map[asset.name],
      );
      if (!ok) {
        throw UpdateException('sha256 mismatch', UpdateStatus.verifying);
      }

      state.value = state.value.copyWith(
        status: UpdateStatus.installing,
      );

      if (Platform.isWindows) {
        // install() 在 Windows 上会 exit(0),必须先释放 VPN/代理/配置。
        try {
          await updateStatus(false);
          await clashCore.shutdown();
          await clashService?.destroy();
          await proxy?.stopProxy();
          await savePreferences();
        } catch (_) {}
        await updateService.install(filePath);
        // 进程已在 install 中退出,以下代码不会执行。
        return;
      }

      // Android: install 触发系统安装界面,不退出应用。
      await updateService.install(filePath);
      state.value = state.value.copyWith(
        status: UpdateStatus.readyToRestart,
      );
    } on UpdateException catch (e) {
      state.value = state.value.copyWith(
        status: UpdateStatus.failed,
        errorMessage: e.message,
      );
    } catch (e) {
      state.value = state.value.copyWith(
        status: UpdateStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// 取消更新(用户点击取消按钮)。
  /// 仅中断进行中的下载;对话框的关闭由调用方负责。
  _cancelUpdate({
    required CancelToken cancelToken,
    required ValueNotifier<UpdateDialogState> state,
  }) {
    if (!cancelToken.isCancelled) {
      cancelToken.cancel();
    }
  }

  init() async {
    final isDisclaimerAccepted = await handlerDisclaimer();
    if (!isDisclaimerAccepted) {
      await handleExit();
      return;
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

  List<Proxy> _sortOfSpeed(List<Proxy> proxies) {
    return List.of(proxies)
      ..sort(
        (a, b) {
          final aSpeed = appState.getSpeed(a.name);
          final bSpeed = appState.getSpeed(b.name);
          if (aSpeed == null && bSpeed == null) {
            return 0;
          }
          if (aSpeed == null || aSpeed == -1) {
            return 1;
          }
          if (bSpeed == null || bSpeed == -1) {
            return -1;
          }
          return bSpeed.compareTo(aSpeed);
        },
      );
  }

  List<Proxy> getSortProxies(List<Proxy> proxies) {
    return switch (config.proxiesStyle.sortType) {
      ProxiesSortType.none => proxies,
      ProxiesSortType.delay => _sortOfDelay(proxies),
      ProxiesSortType.name => _sortOfName(proxies),
      ProxiesSortType.speed => _sortOfSpeed(proxies),
    };
  }

  String getCurrentSelectedName(String groupName) {
    final group = appState.getGroupWithName(groupName);
    return group?.getCurrentSelectedName(
            config.currentSelectedMap[groupName] ?? '') ??
        '';
  }

  clearEffect(String profileId) async {
    final profilePath = await appPath.getProfilePath(profileId);
    final providersPath = await appPath.getProvidersPath(profileId);
    return await Isolate.run(() async {
      if (profilePath != null) {
        await File(profilePath).delete(recursive: true);
      }
      if (providersPath != null) {
        await File(providersPath).delete(recursive: true);
      }
    });
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
    final homeDirPath = await appPath.getHomeDirPath();
    final profilesPath = await appPath.getProfilesPath();
    final configJson = config.toJson();
    final clashConfigJson = clashConfig.toJson();
    return Isolate.run<List<int>>(() async {
      final archive = Archive();
      archive.add("config.json", configJson);
      archive.add("clashConfig.json", clashConfigJson);
      await archive.addDirectoryToArchive(profilesPath, homeDirPath);
      final zipEncoder = ZipEncoder();
      return zipEncoder.encode(archive) ?? [];
    });
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
    final archive = await Isolate.run<Archive>(() {
      final zipDecoder = ZipDecoder();
      return zipDecoder.decodeBytes(data);
    });
    final homeDirPath = await appPath.getHomeDirPath();
    final configs =
        archive.files.where((item) => item.name.endsWith(".json")).toList();
    final profiles =
        archive.files.where((item) => !item.name.endsWith(".json"));
    final configIndex =
        configs.indexWhere((config) => config.name == "config.json");
    final clashConfigIndex =
        configs.indexWhere((config) => config.name == "clashConfig.json");
    if (configIndex == -1 || clashConfigIndex == -1) {
      throw "invalid backup.zip";
    }
    final configFile = configs[configIndex];
    final clashConfigFile = configs[clashConfigIndex];
    // 先解析并校验配置，失败则在写入任何 profile 文件之前抛出，避免部分恢复
    late final Config tempConfig;
    late final ClashConfig tempClashConfig;
    try {
      tempConfig = Config.fromJson(
        json.decode(
          utf8.decode(configFile.content),
        ),
      );
      tempClashConfig = ClashConfig.fromJson(
        json.decode(
          utf8.decode(clashConfigFile.content),
        ),
      );
    } catch (e) {
      throw "invalid backup config: $e";
    }
    for (final profile in profiles) {
      final filePath = join(homeDirPath, profile.name);
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(profile.content);
    }
    if (recoveryOption == RecoveryOption.onlyProfiles) {
      config.update(tempConfig, RecoveryOption.onlyProfiles);
    } else {
      config.update(tempConfig, RecoveryOption.all);
      clashConfig.update(tempClashConfig);
    }
  }
}
