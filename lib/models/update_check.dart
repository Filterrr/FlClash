enum UpdateCheckStatus {
  available,
  upToDate,
  failed,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final Map<String, dynamic>? data;

  const UpdateCheckResult({
    required this.status,
    this.data,
  });
}
