import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:path/path.dart' show join;

/// 极简的 JSON 文件存储,给流量统计 / 节点质量 / 进程规则这类小型历史数据用。
///
/// 为什么不上 sqlite / hive:数据量是「每天一条汇总」「每个节点几十个采样点」
/// 这个量级,JSON 完全够用,而且不用往 pubspec 里塞一个二进制依赖 ——
/// 这仓库在 CI 之外没有任何本地构建环境,依赖越少越好。
///
/// 写盘一律走「临时文件 + rename」:进程被杀或掉电时,读到的要么是旧版本,
/// 要么是新版本,不会是写了一半的残废 JSON。
class LocalStore {
  static const String _dirName = 'store';

  static Future<File> _resolve(String name) async {
    final home = await appPath.getHomeDirPath();
    final dir = Directory(join(home, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(join(dir.path, name));
  }

  /// 读取并反序列化。文件不存在 / 内容损坏 / 无权限,一律返回 null,
  /// 由调用方决定回退策略 —— 存储层不该因为读不到就炸掉整个页面。
  static Future<dynamic> read(String name) async {
    try {
      final file = await _resolve(name);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return json.decode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String name, Object? data) async {
    try {
      final file = await _resolve(name);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json.encode(data), flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // 写失败不该把调用方拖下水:这些数据都是「有更好,没有也能跑」的。
    }
  }

  static Future<void> remove(String name) async {
    try {
      final file = await _resolve(name);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
