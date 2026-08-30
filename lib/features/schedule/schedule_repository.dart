import '../../storage/change_event.dart';
import '../../storage/device_identity.dart';
import '../../storage/hash_service.dart';
import '../../storage/json_repository.dart';
import 'schedule_import_models.dart';

class ScheduleRepository {
  ScheduleRepository({
    required JsonDocumentRepository documents,
    required DeviceIdentity deviceIdentity,
    HashService hashService = const HashService(),
  })  : _documents = documents,
        _deviceIdentity = deviceIdentity,
        _hashService = hashService;

  final JsonDocumentRepository _documents;
  final DeviceIdentity _deviceIdentity;
  final HashService _hashService;

  Future<void> importConfirmed(ScheduleImportDraft draft) async {
    final deviceId = await _deviceIdentity.getOrCreate();
    final now = DateTime.now().toUtc();

    for (final item in draft.items) {
      final data = item.toJson();
      final hash = _hashService.contentHash(data);
      final record = <String, Object?>{
        'id': item.id,
        'version': 1,
        'data': data,
        'hash': hash,
        'createdBy': deviceId,
        'createdAt': now.toIso8601String(),
        'modifiedBy': deviceId,
        'modifiedAt': now.toIso8601String(),
        'deleted': false,
      };

      final semesterKey = _semesterKey(item.validFrom);
      final childPath = _safeSegment(item.childId);
      await _documents.appendJsonLine(
        'family/children/$childPath/schedule/$semesterKey.jsonl',
        record,
      );

      final event = ChangeEvent(
        opId: _opId(deviceId, item.id, now),
        entityType: 'scheduleItem',
        entityId: item.id,
        operation: ChangeOperation.create,
        deviceId: deviceId,
        timestamp: now,
        value: record,
      );
      await _documents.appendJsonLine(
        'sync/events/${_safeSegment(deviceId)}/${_eventFileKey(now)}.jsonl',
        event.toJson(),
      );
    }
  }

  String _semesterKey(String validFrom) => validFrom.substring(0, 7);

  String _eventFileKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}';

  String _opId(String deviceId, String entityId, DateTime timestamp) =>
      '${timestamp.microsecondsSinceEpoch}-${_safeSegment(deviceId)}-${_safeSegment(entityId)}';

  String _safeSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty) throw const FormatException('Unsafe empty storage segment.');
    return safe;
  }
}
