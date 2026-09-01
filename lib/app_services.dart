import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'assistant/family_action_executor.dart';
import 'features/schedule/schedule_repository.dart';
import 'features/shopping/shopping_repository.dart';
import 'features/todo/todo_repository.dart';
import 'shopping/http_offer_provider.dart';
import 'shopping/merchant_offer_provider.dart';
import 'shopping/pchome_web_offer_provider.dart';
import 'shopping/shopping_comparison_service.dart';
import 'storage/device_identity.dart';
import 'storage/entity_event_writer.dart';
import 'storage/json_repository.dart';
import 'sync/android_saf_sync_transport.dart';
import 'sync/conflict_inbox.dart';
import 'sync/household_sync_service.dart';

class AppServices {
  AppServices._({
    required this.documents,
    required this.deviceIdentity,
    required this.schedules,
    required this.shopping,
    required this.todos,
    required this.actions,
    required this.syncTransport,
    required this.sync,
    required this.conflicts,
    required this.shoppingComparison,
  });

  final JsonDocumentRepository documents;
  final DeviceIdentity deviceIdentity;
  final ScheduleRepository schedules;
  final ShoppingRepository shopping;
  final TodoRepository todos;
  final FamilyActionExecutor actions;
  final AndroidSafSyncTransport syncTransport;
  final HouseholdSyncService sync;
  final SyncConflictInbox conflicts;
  final ShoppingComparisonService shoppingComparison;

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
    final syncTransport = AndroidSafSyncTransport();
    final sync = HouseholdSyncService(
      documents: documents,
      deviceIdentity: deviceIdentity,
      transport: syncTransport,
    );
    final conflicts = SyncConflictInbox(documents: documents, writer: writer);

    // Built-in public-web provider: ordinary users do not need to configure or
    // maintain prices manually. Additional normalized providers may still be
    // supplied through HOUSEHOLDER_OFFER_ENDPOINT when desired.
    const endpointText = String.fromEnvironment('HOUSEHOLDER_OFFER_ENDPOINT');
    final providers = <MerchantOfferProvider>[
      PchomeWebOfferProvider(),
    ];
    if (endpointText.trim().isNotEmpty) {
      final endpoint = Uri.tryParse(endpointText);
      if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
        throw const FormatException('HOUSEHOLDER_OFFER_ENDPOINT is not a valid URI.');
      }
      providers.add(HttpMerchantOfferProvider(endpoint: endpoint));
    }
    final shoppingComparison = ShoppingComparisonService(providers: providers);

    return AppServices._(
      documents: documents,
      deviceIdentity: deviceIdentity,
      schedules: schedules,
      shopping: shopping,
      todos: todos,
      actions: actions,
      syncTransport: syncTransport,
      sync: sync,
      conflicts: conflicts,
      shoppingComparison: shoppingComparison,
    );
  }
}
