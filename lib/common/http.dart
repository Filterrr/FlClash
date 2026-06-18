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

  /// 关闭所有活跃 HttpClient 的空闲连接，释放网络资源。
  /// 在应用进入后台时调用，保留活跃连接避免中断进行中的请求。
  static void closeIdleConnections() {
    for (final client in _activeClients) {
      try {
        client.close(force: false);
      } catch (_) {}
    }
    _activeClients.removeWhere((c) => false);
  }

  /// 强制关闭所有 HttpClient 连接，用于激进清理场景。
  static void forceCloseAllConnections() {
    for (final client in _activeClients) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
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
