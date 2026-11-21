import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';

class Service {
  static Service? _instance;
  late MethodChannel methodChannel;
  ReceivePort? receiver;

  Service._internal() {
    methodChannel = const MethodChannel("service");
  }

  factory Service() {
    _instance ??= Service._internal();
    return _instance!;
  }

  Future<bool?> init() async {
    return await methodChannel.invokeMethod<bool>("init");
  }

  /// 请求服务侧销毁引擎。
  ///
  /// 服务引擎会在处理完该请求后销毁自己,**方法通道的回复很可能来不及投递**,
  /// 所以这里必须带超时兜底:否则 await 会永久挂起,停止流程再也走不完。
  Future<void> destroy() async {
    try {
      await methodChannel
          .invokeMethod<bool>("destroy")
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // 引擎已在销毁中 / 回复丢失:都属于预期情况。
    }
  }
}

final service =
    Platform.isAndroid ? Service() : null;
