import 'dart:async';

class RefreshTask {
  final String id;
  final int foregroundMs;
  final int backgroundMs;
  final VoidCallback callback;
  bool _isActive = true;
  Timer? _timer;

  RefreshTask({
    required this.id,
    required this.foregroundMs,
    required this.backgroundMs,
    required this.callback,
  });

  int get currentMs => RefreshScheduler.instance._isBackground
      ? backgroundMs
      : foregroundMs;

  bool get isActive => _isActive;

  void _start() {
    _cancel();
    if (!_isActive) return;
    _timer = Timer.periodic(Duration(milliseconds: currentMs), (_) {
      callback();
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void pause() {
    _isActive = false;
    _cancel();
  }

  void resume() {
    _isActive = true;
    _start();
  }

  void dispose() {
    _cancel();
  }
}

class RefreshScheduler {
  RefreshScheduler._();
  static final RefreshScheduler instance = RefreshScheduler._();

  final Map<String, RefreshTask> _tasks = {};
  bool _isBackground = false;

  void register(RefreshTask task) {
    _tasks[task.id] = task;
    task._start();
  }

  void unregister(String id) {
    final task = _tasks.remove(id);
    task?.dispose();
  }

  void pause(String id) {
    _tasks[id]?.pause();
  }

  void resume(String id) {
    final task = _tasks[id];
    if (task != null) {
      task.resume();
    }
  }

  void setBackground(bool isBackground) {
    if (_isBackground == isBackground) return;
    _isBackground = isBackground;
    for (final task in _tasks.values) {
      if (task.isActive) {
        task._start();
      }
    }
  }

  bool get isBackground => _isBackground;

  void dispose() {
    for (final task in _tasks.values) {
      task.dispose();
    }
    _tasks.clear();
  }
}
