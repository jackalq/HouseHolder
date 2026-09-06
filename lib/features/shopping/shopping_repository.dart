import '../../shopping/product_preference.dart';
import '../../storage/entity_event_writer.dart';
import '../../storage/json_repository.dart';
import 'shopping_item.dart';

class ShoppingRepository {
  ShoppingRepository({
    required JsonDocumentRepository documents,
    required EntityEventWriter writer,
  })  : _documents = documents,
        _writer = writer;

  final JsonDocumentRepository _documents;
  final EntityEventWriter _writer;

  static const _path = 'shopping/items.jsonl';

  Future<List<HouseholdShoppingItem>> list({bool includeDone = true}) async {
    final latest = await _latestRecords();
    final items = <HouseholdShoppingItem>[];
    for (final record in latest.values) {
      if (record['deleted'] == true) continue;
      final data = record['data'];
      if (data is! Map) continue;
      final item = HouseholdShoppingItem.fromJson(data.map((key, value) => MapEntry(key.toString(), value)));
      if (includeDone || !item.done) items.add(item);
    }
    items.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      return a.name.compareTo(b.name);
    });
    return items;
  }

  Future<void> add(HouseholdShoppingItem item) async {
    final latest = await _latestRecords();
    if (latest.containsKey(item.id)) throw StateError('Shopping item id already exists: ${item.id}');
    await _writer.appendCreate(entityType: 'shoppingItem', entityId: item.id, dataPath: _path, data: item.toJson());
  }

  Future<void> setDone(String id, bool done) async {
    await _update(id, (item) => item.copyWith(done: done), {'done': done});
  }

  Future<void> setPreference(String id, ProductPreference preference) async {
    await _update(id, (item) => item.copyWith(preference: preference), {'preference': preference.toJson()});
  }

  Future<void> _update(
    String id,
    HouseholdShoppingItem Function(HouseholdShoppingItem item) change,
    Map<String, Object?> patch,
  ) async {
    final latest = await _latestRecords();
    final current = latest[id];
    if (current == null || current['deleted'] == true) throw StateError('Shopping item not found: $id');
    final rawData = current['data'];
    if (rawData is! Map) throw StateError('Shopping item data is invalid: $id');
    final item = HouseholdShoppingItem.fromJson(rawData.map((key, value) => MapEntry(key.toString(), value)));
    final next = change(item);
    await _writer.appendUpdate(
      entityType: 'shoppingItem',
      entityId: id,
      dataPath: _path,
      currentRecord: current,
      nextData: next.toJson(),
      patch: patch,
    );
  }

  Future<Map<String, Map<String, Object?>>> _latestRecords() async {
    final rows = await _documents.readJsonLines(_path);
    final latest = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final id = row['id'];
      if (id is! String || id.isEmpty) continue;
      final existing = latest[id];
      if (existing == null || _version(row) >= _version(existing)) latest[id] = row;
    }
    return latest;
  }

  int _version(Map<String, Object?> row) => row['version'] as int? ?? 0;
}
