class ScheduleEntry {
  final String id;
  final String childName;
  final int weekday;
  final String start;
  final String end;
  final String title;

  const ScheduleEntry({required this.id, required this.childName, required this.weekday, required this.start, required this.end, required this.title});
}

class ShoppingItem {
  final String id;
  final String name;
  final int quantity;
  final String unit;
  final bool done;

  const ShoppingItem({required this.id, required this.name, this.quantity = 1, this.unit = '個', this.done = false});

  ShoppingItem copyWith({bool? done}) => ShoppingItem(id: id, name: name, quantity: quantity, unit: unit, done: done ?? this.done);
}

class TodoItem {
  final String id;
  final String title;
  final bool done;

  const TodoItem({required this.id, required this.title, this.done = false});
  TodoItem copyWith({bool? done}) => TodoItem(id: id, title: title, done: done ?? this.done);
}
