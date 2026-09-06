import '../../storage/entity_event_writer.dart';
import '../../storage/json_repository.dart';
import 'todo_item.dart';

class TodoRepository {
  TodoRepository({
    required JsonDocumentRepository documents,
    required EntityEventWriter writer,
  })  : _documents = documents,
        _writer = writer;

  final JsonDocumentRepository _documents;
  final EntityEventWriter _writer;

  static const _path = 'todos/items.jsonl';

  Future<List<HouseholdTodoItem>> list({bool includeDone = true}) async {
    final latest = await _latestRecords();
    final items = <HouseholdTodoItem>[];
    for (final record in latest.values) {
      if (record['deleted'] == true) continue;
      final data = record['data'];
      if (data is! Map) continue;
      final item = HouseholdTodoItem.fromJson(
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (includeDone || !item.done) items.add(item);
    }
    items.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final aDue = a.dueDate ?? '9999-99-99';
      final bDue = b.dueDate ?? '9999-99-99';
      final dueCompare = aDue.compareTo(bDue);
      return dueCompare != 0 ? dueCompare : a.title.compareTo(b.title);
    });
    return items;
  }

  Future<void> add(HouseholdTodoItem item) async {
    final latest = await _latestRecords();
    if (latest.containsKey(item.id)) {
      throw StateError('Todo id already exists: ${item.id}');
    }
    await _writer.appendCreate(
      entityType: 'todoItem',
      entityId: item.id,
      dataPath: _path,
      data: item.toJson(),
    );
  }

  Future<void> setDone(String id, bool done) async {
    final latest = await _latestRecords();
    final current = latest[id];
    if (current == null || current['deleted'] == true) {
      throw StateError('Todo not found: $id');
    }
    final rawData = current['data'];
    if (rawData is! Map) throw StateError('Todo data is invalid: $id');
    final item = HouseholdTodoItem.fromJson(
      rawData.map((key, value) => MapEntry(key.toString(), value)),
    );
    final next = item.copyWith(done: done);
    await _writer.appendUpdate(
      entityType: 'todoItem',
      entityId: id,
      dataPath: _path,
      currentRecord: current,
      nextData: next.toJson(),
      patch: {'done': done},
    );
  }

  Future<Map<String, Map<String, Object?>>> _latestRecords() async {
    final rows = await _documents.readJsonLines(_path);
    final latest = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final id = row['id'];
      if (id is! String || id.isEmpty) continue;
      final existing = latest[id];
      if (existing == null || _version(row) >= _version(existing)) {
        latest[id] = row;
      }
    }
    return latest;
  }

  int _version(Map<String, Object?> row) => row['version'] as int? ?? 0;
}
