import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';

/// 订阅/配置文件管理控制器
/// 从 AppController 中拆分出的配置文件相关操作
class ProfileController {
  final BuildContext context;

  ProfileController(this.context);

  Config get config => context.read<Config>();
  AppState get appState => context.read<AppState>();
  AppFlowingState get appFlowingState => context.read<AppFlowingState>();

  addProfile(Profile profile) async {
    config.setProfile(profile);
    if (config.currentProfileId != null) return;
    await globalState.appController.changeProfile(profile.id);
  }

  deleteProfile(String id) async {
    config.deleteProfileById(id);
    clearEffect(id);
    if (config.currentProfileId == id) {
      if (config.profiles.isNotEmpty) {
        final updateId = config.profiles.first.id;
        globalState.appController.changeProfile(updateId);
      } else {
        globalState.appController.changeProfile(null);
        globalState.appController.updateStatus(false);
      }
    }
  }

  Future<void> updateProfile(Profile profile) async {
    final newProfile = await profile.update();
    config.setProfile(
      newProfile.copyWith(isUpdating: false),
    );
  }

  autoUpdateProfiles() async {
    for (final profile in config.profiles) {
      if (!profile.autoUpdate) continue;
      final isNotNeedUpdate = profile.lastUpdateDate
          ?.add(profile.autoUpdateDuration)
          .isBeforeNow;
      if (isNotNeedUpdate == false || profile.type == ProfileType.file) {
        continue;
      }
      try {
        updateProfile(profile);
      } catch (e) {
        appFlowingState.addLog(
          Log(logLevel: LogLevel.info, payload: e.toString()),
        );
      }
    }
  }

  updateProfiles() async {
    for (final profile in config.profiles) {
      if (profile.type == ProfileType.file) continue;
      await updateProfile(profile);
    }
  }

  clearEffect(String profileId) async {
    final profilePath = await appPath.getProfilePath(profileId);
    final providersPath = await appPath.getProvidersPath(profileId);
    return await Isolate.run(() async {
      if (profilePath != null) {
        await File(profilePath).delete(recursive: true);
      }
      if (providersPath != null) {
        await File(providersPath).delete(recursive: true);
      }
    });
  }

  /// 对当前配置的代理节点进行去重
  Future<int> deduplicateProfileNodes() async {
    final groups = appState.groups;
    int duplicateCount = 0;
    for (final group in groups) {
      final seen = <String>{};
      for (final proxy in group.all) {
        final key = '${proxy.name}|${proxy.type}';
        if (seen.contains(key)) {
          duplicateCount++;
        } else {
          seen.add(key);
        }
      }
    }
    return duplicateCount;
  }
}
