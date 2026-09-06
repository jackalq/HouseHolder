class SyncObject {
  const SyncObject({
    required this.path,
    this.remoteId,
    this.modifiedAt,
    this.revision,
  });

  final String path;
  final String? remoteId;
  final DateTime? modifiedAt;
  final String? revision;
}

abstract interface class SyncTransport {
  Future<List<SyncObject>> list(String prefix);
  Future<String> readText(SyncObject object);
  Future<void> writeText(String path, String content);
}
