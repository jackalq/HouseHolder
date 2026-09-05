import 'dart:io';

import '../../storage/entity_event_writer.dart';
import '../../storage/json_repository.dart';
import 'schedule_import_models.dart';

class ScheduleRepository {
  ScheduleRepository({
    required JsonDocumentRepository documents,
    required EntityEventWriter writer,
  })  : _documents = documents,
        _writer = writer;

  final JsonDocumentRepository _documents;
  final EntityEventWriter _writer;

  Future<void> importConfirmed(ScheduleImportDraft draft) async {
    for (final item in draft.items) {
      final semesterKey = _semesterKey(item.validFrom);
      final childPath = _writer.safeSegment(item.childId);
      await _writer.appendCreate(
        entityType: 'scheduleItem',
        entityId: item.id,
        dataPath: 'family/children/$childPath/schedule/$semesterKey.jsonl',
        data: item.toJson(),
      );
    }
  }

  Future<List<ScheduleImportItem>> forDate(
    DateTime date, {
    String? childId,
  }) async {
    final items = await _allLatest(childId: childId);
    final matches = items.where((item) => item.appliesTo(date)).toList();
    matches.sort((a, b) {
      final periodCompare = (a.period ?? 999).compareTo(b.period ?? 999);
      if (periodCompare != 0) return periodCompare;
      return (a.startTime ?? '99:99').compareTo(b.startTime ?? '99:99');
    });
    return matches;
  }

  Future<List<ScheduleImportItem>> _allLatest({String? childId}) async {
    final root = Directory('${_documents.rootDirectory.path}/family/children');
    if (!await root.exists()) return const [];

    final latest = <String, Map<String, Object?>>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      if (!entity.path.contains('${Platform.pathSeparator}schedule${Platform.pathSeparator}')) {
        continue;
      }
      final relative = entity.path
          .substring(_documents.rootDirectory.path.length + 1)
          .replaceAll('\\', '/');
      final rows = await _documents.readJsonLines(relative);
      for (final row in rows) {
        final id = row['id'];
        if (id is! String || id.isEmpty) continue;
        final existing = latest[id];
        if (existing == null || _version(row) >= _version(existing)) {
          latest[id] = row;
        }
      }
    }

    final result = <ScheduleImportItem>[];
    for (final row in latest.values) {
      if (row['deleted'] == true) continue;
      final data = row['data'];
      if (data is! Map) continue;
      final item = ScheduleImportItem.fromJson(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (childId == null || childId.isEmpty || item.childId == childId) {
        result.add(item);
      }
    }
    return result;
  }

  int _version(Map<String, Object?> row) => row['version'] as int? ?? 0;

  String _semesterKey(String validFrom) => validFrom.substring(0, 7);
}
