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
  late FamilyActionExecutor executor;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('householder-chat-test-');
    final documents = JsonDocumentRepository(temp);
    final writer = EntityEventWriter(
      documents: documents,
      deviceIdentity: DeviceIdentity(documents),
    );
    schedules = ScheduleRepository(documents: documents, writer: writer);
    executor = FamilyActionExecutor(
      schedules: schedules,
      shopping: ShoppingRepository(documents: documents, writer: writer),
      todos: TodoRepository(documents: documents, writer: writer),
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
}
