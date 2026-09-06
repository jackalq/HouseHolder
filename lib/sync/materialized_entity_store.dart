import '../storage/change_event.dart';
import '../storage/json_repository.dart';

class MaterializedEntityStore {
  const MaterializedEntityStore(this._documents);

  final JsonDocumentRepository _documents;

  Future<Map<String, Object?>?> latestFor(ChangeEvent event) async {
    final paths = switch (event.entityType) {
      'shoppingItem' => const ['shopping/items.jsonl'],
      'todoItem' => const ['todos/items.jsonl'],
      'scheduleItem' => await _schedulePaths(),
      _ => throw FormatException('Unsupported sync entity type: ${event.entityType}'),
    };
    Map<String, Object?>? latest;
    for (final path in paths) {
      for (final record in await _documents.readJsonLines(path)) {
        if (record['id'] == event.entityId) latest = record;
      }
    }
    return latest;
  }

  Future<void> append(ChangeEvent event, Map<String, Object?> record) async {
    await _documents.appendJsonLine(dataPathFor(event, record), record);
  }

  String dataPathFor(ChangeEvent event, Map<String, Object?> record) => switch (event.entityType) {
        'shoppingItem' => 'shopping/items.jsonl',
        'todoItem' => 'todos/items.jsonl',
        'scheduleItem' => _schedulePath(record),
        _ => throw FormatException('Unsupported sync entity type: ${event.entityType}'),
      };

  Future<List<String>> _schedulePaths() async {
    final files = await _documents.listFiles('family/children');
    return files.where((path) => path.contains('/schedule/') && path.endsWith('.jsonl')).toList();
  }

  String _schedulePath(Map<String, Object?> record) {
    final raw = record['data'];
    if (raw is! Map) throw const FormatException('Schedule record data is missing.');
    final data = raw.map((key, value) => MapEntry(key.toString(), value));
    final childId = data['childId'];
    final validFrom = data['validFrom'];
    if (childId is! String || childId.isEmpty || validFrom is! String || validFrom.length < 7) {
      throw const FormatException('Schedule record requires childId and validFrom.');
    }
    return 'family/children/${_safe(childId)}/schedule/${validFrom.substring(0, 7)}.jsonl';
  }

  String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty) throw const FormatException('Unsafe empty storage segment.');
    return safe;
  }
}
