import '../features/schedule/schedule_import_models.dart';
import '../features/schedule/schedule_repository.dart';
import '../features/shopping/shopping_item.dart';
import '../features/shopping/shopping_repository.dart';
import '../features/todo/todo_item.dart';
import '../features/todo/todo_repository.dart';
import 'family_action.dart';

class ActionExecutionResult {
  const ActionExecutionResult({
    required this.message,
    this.scheduleDraft,
    this.requiresUserConfirmation = false,
  });

  final String message;
  final ScheduleImportDraft? scheduleDraft;
  final bool requiresUserConfirmation;
}

class FamilyActionExecutor {
  const FamilyActionExecutor({
    required ScheduleRepository schedules,
    required ShoppingRepository shopping,
    required TodoRepository todos,
  })  : _schedules = schedules,
        _shopping = shopping,
        _todos = todos;

  final ScheduleRepository _schedules;
  final ShoppingRepository _shopping;
  final TodoRepository _todos;

  Future<ActionExecutionResult> execute(FamilyAction action) async {
    return switch (action.type) {
      'schedule.import' => _scheduleImport(action),
      'schedule.query' => _scheduleQuery(action),
      'shopping.add' => _shoppingAdd(action),
      'shopping.list' => _shoppingList(action),
      'shopping.setDone' => _shoppingSetDone(action),
      'todo.add' => _todoAdd(action),
      'todo.list' => _todoList(action),
      'todo.setDone' => _todoSetDone(action),
      'unsupported' => _unsupported(action),
      _ => throw FormatException('Unsupported FamilyAction type: ${action.type}'),
    };
  }

  Future<ActionExecutionResult> _unsupported(FamilyAction action) async {
    final reason = action.payload['reason'];
    return ActionExecutionResult(
      message: reason is String && reason.trim().isNotEmpty
          ? '目前 MVP 不支援：${reason.trim()}'
          : '目前 MVP 不支援這個操作。',
    );
  }

  Future<ActionExecutionResult> _scheduleImport(FamilyAction action) async {
    if (!action.requiresConfirmation) {
      throw const FormatException('schedule.import must require confirmation.');
    }
    final draft = ScheduleImportDraft.fromPayload(action.payload);
    return ActionExecutionResult(
      message: '課表草稿已驗證，等待確認。',
      scheduleDraft: draft,
      requiresUserConfirmation: true,
    );
  }

  Future<ActionExecutionResult> _scheduleQuery(FamilyAction action) async {
    final dateText = _requiredString(action.payload, 'date');
    final date = DateTime.tryParse(dateText);
    if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText)) {
      throw const FormatException('schedule.query date must be YYYY-MM-DD.');
    }
    final childId = action.payload['childId'] as String?;
    final items = await _schedules.forDate(date, childId: childId);
    if (items.isEmpty) {
      return ActionExecutionResult(message: '$dateText 查不到符合的課程。');
    }

    final lines = items.map((item) {
      final when = item.period != null
          ? '第 ${item.period} 節'
          : [item.startTime, item.endTime].whereType<String>().join('-');
      final prefix = when.isEmpty ? '' : '$when ';
      final location = item.location == null ? '' : '（${item.location}）';
      return '$prefix${item.subject}$location';
    }).join('\n');
    return ActionExecutionResult(message: '$dateText 的課程：\n$lines');
  }

  Future<ActionExecutionResult> _shoppingAdd(FamilyAction action) async {
    final rawItems = action.payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('shopping.add payload.items is required.');
    }
    var count = 0;
    for (final raw in rawItems) {
      if (raw is! Map) throw const FormatException('shopping.add items must be objects.');
      final item = HouseholdShoppingItem.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      await _shopping.add(item);
      count++;
    }
    return ActionExecutionResult(message: '已加入 $count 筆購物項目。');
  }

  Future<ActionExecutionResult> _shoppingList(FamilyAction action) async {
    final includeDone = action.payload['includeDone'] as bool? ?? false;
    final items = await _shopping.list(includeDone: includeDone);
    if (items.isEmpty) return const ActionExecutionResult(message: '目前沒有購物項目。');
    final lines = items.map((item) {
      final mark = item.done ? '✓' : '•';
      return '$mark ${item.name} x${item.quantity}${item.unit}';
    }).join('\n');
    return ActionExecutionResult(message: '購物清單：\n$lines');
  }

  Future<ActionExecutionResult> _shoppingSetDone(FamilyAction action) async {
    final id = _requiredString(action.payload, 'id');
    final done = _requiredBool(action.payload, 'done');
    await _shopping.setDone(id, done);
    return ActionExecutionResult(message: done ? '購物項目已完成。' : '購物項目已重新開啟。');
  }

  Future<ActionExecutionResult> _todoAdd(FamilyAction action) async {
    final rawItems = action.payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('todo.add payload.items is required.');
    }
    var count = 0;
    for (final raw in rawItems) {
      if (raw is! Map) throw const FormatException('todo.add items must be objects.');
      final item = HouseholdTodoItem.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      await _todos.add(item);
      count++;
    }
    return ActionExecutionResult(message: '已加入 $count 筆待辦。');
  }

  Future<ActionExecutionResult> _todoList(FamilyAction action) async {
    final includeDone = action.payload['includeDone'] as bool? ?? false;
    final items = await _todos.list(includeDone: includeDone);
    if (items.isEmpty) return const ActionExecutionResult(message: '目前沒有待辦。');
    final lines = items.map((item) {
      final mark = item.done ? '✓' : '•';
      final due = item.dueDate == null ? '' : ' ${item.dueDate}';
      return '$mark ${item.title}$due';
    }).join('\n');
    return ActionExecutionResult(message: '待辦清單：\n$lines');
  }

  Future<ActionExecutionResult> _todoSetDone(FamilyAction action) async {
    final id = _requiredString(action.payload, 'id');
    final done = _requiredBool(action.payload, 'done');
    await _todos.setDone(id, done);
    return ActionExecutionResult(message: done ? '待辦已完成。' : '待辦已重新開啟。');
  }

  String _requiredString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key is required.');
    }
    return value.trim();
  }

  bool _requiredBool(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! bool) throw FormatException('$key must be boolean.');
    return value;
  }
}
