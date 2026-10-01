import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/low_memory_mode.dart';

/// 智能轮询定时器：根据数据变化频率自动调整轮询间隔
///
/// - 数据活跃时使用 [activeInterval] 高频轮询
/// - 连续 [idleThreshold] 次无变化后降频至 [idleInterval]
/// - 连续 [deepIdleThreshold] 次无变化后降频至 [deepIdleInterval]
/// - 支持 LowMemoryMode 降频/暂停
/// - 空闲切换时请求轻量 GC 释放内存
class AdaptiveTimer {
  final Duration activeInterval;
  final Duration idleInterval;
  final Duration deepIdleInterval;
  final int idleThreshold;
  final int deepIdleThreshold;
  final bool Function() callback;

  /// 进入空闲模式时请求一次轻量 GC 的回调。
  ///
  /// 默认走 [clashCore.requestGc]；测试可注入空实现，避免在测试环境
  /// 初始化真实 core（会启动 socket 服务与进程，产生悬挂定时器）。
  final void Function()? requestGc;

  Timer? _timer;
  int _idleTicks = 0;
  bool _isIdleMode = false;
  bool _isDeepIdleMode = false;
  bool _gcRequested = false;

  AdaptiveTimer({
    required this.activeInterval,
    required this.idleInterval,
    this.deepIdleInterval = const Duration(seconds: 30),
    this.idleThreshold = 3,
    this.deepIdleThreshold = 10,
    required this.callback,
    this.requestGc,
  });

  bool get isActive => _timer != null && _timer!.isActive;

  void start() {
    stop();
    _idleTicks = 0;
    _isIdleMode = false;
    _isDeepIdleMode = false;
    _gcRequested = false;
    _timer = Timer.periodic(activeInterval, (_) => _handleTick());
  }

  /// 定时器每次触发的统一处理入口。
  ///
  /// 注意：reduced 模式下被跳过的 tick 也必须推进 [_idleTicks]，否则
  /// 跳帧判定 `_idleTicks % N == 0` 会永远命中同一个余数而彻底停摆
  /// （曾经 start() 与 _restartWithInterval() 各写一份逻辑，start()
  /// 漏掉了自增导致 reduced 模式下回调只执行一次）。
  void _handleTick() {
    if (isLowMemoryMode) return;
    if (isReducedMemoryMode && !_reducedTickForMode()) {
      _idleTicks++;
      return;
    }
    _applyCallbackResult();
  }

  /// 执行回调并按结果更新状态机（升频 / 降频）。
  void _applyCallbackResult() {
    final hadChange = callback();
    if (hadChange) {
      _idleTicks = 0;
      if (_isDeepIdleMode || _isIdleMode) {
        _isDeepIdleMode = false;
        _isIdleMode = false;
        _gcRequested = false;
        _restartWithInterval(activeInterval);
      }
    } else {
      _idleTicks++;
      if (_idleTicks >= deepIdleThreshold && !_isDeepIdleMode) {
        _isDeepIdleMode = true;
        _isIdleMode = true;
        _requestIdleGc();
        _restartWithInterval(deepIdleInterval);
      } else if (_idleTicks >= idleThreshold && !_isIdleMode) {
        _isIdleMode = true;
        _requestIdleGc();
        _restartWithInterval(idleInterval);
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 切换到空闲模式时请求一次轻量 GC。
  ///
  /// 只在触发这一刻才解析 [clashCore]，且调用方可在测试中注入替代实现；
  /// 生产环境不传 [requestGc] 时行为与旧版一致。
  void _requestIdleGc() {
    if (_gcRequested) return;
    _gcRequested = true;
    try {
      (requestGc ?? () => clashCore.requestGc())();
    } catch (_) {}
  }

  void _restartWithInterval(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _handleTick());
  }

  /// Reduced memory mode 下根据当前空闲级别决定跳帧策略
  bool _reducedTickForMode() {
    if (_isDeepIdleMode) return _idleTicks % 7 == 0;
    if (_isIdleMode) return _idleTicks % 5 == 0;
    return _idleTicks % 3 == 0;
  }
}
