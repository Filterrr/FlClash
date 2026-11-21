import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/clash/interface.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:flutter/foundation.dart';

class ClashService with ClashInterface {
  static ClashService? _instance;

  Completer<ServerSocket> serverCompleter = Completer();

  Completer<Socket> socketCompleter = Completer();

  Map<String, Completer> callbackCompleterMap = {};

  Process? process;

  /// 当前与 core 的连接(用于判断断开的 socket 是否仍是当前连接)。
  Socket? _socket;

  /// 启动阶段(bind / 拉起 core 进程)的失败原因。
  ///
  /// 旧实现把失败原因直接丢掉:completer 永不完成,而 _invoke 又没有超时,
  /// 界面会静默卡在初始化态。记录下来后,后续调用会立刻拿到明确错误。
  Object? _startupError;

  /// 等待 core 建立 socket 连接的最长时间。
  static const Duration _socketReadyTimeout = Duration(seconds: 10);

  Timer? _completerCleanupTimer;

  factory ClashService() {
    _instance ??= ClashService._internal();
    return _instance!;
  }

  ClashService._internal() {
    // 这两个调用都不能 await(_createServer 内部是 server 的 accept 循环,
    // 永不返回),但必须各自捕获异常:否则 bind / Process.start 失败时
    // serverCompleter / socketCompleter 永不完成,配合 _invoke 里对 socket 的
    // 无超时等待,App 会静默卡死在初始化态。
    unawaited(_createServer().catchError((Object e, StackTrace s) {
      debugPrint("create server error ===> $e\n$s");
      _startupError = e;
    }));
    unawaited(startCore().catchError((Object e, StackTrace s) {
      debugPrint("start core error ===> $e\n$s");
      _startupError = e;
    }));
    _startCompleterCleanup();
  }

  /// 等待与 core 的连接,失败/超时都抛出明确错误而不是永久挂起。
  Future<Socket> _waitSocket() async {
    final error = _startupError;
    if (error != null) {
      throw StateError("clash core is not ready: $error");
    }
    try {
      return await socketCompleter.future.timeout(_socketReadyTimeout);
    } on TimeoutException {
      throw StateError(
        "clash core is not ready: no socket connection in "
        "${_socketReadyTimeout.inSeconds}s",
      );
    }
  }

  /// 定期清理已完成的 completer，防止内存累积
  /// 后台时降低清理频率以减少 CPU 唤醒
  void _startCompleterCleanup() {
    _completerCleanupTimer?.cancel();
    _completerCleanupTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        callbackCompleterMap.removeWhere((key, completer) {
          return completer.isCompleted;
        });
      },
    );
  }

  _createServer() async {
    final address = !Platform.isWindows
        ? InternetAddress(
            unixSocketPath,
            type: InternetAddressType.unix,
          )
        : InternetAddress(
            localhost,
            type: InternetAddressType.IPv4,
          );
    await _deleteSocketFile();
    final server = await ServerSocket.bind(
      address,
      0,
      shared: true,
    );
    serverCompleter.complete(server);
    await for (final socket in server) {
      await _destroySocket();
      _socket = socket;
      socketCompleter.complete(socket);
      socket
          .cast<List<int>>()
          // 用 Utf8Decoder 而不是逐包 utf8.decode:一个多字节字符被拆到两个
          // 网络包里时(大 payload 如 getProxies),逐包解码会产生乱码,
          // 下游 json.decode 抛 FormatException 且消息被整条丢掉。
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (data) {
              _handleAction(
                Action.fromJson(
                  json.decode(data.trim()),
                ),
              );
            },
            onError: (Object e, StackTrace s) {
              debugPrint("socket error ===> $e\n$s");
              _handleSocketClosed(socket);
            },
            onDone: () {
              _handleSocketClosed(socket);
            },
            cancelOnError: true,
          );
    }
  }

  startCore() async {
    if (process != null) {
      await shutdown();
    }
    final serverSocket = await serverCompleter.future;
    final arg = Platform.isWindows
        ? "${serverSocket.port}"
        : serverSocket.address.address;
    bool isSuccess = false;
    if (Platform.isWindows && await system.checkIsAdmin()) {
      isSuccess = await request.startCoreByHelper(arg);
    }
    if (isSuccess) {
      return;
    }
    process = await Process.start(
      appPath.corePath,
      [
        arg,
      ],
    );
    process!.stdout.listen((_) {});
  }

  _deleteSocketFile() async {
    if (!Platform.isWindows) {
      final file = File(unixSocketPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  _destroySocket() async {
    if (socketCompleter.isCompleted) {
      final lastSocket = await socketCompleter.future;
      await lastSocket.close();
      socketCompleter = Completer();
    }
    _socket = null;
  }

  /// core 进程退出 / 连接断开:复位 socket 状态,避免后续 IPC 一直往死
  /// socket 上写(只能等各自超时,且没有自愈路径)。
  _handleSocketClosed(Socket socket) {
    if (!identical(_socket, socket)) {
      return;
    }
    _socket = null;
    socketCompleter = Completer();
  }

  _handleAction(Action action) {
    final completer = callbackCompleterMap[action.id];
    switch (action.method) {
      case ActionMethod.initClash:
      case ActionMethod.shutdown:
      case ActionMethod.getIsInit:
      case ActionMethod.startListener:
      case ActionMethod.resetTraffic:
      case ActionMethod.closeConnections:
      case ActionMethod.closeConnection:
      case ActionMethod.stopListener:
        completer?.complete(action.data as bool);
        return;
      case ActionMethod.changeProxy:
      case ActionMethod.getProxies:
      case ActionMethod.getTraffic:
      case ActionMethod.getTotalTraffic:
      case ActionMethod.asyncTestDelay:
      case ActionMethod.asyncTestSpeed:
      case ActionMethod.getConnections:
      case ActionMethod.getExternalProviders:
      case ActionMethod.getExternalProvider:
      case ActionMethod.validateConfig:
      case ActionMethod.updateConfig:
      case ActionMethod.updateGeoData:
      case ActionMethod.updateExternalProvider:
      case ActionMethod.sideLoadExternalProvider:
        completer?.complete(action.data as String);
        return;
      case ActionMethod.message:
        clashMessage.controller.add(action.data as String);
        return;
      case ActionMethod.forceGc:
      case ActionMethod.startLog:
      case ActionMethod.stopLog:
        return;
    }
  }

  Future<T> _invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
    FutureOr<T> Function()? onTimeout,
  }) async {
    final id = "${method.name}#${other.id}";
    final socket = await _waitSocket();
    callbackCompleterMap[id] = Completer<T>();
    socket.writeln(
      json.encode(
        Action(
          id: id,
          method: method,
          data: data,
        ),
      ),
    );
    return (callbackCompleterMap[id] as Completer<T>).safeFuture(
      timeout: timeout,
      onLast: () {
        callbackCompleterMap.remove(id);
      },
      onTimeout: onTimeout,
      functionName: id,
    );
  }

  _prueInvoke({
    required ActionMethod method,
    dynamic data,
  }) async {
    final id = "${method.name}#${other.id}";
    final socket = await _waitSocket();
    socket.writeln(
      json.encode(
        Action(
          id: id,
          method: method,
          data: data,
        ),
      ),
    );
  }

  @override
  Future<bool> init(String homeDir) {
    return _invoke<bool>(
      method: ActionMethod.initClash,
      data: homeDir,
    );
  }

  @override
  shutdown() async {
    await _invoke<bool>(
      method: ActionMethod.shutdown,
    );
    if (Platform.isWindows) {
      await request.stopCoreByHelper();
    }
    await _destroySocket();
    process?.kill();
    process = null;
  }

  @override
  Future<bool> get isInit {
    return _invoke<bool>(
      method: ActionMethod.getIsInit,
    );
  }

  @override
  forceGc() {
    _prueInvoke(method: ActionMethod.forceGc);
  }

  @override
  FutureOr<String> validateConfig(String data) {
    return _invoke<String>(
      method: ActionMethod.validateConfig,
      data: data,
    );
  }

  @override
  Future<String> updateConfig(UpdateConfigParams updateConfigParams) async {
    return await _invoke<String>(
      method: ActionMethod.updateConfig,
      data: json.encode(updateConfigParams),
      timeout: const Duration(seconds: 20),
    );
  }

  @override
  Future<String> getProxies() {
    return _invoke<String>(
      method: ActionMethod.getProxies,
    );
  }

  @override
  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) {
    return _invoke<String>(
      method: ActionMethod.changeProxy,
      data: json.encode(changeProxyParams),
    );
  }

  @override
  FutureOr<String> getExternalProviders() {
    return _invoke<String>(
      method: ActionMethod.getExternalProviders,
    );
  }

  @override
  FutureOr<String> getExternalProvider(String externalProviderName) {
    return _invoke<String>(
      method: ActionMethod.getExternalProvider,
      data: externalProviderName,
    );
  }

  @override
  Future<String> updateGeoData({
    required String geoType,
    required String geoName,
  }) {
    return _invoke<String>(
      method: ActionMethod.updateGeoData,
      data: json.encode(
        {
          "geoType": geoType,
          "geoName": geoName,
        },
      ),
    );
  }

  @override
  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) {
    return _invoke<String>(
      method: ActionMethod.sideLoadExternalProvider,
      data: json.encode({
        "providerName": providerName,
        "data": data,
      }),
    );
  }

  @override
  Future<String> updateExternalProvider(String providerName) {
    return _invoke<String>(
      method: ActionMethod.updateExternalProvider,
      data: providerName,
    );
  }

  @override
  FutureOr<String> getConnections() {
    return _invoke<String>(
      method: ActionMethod.getConnections,
    );
  }

  @override
  Future<bool> closeConnections() {
    return _invoke<bool>(
      method: ActionMethod.closeConnections,
    );
  }

  @override
  Future<bool> closeConnection(String id) {
    return _invoke<bool>(
      method: ActionMethod.closeConnection,
      data: id,
    );
  }

  @override
  FutureOr<String> getTotalTraffic(bool value) {
    return _invoke<String>(
      method: ActionMethod.getTotalTraffic,
      data: value,
    );
  }

  @override
  FutureOr<String> getTraffic(bool value) {
    return _invoke<String>(
      method: ActionMethod.getTraffic,
      data: value,
    );
  }

  @override
  resetTraffic() {
    _prueInvoke(method: ActionMethod.resetTraffic);
  }

  @override
  startLog() {
    _prueInvoke(method: ActionMethod.startLog);
  }

  @override
  stopLog() {
    _prueInvoke(method: ActionMethod.stopLog);
  }

  @override
  Future<bool> startListener() {
    return _invoke<bool>(
      method: ActionMethod.startListener,
    );
  }

  @override
  stopListener() {
    return _invoke<bool>(
      method: ActionMethod.stopListener,
    );
  }

  @override
  Future<String> asyncTestDelay(String proxyName) {
    final delayParams = {
      "proxy-name": proxyName,
      "timeout": httpTimeoutDuration.inMilliseconds,
    };
    return _invoke<String>(
      method: ActionMethod.asyncTestDelay,
      data: json.encode(delayParams),
      timeout: Duration(
        milliseconds: 6000,
      ),
      onTimeout: () {
        return json.encode(
          Delay(
            name: proxyName,
            value: -1,
          ),
        );
      },
    );
  }

  @override
  Future<String> asyncTestSpeed(String proxyName, String url, int timeout) {
    final speedParams = {
      "proxy-name": proxyName,
      "url": url,
      "timeout": timeout,
    };
    return _invoke<String>(
      method: ActionMethod.asyncTestSpeed,
      data: json.encode(speedParams),
      timeout: Duration(
        milliseconds: timeout + 5000,
      ),
      onTimeout: () {
        return json.encode(
          SpeedResult(
            name: proxyName,
          ),
        );
      },
    );
  }

  destroy() async {
    _completerCleanupTimer?.cancel();
    _completerCleanupTimer = null;
    // 清理所有残留的 completer
    for (final completer in callbackCompleterMap.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Service destroyed'));
      }
    }
    callbackCompleterMap.clear();
    // ClashService 是单例,而监听用的 ServerSocket 与 unix socket 文件是
    // 它的长期资源:旧实现在这里 server.close() + 删除 socket 文件,导致
    // 「停止 → 再启动」时 startCore() 把已关闭/已删除的地址交给新的 core
    // 进程(connect 必然失败),且 socketCompleter 也不会再完成,后续 IPC
    // 全部挂起。这里只断开当前连接,保留监听端。
    await _destroySocket();
  }
}

final clashService = system.isDesktop ? ClashService() : null;
