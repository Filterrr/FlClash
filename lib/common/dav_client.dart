import 'dart:async';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:webdav_client/webdav_client.dart';

class DAVClient {
  late Client client;
  Completer<bool> pingCompleter = Completer();
  late String fileName;

  DAVClient(DAV dav) {
    client = newClient(
      dav.uri,
      user: dav.user,
      password: dav.password,
    );
    fileName = dav.fileName;
    client.setHeaders(
      {
        'accept-charset': 'utf-8',
        'Content-Type': 'text/xml',
      },
    );
    client.setConnectTimeout(8000);
    client.setSendTimeout(60000);
    client.setReceiveTimeout(60000);
    pingCompleter.complete(_ping());
  }

  /// 从安全存储创建 DAVClient，密码从加密存储中读取
  static Future<DAVClient> fromSecureStorage(DAV dav) async {
    final securePassword = await SecureStorage.instance.read(
      'dav_password_${dav.user}_${dav.uri.hashCode}',
    );
    final davWithPassword = dav.copyWith(
      password: securePassword ?? dav.password,
    );
    return DAVClient(davWithPassword);
  }

  /// 保存 DAV 密码到安全存储
  static Future<void> savePasswordSecurely(DAV dav) async {
    final key = 'dav_password_${dav.user}_${dav.uri.hashCode}';
    await SecureStorage.instance.write(key, dav.password);
  }

  /// 从安全存储删除 DAV 密码
  static Future<void> deletePasswordSecurely(DAV dav) async {
    final key = 'dav_password_${dav.user}_${dav.uri.hashCode}';
    await SecureStorage.instance.delete(key);
  }

  Future<bool> _ping() async {
    try {
      await client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  get root => "/$appName";

  get backupFile => "$root/$fileName";

  backup(Uint8List data) async {
    await client.mkdir("$root");
    await client.write("$backupFile", data);
    return true;
  }

  Future<List<int>> recovery() async {
    await client.mkdir("$root");
    final data = await client.read(backupFile);
    return data;
  }
}
