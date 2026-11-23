import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:path/path.dart' show join;

/// 订阅配置快照 / 回滚。
///
/// 订阅更新是「下载 → 覆盖本地文件」,一旦拉到半截网络断了、或者上游
/// 推了一份坏配置,本地那份好配置就没了 —— 而用户往往过一阵才发现。
/// 这里在每次更新前留一份快照,提供一键回到上一版。
///
/// 只保留最近一份:留一个"上一版"能覆盖绝大多数事故,再多的历史
/// 对普通用户只是噪音(要做完整版本管理是另一个功能)。
class ProfileSnapshotService {
  static const String _dirName = 'snapshot';

  static Future<Directory> _dir() async {
    final home = await appPath.getHomeDirPath();
    final dir = Directory(join(home, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _fileName(String profileId) => '$profileId.yaml';

  static Future<File?> _snapshotFile(String profileId) async {
    try {
      final profilePath = await appPath.getProfilePath(profileId);
      if (profilePath == null) return null;
      final source = File(profilePath);
      if (!await source.exists()) return null;
      return source;
    } catch (_) {
      return null;
    }
  }

  /// 在更新**之前**调用:把当前配置存成快照。
  static Future<void> snapshot(String profileId) async {
    if (profileId.isEmpty) return;
    try {
      final source = await _snapshotFile(profileId);
      if (source == null) return;
      final dir = await _dir();
      await source.copy(join(dir.path, _fileName(profileId)));
    } catch (_) {
      // 快照失败不该阻断正常更新流程
    }
  }

  /// 是否存在可回滚的快照。
  static Future<bool> hasSnapshot(String profileId) async {
    try {
      final dir = await _dir();
      return await File(join(dir.path, _fileName(profileId))).exists();
    } catch (_) {
      return false;
    }
  }

  static Future<DateTime?> snapshotTime(String profileId) async {
    try {
      final dir = await _dir();
      final file = File(join(dir.path, _fileName(profileId)));
      if (!await file.exists()) return null;
      return (await file.stat()).modified;
    } catch (_) {
      return null;
    }
  }

  /// 用快照覆盖当前配置。返回是否成功。
  static Future<bool> restore(String profileId) async {
    if (profileId.isEmpty) return false;
    try {
      final dir = await _dir();
      final backup = File(join(dir.path, _fileName(profileId)));
      if (!await backup.exists()) return false;
      final profilePath = await appPath.getProfilePath(profileId);
      if (profilePath == null) return false;
      await backup.copy(profilePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> discard(String profileId) async {
    try {
      final dir = await _dir();
      final file = File(join(dir.path, _fileName(profileId)));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
