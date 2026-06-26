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

_VersionParts _parseVersion(String version) {
  final normalized = normalizeVersion(version);
  if (normalized.isEmpty) {
    throw const FormatException('Version is empty');
  }
  final versionAndBuild = normalized.split('+');
  if (versionAndBuild.length > 2) {
    throw FormatException('Invalid version: $version');
  }
  final parts = versionAndBuild.first.split('.');
  if (parts.isEmpty || parts.length > 3) {
    throw FormatException('Invalid version: $version');
  }
  return _VersionParts(
    major: int.parse(parts[0]),
    minor: parts.length > 1 ? int.parse(parts[1]) : 0,
    patch: parts.length > 2 ? int.parse(parts[2]) : 0,
    build: versionAndBuild.length == 2 ? int.parse(versionAndBuild[1]) : 0,
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
