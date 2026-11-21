String normalizeVersion(String version) {
  final trimmed = version.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
    return trimmed.substring(1);
  }
  return trimmed;
}

int compareVersions(String version1, String version2) {
  final v1 = _parseVersion(version1);
  final v2 = _parseVersion(version2);
  if (v1.major != v2.major) {
    return v1.major.compareTo(v2.major);
  }
  if (v1.minor != v2.minor) {
    return v1.minor.compareTo(v2.minor);
  }
  if (v1.patch != v2.patch) {
    return v1.patch.compareTo(v2.patch);
  }
  return v1.build.compareTo(v2.build);
}

/// 取版本段里的数字前缀,容忍 `-beta`、`-rs.1` 这类后缀。
///
/// 旧实现直接用 int.parse:release tag 带后缀时抛 FormatException,调用方
/// 只能把它归入「检查更新失败」(自动更新于是永远报错)。
int _parseVersionPart(String value) {
  final match = RegExp(r'^\d+').stringMatch(value.trim());
  return match == null ? 0 : int.parse(match);
}

_VersionParts _parseVersion(String version) {
  final normalized = normalizeVersion(version);
  if (normalized.isEmpty) {
    return const _VersionParts(major: 0, minor: 0, patch: 0, build: 0);
  }
  final versionAndBuild = normalized.split('+');
  final parts = versionAndBuild.first.split('.');
  return _VersionParts(
    major: parts.isNotEmpty ? _parseVersionPart(parts[0]) : 0,
    minor: parts.length > 1 ? _parseVersionPart(parts[1]) : 0,
    patch: parts.length > 2 ? _parseVersionPart(parts[2]) : 0,
    build: versionAndBuild.length > 1
        ? _parseVersionPart(versionAndBuild[1])
        : 0,
  );
}

class _VersionParts {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const _VersionParts({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });
}
