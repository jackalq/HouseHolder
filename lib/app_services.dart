import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'assistant/family_action_executor.dart';
import 'features/schedule/schedule_repository.dart';
import 'features/shopping/shopping_repository.dart';
import 'features/todo/todo_repository.dart';
import 'storage/device_identity.dart';
import 'storage/entity_event_writer.dart';
import 'storage/json_repository.dart';

class AppServices {
  AppServices._({
    required this.documents,
    required this.deviceIdentity,
    required this.schedules,
    required this.shopping,
    required this.todos,
    required this.actions,
  });

  final JsonDocumentRepository documents;
  final DeviceIdentity deviceIdentity;
  final ScheduleRepository schedules;
  final ShoppingRepository shopping;
  final TodoRepository todos;
  final FamilyActionExecutor actions;

  static Future<AppServices> bootstrap() async {
    final appDocuments = await getApplicationDocumentsDirectory();
    final documents = JsonDocumentRepository(
      Directory('${appDocuments.path}/HouseHolder'),
    );
    final deviceIdentity = DeviceIdentity(documents);
    await deviceIdentity.getOrCreate();
    final writer = EntityEventWriter(
      documents: documents,
      deviceIdentity: deviceIdentity,
    );
    final schedules = ScheduleRepository(documents: documents, writer: writer);
    final shopping = ShoppingRepository(documents: documents, writer: writer);
    final todos = TodoRepository(documents: documents, writer: writer);
    final actions = FamilyActionExecutor(
      schedules: schedules,
      shopping: shopping,
      todos: todos,
    );
    return AppServices._(
      documents: documents,
      deviceIdentity: deviceIdentity,
      schedules: schedules,
      shopping: shopping,
      todos: todos,
      actions: actions,
    );
  }
}
