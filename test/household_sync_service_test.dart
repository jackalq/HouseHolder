import 'dart:io';

import 'package:family_butler/storage/device_identity.dart';
import 'package:family_butler/storage/entity_event_writer.dart';
import 'package:family_butler/storage/json_repository.dart';
import 'package:family_butler/sync/household_sync_service.dart';
import 'package:family_butler/sync/sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySyncTransport implements SyncTransport {
  final Map<String, String> files = {};

  @override
  Future<List<SyncObject>> list(String prefix) async => files.keys
      .where((path) => path.startsWith(prefix))
      .map((path) => SyncObject(path: path))
      .toList(growable: false);

  @override
  Future<String> readText(SyncObject object) async => files[object.path]!;

  @override
  Future<void> writeText(String path, String content) async {
    files[path] = content;
  }
}

void main() {
  test('two devices exchange append-only shopping events through transport', () async {
    final transport = MemorySyncTransport();
    final aDir = await Directory.systemTemp.createTemp('hh-sync-a-');
    final bDir = await Directory.systemTemp.createTemp('hh-sync-b-');
    addTearDown(() async {
      await aDir.delete(recursive: true);
      await bDir.delete(recursive: true);
    });

    final aDocs = JsonDocumentRepository(aDir);
    final bDocs = JsonDocumentRepository(bDir);
    await aDocs.writeObject('sync/device.json', {'deviceId': 'device-a'});
    await bDocs.writeObject('sync/device.json', {'deviceId': 'device-b'});
    final aIdentity = DeviceIdentity(aDocs);
    final bIdentity = DeviceIdentity(bDocs);
    final writer = EntityEventWriter(documents: aDocs, deviceIdentity: aIdentity);
    await writer.appendCreate(
      entityType: 'shoppingItem',
      entityId: 'milk-1',
      dataPath: 'shopping/items.jsonl',
      data: {'id': 'milk-1', 'name': '牛奶', 'quantity': 1, 'unit': '瓶', 'done': false},
    );

    final aSync = HouseholdSyncService(
      documents: aDocs,
      deviceIdentity: aIdentity,
      transport: transport,
    );
    final bSync = HouseholdSyncService(
      documents: bDocs,
      deviceIdentity: bIdentity,
      transport: transport,
    );

    await aSync.sync();
    final report = await bSync.sync();
    expect(report.appliedEvents, 1);
    final records = await bDocs.readJsonLines('shopping/items.jsonl');
    expect(records.single['id'], 'milk-1');

    final second = await bSync.sync();
    expect(second.remoteEvents, 0);
  });
}
