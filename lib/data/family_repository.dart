import '../domain/models.dart';

abstract class FamilyRepository {
  Future<List<ScheduleEntry>> schedules();
  Future<List<ShoppingItem>> shopping();
  Future<List<TodoItem>> todos();
  Future<void> addShopping(ShoppingItem item);
  Future<void> setShoppingDone(String id, bool done);
  Future<void> addTodo(TodoItem item);
  Future<void> setTodoDone(String id, bool done);
}

class MemoryFamilyRepository implements FamilyRepository {
  final _schedules = <ScheduleEntry>[
    const ScheduleEntry(id: 'demo-1', childName: '小孩', weekday: 1, start: '16:30', end: '18:00', title: '英文課'),
  ];
  final _shopping = <ShoppingItem>[];
  final _todos = <TodoItem>[];

  @override Future<List<ScheduleEntry>> schedules() async => List.unmodifiable(_schedules);
  @override Future<List<ShoppingItem>> shopping() async => List.unmodifiable(_shopping);
  @override Future<List<TodoItem>> todos() async => List.unmodifiable(_todos);
  @override Future<void> addShopping(ShoppingItem item) async => _shopping.add(item);
  @override Future<void> addTodo(TodoItem item) async => _todos.add(item);

  @override
  Future<void> setShoppingDone(String id, bool done) async {
    final i = _shopping.indexWhere((x) => x.id == id);
    if (i >= 0) _shopping[i] = _shopping[i].copyWith(done: done);
  }

  @override
  Future<void> setTodoDone(String id, bool done) async {
    final i = _todos.indexWhere((x) => x.id == id);
    if (i >= 0) _todos[i] = _todos[i].copyWith(done: done);
  }
}
