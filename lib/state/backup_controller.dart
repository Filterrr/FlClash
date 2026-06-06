import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fl_clash/common/archive.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';

/// 备份与恢复控制器
/// 从 AppController 中拆分出的备份/恢复操作
class BackupController {
  final BuildContext context;

  BackupController(this.context);

  Config get config => context.read<Config>();
  ClashConfig get clashConfig => context.read<ClashConfig>();

  Future<List<int>> backupData() async {
    final homeDirPath = await appPath.getHomeDirPath();
    final profilesPath = await appPath.getProfilesPath();
    final configJson = config.toJson();
    final clashConfigJson = clashConfig.toJson();
    return Isolate.run<List<int>>(() async {
      final archive = Archive();
      archive.add("config.json", configJson);
      archive.add("clashConfig.json", clashConfigJson);
      await archive.addDirectoryToArchive(profilesPath, homeDirPath);
      final zipEncoder = ZipEncoder();
      return zipEncoder.encode(archive) ?? [];
    });
  }

  recoveryData(
    List<int> data,
    RecoveryOption recoveryOption,
  ) async {
    final archive = await Isolate.run<Archive>(() {
      final zipDecoder = ZipDecoder();
      return zipDecoder.decodeBytes(data);
    });
    final homeDirPath = await appPath.getHomeDirPath();
    final configs =
        archive.files.where((item) => item.name.endsWith(".json")).toList();
    final profiles =
        archive.files.where((item) => !item.name.endsWith(".json"));
    final configIndex =
        configs.indexWhere((config) => config.name == "config.json");
    final clashConfigIndex =
        configs.indexWhere((config) => config.name == "clashConfig.json");
    if (configIndex == -1 || clashConfigIndex == -1) throw "invalid backup.zip";
    final configFile = configs[configIndex];
    final clashConfigFile = configs[clashConfigIndex];
    final tempConfig = Config.fromJson(
      json.decode(utf8.decode(configFile.content)),
    );
    final tempClashConfig = ClashConfig.fromJson(
      json.decode(utf8.decode(clashConfigFile.content)),
    );
    for (final profile in profiles) {
      final filePath = join(homeDirPath, profile.name);
      final file = File(filePath);
      await file.create(recursive: true);
      await file.writeAsBytes(profile.content);
    }
    if (recoveryOption == RecoveryOption.onlyProfiles) {
      config.update(tempConfig, RecoveryOption.onlyProfiles);
    } else {
      config.update(tempConfig, RecoveryOption.all);
      clashConfig.update(tempClashConfig);
    }
  }
}
