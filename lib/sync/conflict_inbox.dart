import '../storage/json_repository.dart';

class SyncConflict {
  const SyncConflict({
    required this.path,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.conflictingFields,
    required this.raw,
  });

  final String path;
  final String entityType;
  final String entityId;
  final String reason;
  final List<String> conflictingFields;
  final Map<String, Object?> raw;
}

class SyncConflictInbox {
  const SyncConflictInbox(this._documents);

  final JsonDocumentRepository _documents;

  Future<List<SyncConflict>> listOpen() async {
    final paths = (await _documents.listFiles('sync/conflicts'))
        .where((path) => path.endsWith('.json'))
        .toList(growable: false);
    final conflicts = <SyncConflict>[];
    for (final path in paths) {
      final raw = await _documents.readObject(path);
      if (raw == null || raw['resolvedAt'] != null) continue;
      conflicts.add(
        SyncConflict(
          path: path,
          entityType: raw['entityType'] as String? ?? 'unknown',
          entityId: raw['entityId'] as String? ?? 'unknown',
          reason: raw['reason'] as String? ?? 'Unspecified conflict',
          conflictingFields:
              (raw['conflictingFields'] as List?)?.whereType<String>().toList(growable: false) ?? const [],
          raw: raw,
        ),
      );
    }
    return conflicts;
  }

  Future<void> keepLocal(SyncConflict conflict) async {
    await _documents.writeObject(conflict.path, {
      ...conflict.raw,
      'resolution': 'keepLocal',
      'resolvedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
