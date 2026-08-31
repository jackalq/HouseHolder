import 'dart:io';

import 'package:family_butler/features/todo/todo_page.dart';
import 'package:family_butler/features/todo/todo_repository.dart';
import 'package:family_butler/storage/device_identity.dart';
import 'package:family_butler/storage/entity_event_writer.dart';
import 'package:family_butler/storage/json_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('todo page adds and completes a persisted todo', (tester) async {
    final temp = await Directory.systemTemp.createTemp('householder-todo-page-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final documents = JsonDocumentRepository(temp);
    final identity = DeviceIdentity(documents);
    final writer = EntityEventWriter(documents: documents, deviceIdentity: identity);
    final repository = TodoRepository(documents: documents, writer: writer);

    await tester.pumpWidget(MaterialApp(home: TodoPage(repository: repository)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('todo-add-input')), '繳學費');
    await tester.tap(find.byKey(const ValueKey('todo-add-button')));
    await tester.pumpAndSettle();

    expect(find.text('繳學費'), findsOneWidget);
    var items = await repository.list(includeDone: true);
    expect(items.single.done, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    items = await repository.list(includeDone: true);
    expect(items.single.done, isTrue);
  });
}
