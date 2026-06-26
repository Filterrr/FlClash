import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get fullVersion {
    if (buildNumber.trim().isEmpty) {
      return version;
    }
    return '$version+$buildNumber';
  }

  String get ua => [
        "$appName/v$version",
        "clash-verge",
        "Platform/${Platform.operatingSystem}",
      ].join(" ");
}
