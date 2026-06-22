import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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

class BackgroundMemoryManager extends ChangeNotifier {
  static final BackgroundMemoryManager _instance =
      BackgroundMemoryManager._internal();
  factory BackgroundMemoryManager() => _instance;
  BackgroundMemoryManager._internal();

  bool _isInitialized = false;
  bool _isInBackground = false;
  Timer? _backgroundMaintenanceTimer;
  Timer? _escalationTimer;
  int _backgroundDuration = 0;
  final _PerformanceStats _perfStats = _PerformanceStats();

  /// 后台持续时间阈值：动态调整维护间隔
  static const int _mediumBgThreshold = 180; // 3 分钟后进入中期
  static const int _longBgThreshold = 600; // 10 分钟后进入长期
  static const int _deepBgThreshold = 1800; // 30 分钟后进入深度后台

  /// 各阶段维护间隔（逐步延长，减少唤醒频率）
  static const Duration _initialMaintenanceInterval = Duration(seconds: 600); // 10 分钟
  static const Duration _mediumMaintenanceInterval = Duration(seconds: 1200); // 20 分钟
  static const Duration _longMaintenanceInterval = Duration(seconds: 1800); // 30 分钟
  static const Duration _deepMaintenanceInterval = Duration(seconds: 3600); // 60 分钟

  static const Duration _escalationDelay = Duration(seconds: 180);
  static const int _aggressiveGcThreshold = 1200;

  bool get isInBackground => _isInBackground && _optimizationLevel != BackgroundOptimizationLevel.disabled;

  BackgroundOptimizationLevel get _optimizationLevel {
    try {
      final config = globalState.appController.config;
      if (!config.appSetting.backgroundOptimization) {
        return BackgroundOptimizationLevel.disabled;
      }
      return config.appSetting.backgroundOptimizationLevel;
    } catch (_) {
      return BackgroundOptimizationLevel.balanced;
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
      _startBackgroundMaintenance();
    });
    resourceController.onExitLowMemory(() {
      _stopBackgroundMaintenance();
    });
  }

  void _enterBackground() {
    if (_isInBackground) return;
    _isInBackground = true;
    _backgroundDuration = 0;
    _perfStats.recordBackgroundStart();
    notifyListeners();

    final level = _optimizationLevel;
    if (level == BackgroundOptimizationLevel.disabled) return;

    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    // 延迟清理缓存，避免进入后台瞬间的 CPU 峰值
    Future.delayed(const Duration(seconds: 2), () {
      if (_isInBackground) {
        _clearNonEssentialCaches();
        _requestGc();
        _emptyWorkingSet();
      }
    });

    switch (level) {
      case BackgroundOptimizationLevel.light:
        _transitionToMode(LowMemoryMode.reduced);
        _startBackgroundMaintenance();
      case BackgroundOptimizationLevel.balanced:
        _transitionToMode(LowMemoryMode.reduced);
        _startEscalationTimer();
        _startBackgroundMaintenance();
      case BackgroundOptimizationLevel.aggressive:
        _transitionToMode(LowMemoryMode.low);
        _startBackgroundMaintenance();
      case BackgroundOptimizationLevel.disabled:
        break;
    }
  }

  void _exitBackground() {
    if (!_isInBackground) return;
    _isInBackground = false;
    _backgroundDuration = 0;
    _perfStats.recordBackgroundEnd();
    notifyListeners();

    _cancelEscalationTimer();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundMaintenance();

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
        // 已有 _backgroundMaintenanceTimer 在运行，无需额外启动
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
    _requestDartGc();
    resourceController.forceClearImageCache();
    _perfStats.recordCacheClear();
  }

  void onMemoryPressureMedium() {
    _transitionToMode(LowMemoryMode.low);
    _requestGc();
    _requestDartGc();
    resourceController.forceClearAllCaches();
    _perfStats.recordCacheClear();
    _trimAppStateData();
  }

  void onMemoryPressureCritical() {
    _transitionToMode(LowMemoryMode.low);
    _requestGc();
    _requestDartGc();
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

  /// 根据后台持续时间计算当前维护间隔
  Duration _currentMaintenanceInterval() {
    if (_backgroundDuration >= _deepBgThreshold) {
      return _deepMaintenanceInterval;
    }
    if (_backgroundDuration >= _longBgThreshold) {
      return _longMaintenanceInterval;
    }
    if (_backgroundDuration >= _mediumBgThreshold) {
      return _mediumMaintenanceInterval;
    }
    return _initialMaintenanceInterval;
  }

  /// 统一的后台维护定时器：合并了原 GC 定时器和内存监控定时器
  /// 根据后台持续时间动态调整间隔，减少长时间后台时的 CPU 唤醒
  void _startBackgroundMaintenance() {
    _stopBackgroundMaintenance();
    final interval = _currentMaintenanceInterval();
    _backgroundMaintenanceTimer = Timer.periodic(interval, (_) {
      if (!_isInBackground) return;

      _backgroundDuration += interval.inSeconds;

      // 仅在长期后台时才执行 GC，避免频繁 GC 导致的 CPU 唤醒
      if (_backgroundDuration >= _mediumBgThreshold) {
        _requestGc();
        _requestDartGc();
        _emptyWorkingSet();
      }

      // 仅在深度后台时才清理缓存
      if (_backgroundDuration >= _longBgThreshold) {
        resourceController.forceClearImageCache();
        _perfStats.recordCacheClear();
        _emptyWorkingSet();
      }

      if (_backgroundDuration >= _aggressiveGcThreshold) {
        _performAggressiveCleanup();
        _emptyWorkingSet();
      }

      // 检查是否需要调整间隔（升级后重启定时器）
      final newInterval = _currentMaintenanceInterval();
      if (newInterval != interval) {
        _startBackgroundMaintenance();
      }
    });
  }

  void _stopBackgroundMaintenance() {
    _backgroundMaintenanceTimer?.cancel();
    _backgroundMaintenanceTimer = null;
  }

  void _requestGc() {
    clashCore.requestGc();
    _perfStats.recordGc();
  }

  void _requestDartGc() {
    try {
      WidgetsBinding.instance.handleMemoryPressure();
    } catch (_) {}
  }

  void _emptyWorkingSet() {
    if (Platform.isWindows) {
      windows?.emptyWorkingSet();
    }
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

  Map<String, dynamic> getPerformanceStats() => _perfStats.toMap();

  @override
  void dispose() {
    _cancelEscalationTimer();
    _stopBackgroundMaintenance();
    resourceController.dispose();
    _isInitialized = false;
    super.dispose();
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
