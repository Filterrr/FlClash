import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

class ClashMessage {
  final controller = StreamController.broadcast();
  StreamSubscription? _messageSubscription;
  bool _isInBackground = false;

  /// 后台模式下被跳过的消息计数，用于诊断
  int _backgroundSkippedCount = 0;

  ClashMessage._() {
    _messageSubscription = clashLib?.receiver.listen(controller.add);
    controller.stream.listen(
      (message) {
        final m = AppMessage.fromJson(json.decode(message));
        // 后台模式下跳过非关键消息（log、request、delay），
        // 仅处理关键消息（started、loaded）以节省 CPU 资源。
        // 消息仍被消费以防止 ReceivePort 积压导致内存增长。
        if (_isInBackground && _isNonCriticalMessage(m.type)) {
          _backgroundSkippedCount++;
          return;
        }
        for (final AppMessageListener listener in _listeners) {
          switch (m.type) {
            case AppMessageType.log:
              listener.onLog(Log.fromJson(m.data));
              break;
            case AppMessageType.delay:
              listener.onDelay(Delay.fromJson(m.data));
              break;
            case AppMessageType.request:
              listener.onRequest(Connection.fromJson(m.data));
              break;
            case AppMessageType.started:
              listener.onStarted(m.data);
              break;
            case AppMessageType.loaded:
              listener.onLoaded(m.data);
              break;
          }
        }
      },
    );
  }

  /// 判断消息类型是否为非关键消息，可在后台跳过。
  bool _isNonCriticalMessage(AppMessageType type) {
    switch (type) {
      case AppMessageType.log:
      case AppMessageType.request:
      case AppMessageType.delay:
        return true;
      case AppMessageType.started:
      case AppMessageType.loaded:
        return false;
    }
  }

  /// 标记进入后台模式，跳过非关键消息处理以节省 CPU。
  void enterBackground() {
    _isInBackground = true;
  }

  /// 标记回到前台模式，恢复所有消息处理。
  void exitBackground() {
    _isInBackground = false;
    _backgroundSkippedCount = 0;
  }

  /// 获取后台模式下跳过的消息计数，用于诊断。
  int get backgroundSkippedCount => _backgroundSkippedCount;

  /// 当前是否处于后台模式。
  bool get isInBackground => _isInBackground;

  static final ClashMessage instance = ClashMessage._();

  final ObserverList<AppMessageListener> _listeners =
      ObserverList<AppMessageListener>();

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(AppMessageListener listener) {
    _listeners.add(listener);
  }

  void removeListener(AppMessageListener listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    controller.close();
    _listeners.clear();
    _isInBackground = false;
  }
}

final clashMessage = ClashMessage.instance;
