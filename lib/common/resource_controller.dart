import 'dart:async';

import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:flutter/painting.dart';

enum ResourcePriority {
  critical,
  normal,
  low,
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

  void dispose() {
    lowMemoryModeNotifier.removeListener(_handleModeChange);
    _pausableSubscriptions.clear();
    _onEnterLowMemory.clear();
    _onExitLowMemory.clear();
    _onEnterReducedMemory.clear();
    _onExitReducedMemory.clear();
    _isInitialized = false;
  }
}

final resourceController = ResourceController();
