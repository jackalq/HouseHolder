class HouseholdTodoItem {
  const HouseholdTodoItem({
    required this.id,
    required this.title,
    this.done = false,
    this.dueDate,
    this.note,
  });

  final String id;
  final String title;
  final bool done;
  final String? dueDate;
  final String? note;

  factory HouseholdTodoItem.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final done = json['done'] ?? false;
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('todo id is required.');
    }
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('todo title is required.');
    }
    if (done is! bool) {
      throw const FormatException('todo done must be boolean.');
    }
    final dueDate = json['dueDate'] as String?;
    if (dueDate != null && !_isIsoDate(dueDate)) {
      throw const FormatException('todo dueDate must be YYYY-MM-DD.');
    }
    return HouseholdTodoItem(
      id: id.trim(),
      title: title.trim(),
      done: done,
      dueDate: dueDate,
      note: json['note'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        if (dueDate != null) 'dueDate': dueDate,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };

  HouseholdTodoItem copyWith({bool? done}) => HouseholdTodoItem(
        id: id,
        title: title,
        done: done ?? this.done,
        dueDate: dueDate,
        note: note,
      );

  static bool _isIsoDate(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      DateTime.tryParse(value) != null;
}
