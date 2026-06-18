import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../state.dart';
import 'constant.dart';

class FlClashHttpOverrides extends HttpOverrides {
  /// 跟踪所有通过此工厂创建的活跃 HttpClient 实例，
  /// 以便在应用进入后台时关闭空闲连接释放系统资源。
  static final Set<HttpClient> _activeClients = {};
  static bool _isInBackground = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (_, __, ___) => true;
    client.findProxy = (url) {
      if ([localhost].contains(url.host)) {
        return "DIRECT";
      }
      debugPrint("find $url");
      final appController = globalState.appController;
      final port = appController.clashConfig.mixedPort;
      final isStart = appController.appFlowingState.isStart;
      if (!isStart) return "DIRECT";
      return "PROXY localhost:$port";
    };
    // 后台模式下缩短空闲超时，加速连接释放
    if (_isInBackground) {
      client.idleTimeout = const Duration(seconds: 5);
    }
    _activeClients.add(client);
    return client;
  }

  /// 强制空闲连接立即过期，用于激进清理场景。
  /// 通过将 idleTimeout 设为零使空闲连接自然过期，
  /// 而非调用 close() 导致客户端永久不可用。
  static void forceIdleConnectionsExpire() {
    for (final client in _activeClients) {
      try {
        client.idleTimeout = Duration.zero;
      } catch (_) {}
    }
  }

  /// 标记应用进入后台状态，缩短新创建连接的空闲超时。
  static void enterBackground() {
    _isInBackground = true;
    for (final client in _activeClients) {
      try {
        client.idleTimeout = const Duration(seconds: 5);
      } catch (_) {}
    }
  }

  /// 标记应用回到前台状态，恢复正常空闲超时。
  static void exitBackground() {
    _isInBackground = false;
    for (final client in _activeClients) {
      try {
        client.idleTimeout = const Duration(seconds: 15);
      } catch (_) {}
    }
  }
}
