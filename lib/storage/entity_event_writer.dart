import 'change_event.dart';
import 'device_identity.dart';
import 'hash_service.dart';
import 'json_repository.dart';

class EntityEventWriter {
  EntityEventWriter({
    required JsonDocumentRepository documents,
    required DeviceIdentity deviceIdentity,
    HashService hashService = const HashService(),
  })  : _documents = documents,
        _deviceIdentity = deviceIdentity,
        _hashService = hashService;

  final JsonDocumentRepository _documents;
  final DeviceIdentity _deviceIdentity;
  final HashService _hashService;

  Future<Map<String, Object?>> appendCreate({
    required String entityType,
    required String entityId,
    required String dataPath,
    required Map<String, Object?> data,
  }) async {
    final deviceId = await _deviceIdentity.getOrCreate();
    final now = DateTime.now().toUtc();
    final hash = _hashService.contentHash(data);
    final record = <String, Object?>{
      'id': entityId,
      'version': 1,
      'data': data,
      'hash': hash,
      'createdBy': deviceId,
      'createdAt': now.toIso8601String(),
      'modifiedBy': deviceId,
      'modifiedAt': now.toIso8601String(),
      'deleted': false,
    };
    await _documents.appendJsonLine(dataPath, record);
    await _appendEvent(
      ChangeEvent(
        opId: _opId(deviceId, entityId, now),
        entityType: entityType,
        entityId: entityId,
        operation: ChangeOperation.create,
        deviceId: deviceId,
        timestamp: now,
        value: record,
      ),
      deviceId,
      now,
    );
    return record;
  }

  Future<Map<String, Object?>> appendUpdate({
    required String entityType,
    required String entityId,
    required String dataPath,
    required Map<String, Object?> currentRecord,
    required Map<String, Object?> nextData,
    required Map<String, Object?> patch,
  }) async {
    final deviceId = await _deviceIdentity.getOrCreate();
    final now = DateTime.now().toUtc();
    final currentData = _dataOf(currentRecord);
    final nextRecord = _nextRecord(currentRecord, nextData, deviceId, now, deleted: false);
    await _documents.appendJsonLine(dataPath, nextRecord);
    await _appendEvent(
      ChangeEvent(
        opId: _opId(deviceId, entityId, now),
        entityType: entityType,
        entityId: entityId,
        operation: ChangeOperation.update,
        deviceId: deviceId,
        timestamp: now,
        baseHash: currentRecord['hash'] as String?,
        baseData: currentData,
        patch: patch,
      ),
      deviceId,
      now,
    );
    return nextRecord;
  }

  Future<Map<String, Object?>> appendDelete({
    required String entityType,
    required String entityId,
    required String dataPath,
    required Map<String, Object?> currentRecord,
  }) async {
    final deviceId = await _deviceIdentity.getOrCreate();
    final now = DateTime.now().toUtc();
    final currentData = _dataOf(currentRecord);
    final nextRecord = _nextRecord(currentRecord, currentData, deviceId, now, deleted: true);
    await _documents.appendJsonLine(dataPath, nextRecord);
    await _appendEvent(
      ChangeEvent(
        opId: _opId(deviceId, entityId, now),
        entityType: entityType,
        entityId: entityId,
        operation: ChangeOperation.delete,
        deviceId: deviceId,
        timestamp: now,
        baseHash: currentRecord['hash'] as String?,
        baseData: currentData,
      ),
      deviceId,
      now,
    );
    return nextRecord;
  }

  Future<Map<String, Object?>> appendConflictResolution({
    required String entityType,
    required String entityId,
    required String dataPath,
    required Map<String, Object?> currentRecord,
    required String resolutionOf,
    required String? alternateBaseHash,
    required Map<String, Object?> nextData,
    required Map<String, Object?> patch,
    bool deleted = false,
  }) async {
    final deviceId = await _deviceIdentity.getOrCreate();
    final now = DateTime.now().toUtc();
    final currentData = _dataOf(currentRecord);
    final nextRecord = _nextRecord(currentRecord, nextData, deviceId, now, deleted: deleted);
    await _documents.appendJsonLine(dataPath, nextRecord);
    await _appendEvent(
      ChangeEvent(
        opId: _opId(deviceId, entityId, now),
        entityType: entityType,
        entityId: entityId,
        operation: deleted ? ChangeOperation.delete : ChangeOperation.update,
        deviceId: deviceId,
        timestamp: now,
        baseHash: currentRecord['hash'] as String?,
        alternateBaseHash: alternateBaseHash,
        resolutionOf: resolutionOf,
        baseData: currentData,
        patch: deleted ? null : patch,
      ),
      deviceId,
      now,
    );
    return nextRecord;
  }

  Map<String, Object?> _nextRecord(
    Map<String, Object?> currentRecord,
    Map<String, Object?> data,
    String deviceId,
    DateTime now, {
    required bool deleted,
  }) => <String, Object?>{
        ...currentRecord,
        'version': (currentRecord['version'] as int? ?? 1) + 1,
        'data': data,
        'hash': _hashService.contentHash(data),
        'modifiedBy': deviceId,
        'modifiedAt': now.toIso8601String(),
        'deleted': deleted,
      };

  Map<String, Object?> _dataOf(Map<String, Object?> record) {
    final raw = record['data'];
    if (raw is! Map) throw const FormatException('Entity record data must be an object.');
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _appendEvent(ChangeEvent event, String deviceId, DateTime now) async {
    await _documents.appendJsonLine(
      'sync/events/${safeSegment(deviceId)}/${eventFileKey(now)}.jsonl',
      event.toJson(),
    );
  }

  String eventFileKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}';

  String safeSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty) throw const FormatException('Unsafe empty storage segment.');
    return safe;
  }

  String _opId(String deviceId, String entityId, DateTime timestamp) =>
      '${timestamp.microsecondsSinceEpoch}-${safeSegment(deviceId)}-${safeSegment(entityId)}';
}
