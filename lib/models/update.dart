enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  verifying,
  installing,
  failed,
  readyToRestart,
}

class UpdateAsset {
  final String name;
  final String browserDownloadUrl;
  final int size;

  const UpdateAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
  });
}

class UpdateInfo {
  final String version;
  final String tagName;
  final String releaseNotes;
  final List<UpdateAsset> assets;
  final DateTime publishedAt;

  /// filename -> sha256 hex (lowercase). Parsed from release body lines
  /// formatted as "<filename> <sha256>". Empty when body contains no hashes.
  final Map<String, String> sha256Map;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.assets,
    required this.publishedAt,
    this.sha256Map = const {},
  });
}

class DownloadProgress {
  final int downloaded;
  final int total;
  final int speed;

  const DownloadProgress({
    required this.downloaded,
    required this.total,
    required this.speed,
  });

  double get percent => total > 0 ? downloaded / total : 0;
}

class UpdateException implements Exception {
  final String message;
  final UpdateStatus stage;

  const UpdateException(this.message, this.stage);

  @override
  String toString() => message;
}
