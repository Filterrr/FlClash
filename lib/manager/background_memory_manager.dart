import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/scheduler.dart';

class _PerformanceStats {
  final List<_ModeTransition> _modeTransitions = [];
  int _gcCount = 0;
  int _cacheClearCount = 0;
  DateTime? _backgroundEnteredAt;
  Duration _totalBackgroundDuration = Duration.zero;
  int _backgroundCount = 0;

  void recordModeTransition(LowMemoryMode from, LowMemoryMode to) {
    _modeTransitions.add(_ModeTransition(
      from: from,
      to: to,
      timestamp: DateTime.now(),
    ));
    if (_modeTransitions.length > 100) {
      _modeTransitions.removeRange(0, _modeTransitions.length - 100);
    }
  }

  void recordGc() => _gcCount++;
  void recordCacheClear() => _cacheClearCount++;
  void recordBackgroundStart() {
    _backgroundEnteredAt = DateTime.now();
    _backgroundCount++;
  }

  void recordBackgroundEnd() {
    if (_backgroundEnteredAt != null) {
      _totalBackgroundDuration +=
          DateTime.now().difference(_backgroundEnteredAt!);
      _backgroundEnteredAt = null;
    }
  }

  Map<String, dynamic> toMap() => {
        'totalGcCount': _gcCount,
        'totalCacheClearCount': _cacheClearCount,
        'totalBackgroundCount': _backgroundCount,
        'totalBackgroundDuration': _totalBackgroundDuration.inSeconds,
        'recentModeTransitions': _modeTransitions
            .map((t) => {
                  'from': t.from.name,
                  'to': t.to.name,
                  'time': t.timestamp.toIso8601String(),
                })
            .toList()
            .reversed
            .take(10)
            .toList(),
        'currentMode': lowMemoryModeNotifier.value.name,
      };
}

class _ModeTransition {
  final LowMemoryMode from;
  final LowMemoryMode to;
  final DateTime timestamp;

  _ModeTransition({
    required this.from,
    required this.to,
    required this.timestamp,
  });
}

class BackgroundMemoryManager {
  static final BackgroundMemoryManager _instance =
      BackgroundMemoryManager._internal();
  factory BackgroundMemoryManager() => _instance;
  BackgroundMemoryManager._internal();

  bool _isInitialized = false;
  bool _isInBackground = false;
  Timer? _gcTimer;
  Timer? _memoryMonitorTimer;
  Timer? _escalationTimer;
  int _backgroundDuration = 0;
  final _PerformanceStats _perfStats = _PerformanceStats();

  static const Duration _gcInterval = Duration(seconds: 300);
  static const Duration _memoryMonitorInterval = Duration(seconds: 600);
  static const Duration _escalationDelay = Duration(seconds: 120);
  static const int _aggressiveGcThreshold = 600;

  bool get isInBackground => _isInBackground;

  BackgroundOptimizationLevel get _optimizationLevel {
    try {
      final config = globalState.appController.config;
      if (!config.appSetting.backgroundOptimization) {
        return BackgroundOptimizationLevel.disabled;
      }
      return config.appSetting.backgroundOptimizationLevel;
    } catch (_) {
      return BackgroundOptimizationLevel.disabled;
    }
  }

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

  void _enterBackground() {
    if (_isInBackground) return;
    _isInBackground = true;
    _backgroundDuration = 0;
    _perfStats.recordBackgroundStart();

    final level = _optimizationLevel;
    if (level == BackgroundOptimizationLevel.disabled) return;

    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _clearNonEssentialCaches();
    _requestGc();

    switch (level) {
      case BackgroundOptimizationLevel.light:
        _transitionToMode(LowMemoryMode.reduced);
        _startMemoryMonitor();
      case BackgroundOptimizationLevel.balanced:
        _transitionToMode(LowMemoryMode.reduced);
        _startEscalationTimer();
        _startMemoryMonitor();
      case BackgroundOptimizationLevel.aggressive:
        _transitionToMode(LowMemoryMode.low);
        _startBackgroundGc();
        _startMemoryMonitor();
      case BackgroundOptimizationLevel.disabled:
        break;
    }
  }

  void _exitBackground() {
    if (!_isInBackground) return;
    _isInBackground = false;
    _backgroundDuration = 0;
    _perfStats.recordBackgroundEnd();

    _cancelEscalationTimer();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundGc();
    _stopMemoryMonitor();

    if (_optimizationLevel != BackgroundOptimizationLevel.disabled) {
      _transitionToMode(LowMemoryMode.normal);
      _scheduleUiRefresh();
    }
  }

  void _startEscalationTimer() {
    _cancelEscalationTimer();
    _escalationTimer = Timer(_escalationDelay, () {
      if (_isInBackground &&
          _optimizationLevel == BackgroundOptimizationLevel.balanced) {
        _transitionToMode(LowMemoryMode.low);
        _startBackgroundGc();
      }
    });
  }

  void _cancelEscalationTimer() {
    _escalationTimer?.cancel();
    _escalationTimer = null;
  }

  void _transitionToMode(LowMemoryMode newMode) {
    final oldMode = lowMemoryModeNotifier.value;
    if (oldMode == newMode) return;
    lowMemoryModeNotifier.value = newMode;
    _perfStats.recordModeTransition(oldMode, newMode);
  }

  void onAppPaused() => _enterBackground();
  void onAppResumed() => _exitBackground();
  void onWindowHidden() => _enterBackground();
  void onWindowShown() => _exitBackground();
  void onWindowMinimized() => _enterBackground();
  void onWindowRestored() => _exitBackground();

  void onMemoryPressureLow() {
    if (!_isInBackground) {
      _transitionToMode(LowMemoryMode.reduced);
    }
    _requestGc();
    resourceController.forceClearImageCache();
    _perfStats.recordCacheClear();
  }

  void onMemoryPressureMedium() {
    _transitionToMode(LowMemoryMode.low);
    _requestGc();
    resourceController.forceClearAllCaches();
    _perfStats.recordCacheClear();
    _trimAppStateData();
  }

  void onMemoryPressureCritical() {
    _transitionToMode(LowMemoryMode.low);
    _requestGc();
    resourceController.forceClearAllCaches();
    _perfStats.recordCacheClear();
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
    resourceController.pauseAllNonCriticalTimers();
    resourceController.pauseAllNonCriticalSubscriptions();
    resourceController.forceClearImageCache();
    _perfStats.recordCacheClear();
  }

  void _resumeAllUpdates() {
    resourceController.resumeAllTimers();
    resourceController.resumeAllSubscriptions();
  }

  void _clearNonEssentialCaches() {
    resourceController.forceClearAllCaches();
    _perfStats.recordCacheClear();
  }

  void _scheduleUiRefresh() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_isInBackground) {
        globalState.appController.updateGroupDebounce();
      }
    });
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
    _perfStats.recordGc();
  }

  void _requestDartGc() {
    try {
      Future.microtask(() {});
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  }

  void _performAggressiveCleanup() {
    resourceController.forceClearAllCaches();
    _perfStats.recordCacheClear();
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
    _memoryMonitorTimer = Timer.periodic(_memoryMonitorInterval, (_) {
      if (_isInBackground) {
        _requestGc();
        _requestDartGc();
        resourceController.forceClearImageCache();
        _perfStats.recordCacheClear();
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

  Map<String, dynamic> getPerformanceStats() => _perfStats.toMap();

  void dispose() {
    _cancelEscalationTimer();
    _stopBackgroundGc();
    _stopMemoryMonitor();
    resourceController.dispose();
    _isInitialized = false;
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
