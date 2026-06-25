import 'dart:io';

import 'package:flutter/services.dart';

/// Lightweight MethodChannel wrapper for Android-only update operations
/// (APK install intent + app restart). Null on non-Android platforms.
class UpdatePlugin {
  static UpdatePlugin? _instance;
  final MethodChannel _channel = const MethodChannel("fl_clash/update");

  UpdatePlugin._internal();

  factory UpdatePlugin() {
    _instance ??= UpdatePlugin._internal();
    return _instance!;
  }

  /// Trigger system APK install UI for the file at [path].
  /// Returns true if the install intent was launched successfully.
  Future<bool> installApk(String path) async {
    final result = await _channel.invokeMethod<bool>("installApk", {
      "path": path,
    });
    return result ?? false;
  }

  /// Restart the app (kill process + relaunch MainActivity).
  Future<bool> restartApp() async {
    final result = await _channel.invokeMethod<bool>("restartApp");
    return result ?? false;
  }
}

final updatePlugin = Platform.isAndroid ? UpdatePlugin() : null;
