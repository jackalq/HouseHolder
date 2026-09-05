import '../storage/change_event.dart';
import '../storage/entity_event_writer.dart';
import '../storage/hash_service.dart';
import '../storage/json_repository.dart';
import 'materialized_entity_store.dart';

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

  List<String> comparisonLines() {
    final localRecord = raw['localRecord'];
    final remoteRaw = raw['remoteEvent'];
    if (localRecord is! Map || remoteRaw is! Map) return const [];
    final localDataRaw = localRecord['data'];
    final localData = localDataRaw is Map
        ? localDataRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    final remote = ChangeEvent.fromJson(
      remoteRaw.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (remote.operation == ChangeOperation.delete) {
      return const ['遠端要求刪除；本機有較新的修改。'];
    }
    Map<String, Object?> remoteValues = remote.patch ?? const {};
    if (remote.operation == ChangeOperation.create) {
      final valueData = remote.value?['data'];
      if (valueData is Map) {
        remoteValues = valueData.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    final fields = conflictingFields.isEmpty ? remoteValues.keys.toList() : conflictingFields;
    return fields.map((field) {
      final local = localData[field];
      final remoteValue = remoteValues[field];
      return '$field：本機 ${local ?? 'null'} ／ 遠端 ${remoteValue ?? 'null'}';
    }).toList(growable: false);
  }
}

class SyncConflictInbox {
  SyncConflictInbox({
    required JsonDocumentRepository documents,
    required EntityEventWriter writer,
    HashService hashService = const HashService(),
  })  : _documents = documents,
        _writer = writer,
        _hashService = hashService,
        _store = MaterializedEntityStore(documents);

  final JsonDocumentRepository _documents;
  final EntityEventWriter _writer;
  final HashService _hashService;
  final MaterializedEntityStore _store;

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
    final context = await _context(conflict);
    final nextData = Map<String, Object?>.from(context.currentData);
    final remotePatch = context.remote.patch ?? const <String, Object?>{};
    if (context.remote.operation == ChangeOperation.update) {
      for (final entry in remotePatch.entries) {
        if (!conflict.conflictingFields.contains(entry.key)) nextData[entry.key] = entry.value;
      }
    }
    await _writeResolution(conflict, context, nextData, deleted: false);
  }

  Future<void> acceptRemote(SyncConflict conflict) async {
    final context = await _context(conflict);
    if (context.remote.operation == ChangeOperation.delete) {
      await _writeResolution(conflict, context, context.currentData, deleted: true);
      return;
    }

    final nextData = Map<String, Object?>.from(context.currentData);
    if (context.remote.operation == ChangeOperation.create) {
      final rawData = context.remote.value?['data'];
      if (rawData is! Map) throw const FormatException('Remote create conflict has no data.');
      nextData
        ..clear()
        ..addAll(rawData.map((key, value) => MapEntry(key.toString(), value)));
    } else {
      nextData.addAll(context.remote.patch ?? const <String, Object?>{});
    }
    await _writeResolution(conflict, context, nextData, deleted: false);
  }

  Future<_ResolutionContext> _context(SyncConflict conflict) async {
    final remoteRaw = conflict.raw['remoteEvent'];
    if (remoteRaw is! Map) throw const FormatException('Conflict has no remote event.');
    final remote = ChangeEvent.fromJson(
      remoteRaw.map((key, value) => MapEntry(key.toString(), value)),
    );
    final current = await _store.latestFor(remote);
    if (current == null) throw StateError('Conflict entity no longer exists locally.');
    final rawData = current['data'];
    if (rawData is! Map) throw const FormatException('Local conflict record has no data.');
    return _ResolutionContext(
      remote: remote,
      current: current,
      currentData: rawData.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> _writeResolution(
    SyncConflict conflict,
    _ResolutionContext context,
    Map<String, Object?> nextData, {
    required bool deleted,
  }) async {
    final alternateHash = _remoteBranchHash(context.remote);
    await _writer.appendConflictResolution(
      entityType: context.remote.entityType,
      entityId: context.remote.entityId,
      dataPath: _store.dataPathFor(context.remote, context.current),
      currentRecord: context.current,
      resolutionOf: context.remote.opId,
      alternateBaseHash: alternateHash,
      nextData: nextData,
      patch: nextData,
      deleted: deleted,
    );
    await _documents.writeObject(conflict.path, {
      ...conflict.raw,
      'resolution': deleted ? 'acceptRemoteDelete' : 'resolvedValues',
      'resolvedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  String? _remoteBranchHash(ChangeEvent remote) {
    switch (remote.operation) {
      case ChangeOperation.create:
        return remote.value?['hash'] as String?;
      case ChangeOperation.update:
        final base = remote.baseData;
        if (base == null) return null;
        return _hashService.contentHash({...base, ...?remote.patch});
      case ChangeOperation.delete:
        return remote.baseHash;
    }
  }
}

class _ResolutionContext {
  const _ResolutionContext({required this.remote, required this.current, required this.currentData});
  final ChangeEvent remote;
  final Map<String, Object?> current;
  final Map<String, Object?> currentData;
}
