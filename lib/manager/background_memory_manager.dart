import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:fl_clash/common/resource_controller.dart';
import 'package:fl_clash/state.dart';

class BackgroundMemoryManager {
  static final BackgroundMemoryManager _instance =
      BackgroundMemoryManager._internal();
  factory BackgroundMemoryManager() => _instance;
  BackgroundMemoryManager._internal();

  bool _isInitialized = false;
  bool _isInBackground = false;
  Timer? _gcTimer;
  Timer? _memoryMonitorTimer;

  static const Duration _gcInterval = Duration(seconds: 30);
  static const Duration _memoryMonitorInterval = Duration(seconds: 60);

  bool get isInBackground => _isInBackground;

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    resourceController.init();
    _setupResourceCallbacks();
  }

  void _setupResourceCallbacks() {
    resourceController.onEnterLowMemory(() {
      _startBackgroundGc();
    });
    resourceController.onExitLowMemory(() {
      _stopBackgroundGc();
    });
  }

  void onAppPaused() {
    _isInBackground = true;
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _requestGc();
    _startBackgroundGc();
  }

  void onAppResumed() {
    _isInBackground = false;
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
  }

  void onWindowHidden() {
    _isInBackground = true;
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _requestGc();
    _startBackgroundGc();
  }

  void onWindowShown() {
    _isInBackground = false;
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
  }

  void onWindowMinimized() {
    _isInBackground = true;
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _requestGc();
    _startBackgroundGc();
  }

  void onWindowRestored() {
    _isInBackground = false;
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
  }

  void onMemoryPressureLow() {
    if (!_isInBackground) {
      enterReducedMemoryMode();
    }
    _requestGc();
    resourceController.forceClearImageCache();
  }

  void onMemoryPressureMedium() {
    enterLowMemoryMode();
    _requestGc();
    resourceController.forceClearAllCaches();
  }

  void onMemoryPressureCritical() {
    enterLowMemoryMode();
    _requestGc();
    resourceController.forceClearAllCaches();
    _trimAppStateData();
  }

  void _reduceGlobalStateTimerFrequency() {
    globalState.stopListenUpdate();
  }

  void _restoreGlobalStateTimerFrequency() {
    if (globalState.isStart) {
      globalState.startListenUpdate();
    }
  }

  void _stopNonEssentialUpdates() {
    resourceController.forceClearImageCache();
  }

  void _resumeAllUpdates() {
    resourceController.forceClearImageCache();
  }

  void _startBackgroundGc() {
    _stopBackgroundGc();
    _gcTimer = Timer.periodic(_gcInterval, (_) {
      _requestGc();
    });
  }

  void _stopBackgroundGc() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  void _requestGc() {
    clashCore.requestGc();
  }

  void _trimAppStateData() {
    final appController = globalState.appController;
    if (appController.appState.requests.length > 100) {
      appController.appState.requests =
          appController.appState.requests.safeSublist(
        appController.appState.requests.length - 100,
      );
    }
  }

  void startMemoryMonitor() {
    stopMemoryMonitor();
    _memoryMonitorTimer =
        Timer.periodic(_memoryMonitorInterval, (_) {
      if (_isInBackground) {
        _requestGc();
        resourceController.forceClearImageCache();
      }
    });
  }

  void stopMemoryMonitor() {
    _memoryMonitorTimer?.cancel();
    _memoryMonitorTimer = null;
  }

  void dispose() {
    _stopBackgroundGc();
    stopMemoryMonitor();
    resourceController.dispose();
    _isInitialized = false;
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
