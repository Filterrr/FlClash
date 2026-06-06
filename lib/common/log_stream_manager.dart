import 'dart:async';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

/// 事件驱动的日志流管理器
/// 替代轮询方式，使用 Stream 实现背压控制和事件驱动日志更新
class LogStreamManager {
  static LogStreamManager? _instance;
  static LogStreamManager get instance => _instance ??= LogStreamManager._();

  LogStreamManager._();

  /// 日志广播流控制器
  StreamController<List<Log>>? _logController;

  /// 日志缓冲区
  final List<Log> _buffer = [];

  /// 最大缓冲区大小
  static const int _maxBufferSize = 1000;

  /// 背压刷新间隔
  Duration _flushInterval = const Duration(milliseconds: 200);

  /// 定时刷新器
  Timer? _flushTimer;

  /// 是否有监听者
  bool _hasListeners = false;

  /// 获取日志流
  Stream<List<Log>> get stream {
    _logController ??= StreamController<List<Log>>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    return _logController!.stream;
  }

  void _onListen() {
    _hasListeners = true;
    _startFlushTimer();
  }

  void _onCancel() {
    _hasListeners = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      _flush();
    });
  }

  /// 添加日志到缓冲区
  void addLog(Log log) {
    _buffer.add(log);
    // 背压控制：超过最大缓冲区大小时立即刷新
    if (_buffer.length >= _maxBufferSize) {
      _flush();
    }
  }

  /// 批量添加日志
  void addLogs(List<Log> logs) {
    _buffer.addAll(logs);
    if (_buffer.length >= _maxBufferSize) {
      _flush();
    }
  }

  /// 刷新缓冲区到流
  void _flush() {
    if (_buffer.isEmpty || !_hasListeners) return;
    final logs = List<Log>.from(_buffer);
    _buffer.clear();
    _logController?.add(logs);
  }

  /// 设置刷新间隔（根据内存模式动态调整）
  void updateFlushInterval(Duration interval) {
    if (_flushInterval != interval) {
      _flushInterval = interval;
      if (_hasListeners) {
        _startFlushTimer();
      }
    }
  }

  /// 根据内存模式自动调整
  void applyMemoryMode() {
    if (isLowMemoryMode) {
      updateFlushInterval(const Duration(seconds: 5));
    } else if (isReducedMemoryMode) {
      updateFlushInterval(const Duration(seconds: 1));
    } else {
      updateFlushInterval(const Duration(milliseconds: 200));
    }
  }

  /// 获取当前缓冲区大小
  int get bufferSize => _buffer.length;

  /// 清空缓冲区
  void clearBuffer() {
    _buffer.clear();
  }

  /// 销毁
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _logController?.close();
    _logController = null;
    _buffer.clear();
    _hasListeners = false;
  }
}
