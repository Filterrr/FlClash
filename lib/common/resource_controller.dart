import 'dart:async';

import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:flutter/painting.dart';

class PausableTimer {
  final Duration duration;
  final void Function() callback;
  Timer? _timer;
  bool _isPaused = false;

  PausableTimer({
    required this.duration,
    required this.callback,
  });

  bool get isActive => _timer != null && _timer!.isActive;

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

class ResourceController {
  static final ResourceController _instance = ResourceController._internal();
  factory ResourceController() => _instance;
  ResourceController._internal();

  final List<PausableTimer> _pausableTimers = [];
  final List<StreamSubscription> _pausableSubscriptions = [];
  final List<VoidCallback> _onEnterLowMemory = [];
  final List<VoidCallback> _onExitLowMemory = [];
  bool _isInitialized = false;

  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    lowMemoryModeNotifier.addListener(_handleModeChange);
  }

  void _handleModeChange() {
    final isLow = lowMemoryModeNotifier.value == LowMemoryMode.low;
    if (isLow) {
      _enterLowMemory();
    } else {
      _exitLowMemory();
    }
  }

  void registerPausableTimer(PausableTimer timer) {
    _pausableTimers.add(timer);
  }

  void unregisterPausableTimer(PausableTimer timer) {
    _pausableTimers.remove(timer);
  }

  void registerPausableSubscription(StreamSubscription sub) {
    _pausableSubscriptions.add(sub);
  }

  void unregisterPausableSubscription(StreamSubscription sub) {
    _pausableSubscriptions.remove(sub);
  }

  void onEnterLowMemory(VoidCallback callback) {
    _onEnterLowMemory.add(callback);
  }

  void onExitLowMemory(VoidCallback callback) {
    _onExitLowMemory.add(callback);
  }

  void removeOnEnterLowMemory(VoidCallback callback) {
    _onEnterLowMemory.remove(callback);
  }

  void removeOnExitLowMemory(VoidCallback callback) {
    _onExitLowMemory.remove(callback);
  }

  void _enterLowMemory() {
    for (final timer in _pausableTimers) {
      timer.pause();
    }
    for (final sub in _pausableSubscriptions) {
      sub.pause();
    }
    for (final callback in _onEnterLowMemory) {
      callback();
    }
    _clearImageCache();
    _clearListViewCache();
  }

  void _exitLowMemory() {
    for (final timer in _pausableTimers) {
      timer.resume();
    }
    for (final sub in _pausableSubscriptions) {
      sub.resume();
    }
    for (final callback in _onExitLowMemory) {
      callback();
    }
  }

  void _clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void _clearListViewCache() {}

  void dispose() {
    lowMemoryModeNotifier.removeListener(_handleModeChange);
    _pausableTimers.clear();
    _pausableSubscriptions.clear();
    _onEnterLowMemory.clear();
    _onExitLowMemory.clear();
    _isInitialized = false;
  }
}

final resourceController = ResourceController();
