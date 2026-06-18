import 'dart:async';

import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:flutter/painting.dart';

enum ResourcePriority {
  critical,
  normal,
  low,
}

class ThrottledTimer {
  final Duration normalDuration;
  final Duration reducedDuration;
  final Duration lowDuration;
  final void Function() callback;
  Timer? _timer;
  int _tickCount = 0;
  final int _reducedSkipFactor;
  final int _lowSkipFactor;

  ThrottledTimer({
    required this.normalDuration,
    Duration? reducedDuration,
    Duration? lowDuration,
    required this.callback,
    int reducedSkipFactor = 3,
    int lowSkipFactor = 5,
  })  : reducedDuration = reducedDuration ?? normalDuration,
        lowDuration = lowDuration ?? normalDuration,
        _reducedSkipFactor = reducedSkipFactor,
        _lowSkipFactor = lowSkipFactor;

  bool get isActive => _timer != null && _timer!.isActive;

  void start() {
    cancel();
    _timer = Timer.periodic(normalDuration, (_) {
      _tickCount++;
      final mode = lowMemoryModeNotifier.value;
      switch (mode) {
        case LowMemoryMode.normal:
          callback();
        case LowMemoryMode.reduced:
          if (_tickCount % _reducedSkipFactor == 0) {
            callback();
          }
        case LowMemoryMode.low:
          if (_tickCount % _lowSkipFactor == 0) {
            callback();
          }
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _tickCount = 0;
  }
}

class PausableTimer {
  final Duration duration;
  final void Function() callback;
  final ResourcePriority priority;
  Timer? _timer;
  bool _isPaused = false;

  PausableTimer({
    required this.duration,
    required this.callback,
    this.priority = ResourcePriority.normal,
  });

  bool get isActive => _timer != null && _timer!.isActive;
  bool get isPaused => _isPaused;

  void start() {
    _cancel();
    _isPaused = false;
    _timer = Timer.periodic(duration, (_) {
      if (!_isPaused) callback();
    });
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  void cancel() {
    _cancel();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

class PausableSubscription {
  final StreamSubscription subscription;
  final ResourcePriority priority;
  final String? label;

  PausableSubscription(
    this.subscription, {
    this.priority = ResourcePriority.normal,
    this.label,
  });
}

class ResourceController {
  static final ResourceController _instance = ResourceController._internal();
  factory ResourceController() => _instance;
  ResourceController._internal();

  final List<PausableTimer> _pausableTimers = [];
  final List<ThrottledTimer> _throttledTimers = [];
  final List<PausableSubscription> _pausableSubscriptions = [];
  final List<VoidCallback> _onEnterLowMemory = [];
  final List<VoidCallback> _onExitLowMemory = [];
  final List<VoidCallback> _onEnterReducedMemory = [];
  final List<VoidCallback> _onExitReducedMemory = [];
  bool _isInitialized = false;
  LowMemoryMode _lastMode = LowMemoryMode.normal;

  static const int _normalImageCacheLimit = 100;
  static const int _reducedImageCacheLimit = 30;
  static const int _lowImageCacheLimit = 10;
  static const int _normalImageCacheBytes = 100 * 1024 * 1024;
  static const int _reducedImageCacheBytes = 30 * 1024 * 1024;
  static const int _lowImageCacheBytes = 10 * 1024 * 1024;

  static const double _normalCacheExtent = 500;
  static const double _reducedCacheExtent = 200;
  static const double _lowCacheExtent = 0;

  double get currentCacheExtent {
    switch (lowMemoryModeNotifier.value) {
      case LowMemoryMode.normal:
        return _normalCacheExtent;
      case LowMemoryMode.reduced:
        return _reducedCacheExtent;
      case LowMemoryMode.low:
        return _lowCacheExtent;
    }
  }

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    _setImageCacheLimits(_normalImageCacheLimit, _normalImageCacheBytes);
    lowMemoryModeNotifier.addListener(_handleModeChange);
  }

  void _handleModeChange() {
    final mode = lowMemoryModeNotifier.value;
    if (mode == _lastMode) return;

    switch (_lastMode) {
      case LowMemoryMode.reduced:
        for (final callback in _onExitReducedMemory) {
          callback();
        }
        break;
      case LowMemoryMode.low:
        for (final callback in _onExitLowMemory) {
          callback();
        }
        break;
      case LowMemoryMode.normal:
        break;
    }

    switch (mode) {
      case LowMemoryMode.normal:
        _exitLowMemory();
        break;
      case LowMemoryMode.reduced:
        _enterReducedMemory();
        break;
      case LowMemoryMode.low:
        _enterLowMemory();
        break;
    }

    _lastMode = mode;
  }

  void registerPausableTimer(PausableTimer timer) {
    _pausableTimers.add(timer);
  }

  void unregisterPausableTimer(PausableTimer timer) {
    _pausableTimers.remove(timer);
  }

  void registerThrottledTimer(ThrottledTimer timer) {
    _throttledTimers.add(timer);
  }

  void unregisterThrottledTimer(ThrottledTimer timer) {
    _throttledTimers.remove(timer);
  }

  void registerPausableSubscription(
    StreamSubscription sub, {
    ResourcePriority priority = ResourcePriority.normal,
    String? label,
  }) {
    _pausableSubscriptions.add(
      PausableSubscription(sub, priority: priority, label: label),
    );
  }

  void unregisterPausableSubscription(StreamSubscription sub) {
    _pausableSubscriptions.removeWhere((s) => s.subscription == sub);
  }

  void onEnterLowMemory(VoidCallback callback) {
    _onEnterLowMemory.add(callback);
  }

  void onExitLowMemory(VoidCallback callback) {
    _onExitLowMemory.add(callback);
  }

  void onEnterReducedMemory(VoidCallback callback) {
    _onEnterReducedMemory.add(callback);
  }

  void onExitReducedMemory(VoidCallback callback) {
    _onExitReducedMemory.add(callback);
  }

  void removeOnEnterLowMemory(VoidCallback callback) {
    _onEnterLowMemory.remove(callback);
  }

  void removeOnExitLowMemory(VoidCallback callback) {
    _onExitLowMemory.remove(callback);
  }

  void removeOnEnterReducedMemory(VoidCallback callback) {
    _onEnterReducedMemory.remove(callback);
  }

  void removeOnExitReducedMemory(VoidCallback callback) {
    _onExitReducedMemory.remove(callback);
  }

  void _enterReducedMemory() {
    for (final timer in _pausableTimers) {
      if (timer.priority == ResourcePriority.low) {
        timer.pause();
      }
    }
    for (final sub in _pausableSubscriptions) {
      if (sub.priority == ResourcePriority.low) {
        sub.subscription.pause();
      }
    }
    _setImageCacheLimits(_reducedImageCacheLimit, _reducedImageCacheBytes);
    _clearImageCache();
    for (final callback in _onEnterReducedMemory) {
      callback();
    }
  }

  void _enterLowMemory() {
    for (final timer in _pausableTimers) {
      if (timer.priority != ResourcePriority.critical) {
        timer.pause();
      }
    }
    for (final sub in _pausableSubscriptions) {
      if (sub.priority != ResourcePriority.critical) {
        sub.subscription.pause();
      }
    }
    _setImageCacheLimits(_lowImageCacheLimit, _lowImageCacheBytes);
    _clearImageCache();
    _clearListViewCache();
    for (final callback in _onEnterLowMemory) {
      callback();
    }
  }

  void _exitLowMemory() {
    for (final timer in _pausableTimers) {
      timer.resume();
    }
    for (final sub in _pausableSubscriptions) {
      if (sub.subscription.isPaused) {
        sub.subscription.resume();
      }
    }
    _setImageCacheLimits(_normalImageCacheLimit, _normalImageCacheBytes);
    for (final callback in _onExitReducedMemory) {
      callback();
    }
    for (final callback in _onExitLowMemory) {
      callback();
    }
  }

  void _setImageCacheLimits(int count, int bytes) {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = count;
    cache.maximumSizeBytes = bytes;
  }

  void _clearImageCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  void _clearListViewCache() {
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void forceClearImageCache() {
    _clearImageCache();
  }

  void forceClearAllCaches() {
    _clearImageCache();
    _clearListViewCache();
  }

  void pauseAllNonCriticalTimers() {
    for (final timer in _pausableTimers) {
      if (timer.priority != ResourcePriority.critical) {
        timer.pause();
      }
    }
  }

  void resumeAllTimers() {
    for (final timer in _pausableTimers) {
      timer.resume();
    }
  }

  void pauseAllNonCriticalSubscriptions() {
    for (final sub in _pausableSubscriptions) {
      if (sub.priority != ResourcePriority.critical) {
        sub.subscription.pause();
      }
    }
  }

  void resumeAllSubscriptions() {
    for (final sub in _pausableSubscriptions) {
      if (sub.subscription.isPaused) {
        sub.subscription.resume();
      }
    }
  }

  /// 获取当前跟踪的资源统计信息，用于诊断和测试。
  Map<String, dynamic> getResourceStats() {
    int pausedTimers = 0;
    int pausedSubscriptions = 0;
    for (final timer in _pausableTimers) {
      if (timer.isPaused) pausedTimers++;
    }
    for (final sub in _pausableSubscriptions) {
      if (sub.subscription.isPaused) pausedSubscriptions++;
    }
    return {
      'totalPausableTimers': _pausableTimers.length,
      'pausedTimers': pausedTimers,
      'totalThrottledTimers': _throttledTimers.length,
      'totalPausableSubscriptions': _pausableSubscriptions.length,
      'pausedSubscriptions': pausedSubscriptions,
      'currentMode': lowMemoryModeNotifier.value.name,
      'imageCacheSize': PaintingBinding.instance.imageCache.currentSize,
      'imageCacheBytes': PaintingBinding.instance.imageCache.currentSizeBytes,
    };
  }

  /// 检查是否有非关键定时器仍在运行（未暂停）。
  bool hasActiveNonCriticalTimers() {
    for (final timer in _pausableTimers) {
      if (timer.priority != ResourcePriority.critical && !timer.isPaused) {
        return true;
      }
    }
    return false;
  }

  /// 检查是否有非关键订阅仍在运行（未暂停）。
  bool hasActiveNonCriticalSubscriptions() {
    for (final sub in _pausableSubscriptions) {
      if (sub.priority != ResourcePriority.critical &&
          !sub.subscription.isPaused) {
        return true;
      }
    }
    return false;
  }

  void dispose() {
    lowMemoryModeNotifier.removeListener(_handleModeChange);
    _pausableTimers.clear();
    _throttledTimers.clear();
    _pausableSubscriptions.clear();
    _onEnterLowMemory.clear();
    _onExitLowMemory.clear();
    _onEnterReducedMemory.clear();
    _onExitReducedMemory.clear();
    _isInitialized = false;
  }
}

final resourceController = ResourceController();
