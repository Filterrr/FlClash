import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:fl_clash/state.dart';

class BackgroundMemoryManager {
  static final BackgroundMemoryManager _instance =
      BackgroundMemoryManager._internal();
  factory BackgroundMemoryManager() => _instance;
  BackgroundMemoryManager._internal();

  bool _isInitialized = false;
  bool _isInBackground = false;
  Timer? _gcTimer;
  Timer? _recoveryTimer;
  int _backgroundDuration = 0;

  static const Duration _gcInterval = Duration(seconds: 30);
  static const int _aggressiveGcThreshold = 60;

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
  }

  void onAppResumed() {
    _isInBackground = false;
    _backgroundDuration = 0;
    _gradualRecovery();
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
  }

  void onWindowShown() {
    _isInBackground = false;
    _backgroundDuration = 0;
    _gradualRecovery();
  }

  void onWindowBlurred() {
    if (_isInBackground) return;
    enterReducedMemoryMode();
    _reduceGlobalStateTimerFrequency();
    _requestGc();
  }

  void onWindowFocused() {
    if (_isInBackground) return;
    if (lowMemoryModeNotifier.value != LowMemoryMode.low) {
      exitLowMemoryMode();
      _restoreGlobalStateTimerFrequency();
      _resumeAllUpdates();
    }
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
  }

  void onWindowRestored() {
    _isInBackground = false;
    _backgroundDuration = 0;
    _gradualRecovery();
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
    resourceController.resumeAllTimers();
    resourceController.resumeAllSubscriptions();
    _restoreGlobalStateTimerFrequency();
    _triggerDataRefresh();
  }

  void _triggerDataRefresh() {
    if (!globalState.isStart) return;
    final appController = globalState.appController;
    appController.updateRunTime();
    appController.updateTraffic();
    appController.updateGroupDebounce();
  }

  void _clearNonEssentialCaches() {
    resourceController.forceClearAllCaches();
  }

  void _startBackgroundGc() {
    _stopBackgroundGc();
    _gcTimer = Timer.periodic(_gcInterval, (_) {
      _requestGc();
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

  void _gradualRecovery() {
    _stopBackgroundGc();
    _cancelRecoveryTimer();
    final currentMode = lowMemoryModeNotifier.value;
    if (currentMode == LowMemoryMode.low) {
      lowMemoryModeNotifier.value = LowMemoryMode.reduced;
      _restoreGlobalStateTimerFrequency();
      _recoveryTimer = Timer(const Duration(seconds: 2), () {
        lowMemoryModeNotifier.value = LowMemoryMode.normal;
        _resumeAllUpdates();
        _recoveryTimer = null;
      });
    } else if (currentMode == LowMemoryMode.reduced) {
      lowMemoryModeNotifier.value = LowMemoryMode.normal;
      _restoreGlobalStateTimerFrequency();
      _resumeAllUpdates();
    }
  }

  void _cancelRecoveryTimer() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
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

  void dispose() {
    _stopBackgroundGc();
    _cancelRecoveryTimer();
    resourceController.dispose();
    _isInitialized = false;
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
