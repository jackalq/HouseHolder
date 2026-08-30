import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:family_butler/assistant/family_action.dart';
import 'package:family_butler/assistant/family_action_executor.dart';
import 'package:family_butler/features/schedule/schedule_import_models.dart';
import 'package:family_butler/features/schedule/schedule_repository.dart';
import 'package:family_butler/features/shopping/shopping_repository.dart';
import 'package:family_butler/features/todo/todo_repository.dart';
import 'package:family_butler/storage/device_identity.dart';
import 'package:family_butler/storage/entity_event_writer.dart';
import 'package:family_butler/storage/json_repository.dart';

void main() {
  late Directory temp;
  late JsonDocumentRepository documents;
  late ScheduleRepository schedules;
  late ShoppingRepository shopping;
  late TodoRepository todos;
  late FamilyActionExecutor executor;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('householder-test-');
    documents = JsonDocumentRepository(temp);
    final identity = DeviceIdentity(documents);
    final writer = EntityEventWriter(
      documents: documents,
      deviceIdentity: identity,
    );
    schedules = ScheduleRepository(documents: documents, writer: writer);
    shopping = ShoppingRepository(documents: documents, writer: writer);
    todos = TodoRepository(documents: documents, writer: writer);
    executor = FamilyActionExecutor(
      schedules: schedules,
      shopping: shopping,
      todos: todos,
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('schedule query is grounded in persisted schedule records', () async {
    await schedules.importConfirmed(
      const ScheduleImportDraft(
        items: [
          ScheduleImportItem(
            id: 'math-mon',
            childId: 'child-1',
            dayOfWeek: DateTime.monday,
            subject: '數學',
            period: 2,
            validFrom: '2026-08-01',
            validUntil: '2026-12-31',
          ),
        ],
      ),
    );

    final result = await executor.execute(
      const FamilyAction(
        type: 'schedule.query',
        requiresConfirmation: false,
        payload: {'date': '2026-08-31', 'childId': 'child-1'},
      ),
    );

    expect(result.message, contains('數學'));
    expect(result.message, contains('第 2 節'));
  });

  test('shopping add/list/update persists through append-only records', () async {
    await executor.execute(
      const FamilyAction(
        type: 'shopping.add',
        requiresConfirmation: false,
        payload: {
          'items': [
            {'id': 'milk-1', 'name': '牛奶', 'quantity': 2, 'unit': '瓶', 'done': false}
          ]
        },
      ),
    );

    var result = await executor.execute(
      const FamilyAction(
        type: 'shopping.list',
        requiresConfirmation: false,
        payload: {'includeDone': false},
      ),
    );
    expect(result.message, contains('牛奶'));

    await executor.execute(
      const FamilyAction(
        type: 'shopping.setDone',
        requiresConfirmation: false,
        payload: {'id': 'milk-1', 'done': true},
      ),
    );
    result = await executor.execute(
      const FamilyAction(
        type: 'shopping.list',
        requiresConfirmation: false,
        payload: {'includeDone': false},
      ),
    );
    expect(result.message, contains('目前沒有購物項目'));
  });

  test('todo add/list persists due date', () async {
    await executor.execute(
      const FamilyAction(
        type: 'todo.add',
        requiresConfirmation: false,
        payload: {
          'items': [
            {
              'id': 'fee-1',
              'title': '繳學費',
              'done': false,
              'dueDate': '2026-09-04'
            }
          ]
        },
      ),
    );

    final result = await executor.execute(
      const FamilyAction(
        type: 'todo.list',
        requiresConfirmation: false,
        payload: {'includeDone': false},
      ),
    );
    expect(result.message, contains('繳學費'));
    expect(result.message, contains('2026-09-04'));
  });

  test('schedule import cannot bypass confirmation flag', () async {
    expect(
      () => executor.execute(
        const FamilyAction(
          type: 'schedule.import',
          requiresConfirmation: false,
          payload: {
            'items': [
              {
                'id': 'x',
                'childId': 'child-1',
                'dayOfWeek': 1,
                'subject': '國文',
                'validFrom': '2026-08-01'
              }
            ]
          },
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
