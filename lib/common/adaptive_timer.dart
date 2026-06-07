import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/low_memory_mode.dart';

/// 智能轮询定时器：根据数据变化频率自动调整轮询间隔
///
/// - 数据活跃时使用 [activeInterval] 高频轮询
/// - 连续 [idleThreshold] 次无变化后降频至 [idleInterval]
/// - 支持 LowMemoryMode 降频/暂停
/// - 空闲切换时请求轻量 GC 释放内存
class AdaptiveTimer {
  final Duration activeInterval;
  final Duration idleInterval;
  final int idleThreshold;
  final void Function() callback;

  Timer? _timer;
  int _idleTicks = 0;
  bool _lastHadChange = false;
  bool _isIdleMode = false;
  bool _gcRequested = false;

  AdaptiveTimer({
    required this.activeInterval,
    required this.idleInterval,
    this.idleThreshold = 3,
    required this.callback,
  });

  bool get isActive => _timer != null && _timer!.isActive;

  /// 通知当前周期有数据变化，重置空闲计数
  void notifyChange() {
    _lastHadChange = true;
    _gcRequested = false;
  }

  void start() {
    stop();
    _idleTicks = 0;
    _isIdleMode = false;
    _gcRequested = false;
    _timer = Timer.periodic(activeInterval, (_) {
      if (isLowMemoryMode) return;
      if (isReducedMemoryMode && !(_isIdleMode ? _reducedIdleTick() : _reducedActiveTick())) {
        return;
      }
      callback();
      _updateIdleState();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _updateIdleState() {
    if (_lastHadChange) {
      _idleTicks = 0;
      _isIdleMode = false;
      _lastHadChange = false;
    } else {
      _idleTicks++;
      if (_idleTicks >= idleThreshold && !_isIdleMode) {
        _isIdleMode = true;
        _requestIdleGc();
        _restartWithInterval(idleInterval);
      }
    }
  }

  /// 切换到空闲模式时请求一次轻量 GC
  void _requestIdleGc() {
    if (_gcRequested) return;
    _gcRequested = true;
    try {
      clashCore.requestGc();
    } catch (_) {}
  }

  void _restartWithInterval(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (isLowMemoryMode) return;
      if (isReducedMemoryMode && _idleTicks % 3 != 0) {
        _idleTicks++;
        return;
      }
      callback();
      if (_lastHadChange) {
        _idleTicks = 0;
        _isIdleMode = false;
        _lastHadChange = false;
        _gcRequested = false;
        _restartWithInterval(activeInterval);
      } else {
        _idleTicks++;
      }
    });
  }

  // Reduced memory mode: active 时每 3 tick 执行一次
  bool _reducedActiveTick() => _idleTicks % 3 == 0;

  // Reduced memory mode: idle 时每 5 tick 执行一次
  bool _reducedIdleTick() => _idleTicks % 5 == 0;
}

/// 页面可见性感知的定时器：页面不可见时自动暂停
class VisibilityAwareTimer {
  final Duration interval;
  final void Function() callback;
  final bool Function() isVisible;

  Timer? _timer;
  bool _isRunning = false;

  VisibilityAwareTimer({
    required this.interval,
    required this.callback,
    required this.isVisible,
  });

  bool get isActive => _isRunning;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(interval, (_) {
      if (!isVisible()) return;
      if (isLowMemoryMode) return;
      if (isReducedMemoryMode) {
        // reduced mode 下降低频率
        if (_timer!.tick % 3 != 0) return;
      }
      callback();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }
}
