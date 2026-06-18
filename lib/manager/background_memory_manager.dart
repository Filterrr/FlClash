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
  Timer? _backgroundMaintenanceTimer;
  Timer? _escalationTimer;
  int _backgroundDuration = 0;
  final _PerformanceStats _perfStats = _PerformanceStats();
  final List<VoidCallback> _onEnterBackgroundCallbacks = [];
  final List<VoidCallback> _onExitBackgroundCallbacks = [];

  /// 后台持续时间阈值：动态调整维护间隔
  static const int _mediumBgThreshold = 300; // 5 分钟后进入中期
  static const int _longBgThreshold = 1800; // 30 分钟后进入长期

  /// 各阶段维护间隔
  static const Duration _initialMaintenanceInterval = Duration(seconds: 300);
  static const Duration _mediumMaintenanceInterval = Duration(seconds: 600);
  static const Duration _longMaintenanceInterval = Duration(seconds: 900);

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

  /// 注册后台进入回调，在应用进入后台时调用。
  /// 用于暂停非必要的定时器、订阅等资源。
  void onEnterBackground(VoidCallback callback) {
    _onEnterBackgroundCallbacks.add(callback);
  }

  /// 注册后台退出回调，在应用回到前台时调用。
  /// 用于恢复被暂停的定时器、订阅等资源。
  void onExitBackground(VoidCallback callback) {
    _onExitBackgroundCallbacks.add(callback);
  }

  /// 移除后台进入回调。
  void removeOnEnterBackground(VoidCallback callback) {
    _onEnterBackgroundCallbacks.remove(callback);
  }

  /// 移除后台退出回调。
  void removeOnExitBackground(VoidCallback callback) {
    _onExitBackgroundCallbacks.remove(callback);
  }

  void _enterBackground() {
    if (_isInBackground) return;
    _isInBackground = true;
    _backgroundDuration = 0;
    _perfStats.recordBackgroundStart();

    // 通知所有注册的回调暂停非必要资源（定时器、订阅等）
    for (final callback in _onEnterBackgroundCallbacks) {
      try {
        callback();
      } catch (_) {}
    }

    // 标记 HTTP 客户端进入后台模式，缩短空闲超时加速连接释放
    FlClashHttpOverrides.enterBackground();
    // 节流 ClashMessage 非关键消息处理，减少后台 CPU 占用
    clashMessage.enterBackground();

    final level = _optimizationLevel;
    if (level == BackgroundOptimizationLevel.disabled) return;

    _reduceGlobalStateTimerFrequency();
    _stopNonEssentialUpdates();
    _clearNonEssentialCaches();
    _requestGc();

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

    _cancelEscalationTimer();
    _restoreGlobalStateTimerFrequency();
    _resumeAllUpdates();
    _stopBackgroundMaintenance();

    // 在模式转换前通知回调恢复资源，确保定时器在 normal 模式前恢复
    for (final callback in _onExitBackgroundCallbacks) {
      try {
        callback();
      } catch (_) {}
    }

    // 标记 HTTP 客户端回到前台模式，恢复正常空闲超时
    FlClashHttpOverrides.exitBackground();
    // 恢复 ClashMessage 全部消息处理
    clashMessage.exitBackground();

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
    // 关闭空闲 HTTP 连接，释放网络资源（保留活跃连接）
    FlClashHttpOverrides.closeIdleConnections();
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

      _requestGc();
      _requestDartGc();
      resourceController.forceClearImageCache();
      _perfStats.recordCacheClear();
      _backgroundDuration += interval.inSeconds;

      if (_backgroundDuration >= _aggressiveGcThreshold) {
        _performAggressiveCleanup();
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
      Future.microtask(() {});
      SchedulerBinding.instance.scheduleFrame();
    } catch (_) {}
  }

  void _performAggressiveCleanup() {
    resourceController.forceClearAllCaches();
    // 强制关闭所有 HTTP 连接，最大化资源释放
    FlClashHttpOverrides.forceCloseAllConnections();
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

  void dispose() {
    _cancelEscalationTimer();
    _stopBackgroundMaintenance();
    _onEnterBackgroundCallbacks.clear();
    _onExitBackgroundCallbacks.clear();
    resourceController.dispose();
    _isInitialized = false;
  }
}

final backgroundMemoryManager = BackgroundMemoryManager();
