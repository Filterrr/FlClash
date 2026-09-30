import 'dart:async';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
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
  DateTime? _backgroundEnteredAt;
  final _PerformanceStats _perfStats = _PerformanceStats();

  /// 已连续处于后台的时长。
  ///
  /// 按真实时间计算（而非累加定时器 tick），定时器被 Doze 等延迟时也能对齐。
  Duration get backgroundDuration {
    final enteredAt = _backgroundEnteredAt;
    if (enteredAt == null) return Duration.zero;
    return DateTime.now().difference(enteredAt);
  }

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
    _backgroundEnteredAt = DateTime.now();
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
    _backgroundEnteredAt = null;
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
    _logStatsIfNeeded();
  }

  /// 性能统计的出口：debug 构建下退出后台时输出一次快照，
  /// 便于排查后台优化实际执行情况。release 构建下 kDebugMode 为
  /// false，不产生任何开销。
  void _logStatsIfNeeded() {
    if (!kDebugMode) return;
    debugPrint('[BackgroundMemoryManager] $getPerformanceStats');
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
    resourceController.pauseAllNonCriticalSubscriptions();
    resourceController.forceClearImageCache();
    _perfStats.recordCacheClear();
  }

  void _resumeAllUpdates() {
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
    final seconds = backgroundDuration.inSeconds;
    if (seconds >= _deepBgThreshold) {
      return _deepMaintenanceInterval;
    }
    if (seconds >= _longBgThreshold) {
      return _longMaintenanceInterval;
    }
    if (seconds >= _mediumBgThreshold) {
      return _mediumMaintenanceInterval;
    }
    return _initialMaintenanceInterval;
  }

  /// 后台维护：一次性定时器链。
  ///
  /// 每次触发后按当前后台时长重排下一次执行，使 3/10/30 分钟三档阈值
  /// 真正生效。旧实现用固定周期 Timer.periodic + 触发时判断是否换挡，
  /// 首次必须等满 10 分钟才会重新评估，阈值形同虚设。
  void _startBackgroundMaintenance() {
    _stopBackgroundMaintenance();
    final interval = _currentMaintenanceInterval();
    _backgroundMaintenanceTimer = Timer(interval, () {
      _backgroundMaintenanceTimer = null;
      if (!_isInBackground) return;

      final duration = backgroundDuration;
      final seconds = duration.inSeconds;

      // 仅在长期后台时才执行 GC，避免频繁 GC 导致的 CPU 唤醒
      if (seconds >= _mediumBgThreshold) {
        _requestGc();
        _releaseDartMemory();
      }

      // 仅在深度后台时才清理缓存
      if (seconds >= _longBgThreshold) {
        resourceController.forceClearImageCache();
        _perfStats.recordCacheClear();
      }

      if (seconds >= _aggressiveGcThreshold) {
        _performAggressiveCleanup();
      }

      if (_isInBackground) {
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

  /// 请求 Dart 侧回收内存。
  ///
  /// 旧实现调用 [WidgetsBinding.handleMemoryPressure] 来“间接触发 GC”，
  /// 但那会让框架遍历所有观察者并回调 [didHaveMemoryPressure]，等于向
  /// 应用广播一次虚假的内存压力告警：AppStateManager 会据此进入 low 模式、
  /// 强制关闭所有定时器与缓存——在 balanced 级别、用户并未真正遇到内存
  /// 压力的情况下，这属于自伤行为，故移除。
  ///
  /// Dart 侧本身不提供主动 GC 的能力，可行的做法是把缓存压缩到当前
  /// 低内存模式下限，交由运行时自行回收。
  void _releaseDartMemory() {
    resourceController.forceClearAllCaches();
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
