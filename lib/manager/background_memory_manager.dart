import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
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
  int _backgroundDuration = 0;

  static const Duration _gcInterval = Duration(seconds: 30);
  static const Duration _memoryMonitorInterval = Duration(seconds: 60);
  static const int _aggressiveGcThreshold = 60; // 后台60秒后进入激进GC

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
    _backgroundDuration = 0;
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _clearNonEssentialCaches();
    _requestGc();
    _startBackgroundGc();
    _startMemoryMonitor();
  }

  void onAppResumed() {
    _isInBackground = false;
    _backgroundDuration = 0;
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
    _stopMemoryMonitor();
  }

  void onWindowHidden() {
    _isInBackground = true;
    _backgroundDuration = 0;
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _clearNonEssentialCaches();
    _requestGc();
    _startBackgroundGc();
    _startMemoryMonitor();
  }

  void onWindowShown() {
    _isInBackground = false;
    _backgroundDuration = 0;
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
    _stopMemoryMonitor();
  }

  void onWindowMinimized() {
    _isInBackground = true;
    _backgroundDuration = 0;
    enterLowMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _clearNonEssentialCaches();
    _requestGc();
    _startBackgroundGc();
    _startMemoryMonitor();
  }

  void onWindowRestored() {
    _isInBackground = false;
    _backgroundDuration = 0;
    exitLowMemoryMode();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
    _stopMemoryMonitor();
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
    _trimAppStateData();
  }

  void onMemoryPressureCritical() {
    enterLowMemoryMode();
    _requestGc();
    resourceController.forceClearAllCaches();
    _trimAppStateData();
    _trimFlowingStateData();
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

  void _clearNonEssentialCaches() {
    resourceController.forceClearAllCaches();
  }

  void _startBackgroundGc() {
    _stopBackgroundGc();
    _gcTimer = Timer.periodic(_gcInterval, (_) {
      _requestGc();
      _requestDartGc();
      _backgroundDuration += _gcInterval.inSeconds;
      if (_backgroundDuration >= _aggressiveGcThreshold) {
        _performAggressiveCleanup();
      }
    });
  }

  void _stopBackgroundGc() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  void _requestGc() {
    clashCore.requestGc();
  }

  void _requestDartGc() {
    // 触发Dart VM垃圾回收 - 通过创建并丢弃对象触发GC启发式回收
    try {
      final List<dynamic> discard = [];
      discard.length;
    } catch (_) {}
  }

  void _performAggressiveCleanup() {
    resourceController.forceClearAllCaches();
    _trimAppStateData();
    _trimFlowingStateData();
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

  void _trimFlowingStateData() {
    final appController = globalState.appController;
    final flowingState = appController.appFlowingState;
    if (flowingState.logs.length > 50) {
      flowingState.logs = flowingState.logs.safeSublist(
        flowingState.logs.length - 50,
      );
    }
    if (flowingState.traffics.length > 20) {
      flowingState.traffics = flowingState.traffics.safeSublist(
        flowingState.traffics.length - 20,
      );
    }
  }

  void _startMemoryMonitor() {
    _stopMemoryMonitor();
    _memoryMonitorTimer =
        Timer.periodic(_memoryMonitorInterval, (_) {
      if (_isInBackground) {
        _requestGc();
        _requestDartGc();
        resourceController.forceClearImageCache();
        _backgroundDuration += _memoryMonitorInterval.inSeconds;
        if (_backgroundDuration >= _aggressiveGcThreshold) {
          _performAggressiveCleanup();
        }
      }
    });
  }

  void _stopMemoryMonitor() {
    _memoryMonitorTimer?.cancel();
    _memoryMonitorTimer = null;
  }

  void dispose() {
    _stopBackgroundGc();
    _stopMemoryMonitor();
    resourceController.dispose();
    _isInitialized = false;
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
