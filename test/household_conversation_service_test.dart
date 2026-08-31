import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:family_butler/assistant/assistant_orchestrator.dart';
import 'package:family_butler/assistant/family_action_executor.dart';
import 'package:family_butler/assistant/household_conversation_service.dart';
import 'package:family_butler/features/schedule/schedule_import_models.dart';
import 'package:family_butler/features/schedule/schedule_repository.dart';
import 'package:family_butler/features/shopping/shopping_repository.dart';
import 'package:family_butler/features/todo/todo_repository.dart';
import 'package:family_butler/storage/device_identity.dart';
import 'package:family_butler/storage/entity_event_writer.dart';
import 'package:family_butler/storage/json_repository.dart';

void main() {
  late Directory temp;
  late ScheduleRepository schedules;
  late ShoppingRepository shopping;
  late TodoRepository todos;
  late FamilyActionExecutor executor;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('householder-chat-test-');
    final documents = JsonDocumentRepository(temp);
    final writer = EntityEventWriter(
      documents: documents,
      deviceIdentity: DeviceIdentity(documents),
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

  test('chat query uses LLM action but answers from persisted timetable', () async {
    await schedules.importConfirmed(
      const ScheduleImportDraft(
        items: [
          ScheduleImportItem(
            id: 'math-mon',
            childId: '小明',
            dayOfWeek: DateTime.monday,
            subject: '數學',
            period: 2,
            location: '302',
            validFrom: '2026-08-01',
            validUntil: '2026-12-31',
          ),
        ],
      ),
    );

    final service = HouseholdConversationService(
      propose: (_) async => const FamilyActionDraft(
        rawJson: '{"type":"schedule.query","requiresConfirmation":false,"payload":{"date":"2026-08-31","childId":"小明"}}',
      ),
      executor: executor,
    );

    final result = await service.sendText('小明今天有什麼課？');

    expect(result.userMessage.text, '小明今天有什麼課？');
    expect(result.assistantMessage.text, contains('數學'));
    expect(result.assistantMessage.text, contains('第 2 節'));
    expect(result.assistantMessage.text, contains('302'));
    expect(result.scheduleDraft, isNull);
  });

  test('schedule import becomes a confirmation draft instead of writing immediately', () async {
    final service = HouseholdConversationService(
      propose: (_) async => const FamilyActionDraft(
        rawJson: '{"type":"schedule.import","requiresConfirmation":true,"payload":{"items":[{"id":"model-id","childId":"小明","dayOfWeek":1,"subject":"國文","period":1,"validFrom":"2026-09-01","validUntil":"2027-01-20"}],"warnings":[]}}',
      ),
      executor: executor,
    );

    final result = await service.sendText('匯入課表');

    expect(result.scheduleDraft, isNotNull);
    expect(result.assistantMessage.text, contains('請確認'));
    expect(await schedules.forDate(DateTime(2026, 9, 7)), isEmpty);
  });

  test('shopping chat writes to repository then grounds list response', () async {
    var turn = 0;
    final service = HouseholdConversationService(
      propose: (_) async {
        turn++;
        if (turn == 1) {
          return const FamilyActionDraft(
            rawJson: '{"type":"shopping.add","requiresConfirmation":false,"payload":{"items":[{"name":"牛奶","quantity":2,"unit":"瓶","done":false}]}}',
          );
        }
        return const FamilyActionDraft(
          rawJson: '{"type":"shopping.list","requiresConfirmation":false,"payload":{"includeDone":false}}',
        );
      },
      executor: executor,
    );

    final added = await service.sendText('把兩瓶牛奶加入採購清單');
    final listed = await service.sendText('我的採購清單有什麼？');

    expect(added.assistantMessage.text, contains('已加入 1 筆'));
    expect(listed.assistantMessage.text, contains('牛奶'));
    expect(listed.assistantMessage.text, contains('x2瓶'));
    final persisted = await shopping.list(includeDone: false);
    expect(persisted.single.name, '牛奶');
    expect(persisted.single.quantity, 2);
  });

  test('todo chat writes to repository then grounds list response', () async {
    var turn = 0;
    final service = HouseholdConversationService(
      propose: (_) async {
        turn++;
        if (turn == 1) {
          return const FamilyActionDraft(
            rawJson: '{"type":"todo.add","requiresConfirmation":false,"payload":{"items":[{"title":"繳學費","done":false,"dueDate":"2026-09-04"}]}}',
          );
        }
        return const FamilyActionDraft(
          rawJson: '{"type":"todo.list","requiresConfirmation":false,"payload":{"includeDone":false}}',
        );
      },
      executor: executor,
    );

    final added = await service.sendText('新增待辦：9月4日前繳學費');
    final listed = await service.sendText('列出待辦');

    expect(added.assistantMessage.text, contains('已加入 1 筆待辦'));
    expect(listed.assistantMessage.text, contains('繳學費'));
    expect(listed.assistantMessage.text, contains('2026-09-04'));
    final persisted = await todos.list(includeDone: false);
    expect(persisted.single.title, '繳學費');
  });
}
