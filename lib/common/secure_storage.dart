import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感数据安全存储层
/// 使用 flutter_secure_storage 加密存储密码、Token 等敏感信息
class SecureStorage {
  static SecureStorage? _instance;
  static SecureStorage get instance => _instance ??= SecureStorage._();

  late final FlutterSecureStorage _storage;

  // 存储键定义
  static const String _keyDavPassword = 'dav_password';
  static const String _keyDavUsername = 'dav_username';
  static const String _keyProxyPassword = 'proxy_password';
  static const String _keyApiToken = 'api_token';

  SecureStorage._() {
    _storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
  }

  // --- DAV 密码 ---
  Future<String?> getDavPassword() => _storage.read(key: _keyDavPassword);

  Future<void> setDavPassword(String password) =>
      _storage.write(key: _keyDavPassword, value: password);

  Future<void> deleteDavPassword() =>
      _storage.delete(key: _keyDavPassword);

  // --- DAV 用户名 ---
  Future<String?> getDavUsername() => _storage.read(key: _keyDavUsername);

  Future<void> setDavUsername(String username) =>
      _storage.write(key: _keyDavUsername, value: username);

  Future<void> deleteDavUsername() =>
      _storage.delete(key: _keyDavUsername);

  // --- 代理密码 ---
  Future<String?> getProxyPassword() => _storage.read(key: _keyProxyPassword);

  Future<void> setProxyPassword(String password) =>
      _storage.write(key: _keyProxyPassword, value: password);

  Future<void> deleteProxyPassword() =>
      _storage.delete(key: _keyProxyPassword);

  // --- API Token ---
  Future<String?> getApiToken() => _storage.read(key: _keyApiToken);

  Future<void> setApiToken(String token) =>
      _storage.write(key: _keyApiToken, value: token);

  Future<void> deleteApiToken() =>
      _storage.delete(key: _keyApiToken);

  // --- 通用方法 ---
  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> writeJson(String key, Map<String, dynamic> value) =>
      _storage.write(key: key, value: json.encode(value));

  Future<Map<String, dynamic>?> readJson(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 清除所有安全存储数据
  Future<void> deleteAll() => _storage.deleteAll();

  /// 检查平台是否支持安全存储
  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}
