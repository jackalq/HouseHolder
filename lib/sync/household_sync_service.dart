import 'dart:convert';

import '../storage/change_event.dart';
import '../storage/device_identity.dart';
import '../storage/json_repository.dart';
import 'materialized_entity_store.dart';
import 'merge_engine.dart';
import 'sync_transport.dart';

class SyncReport {
  const SyncReport({
    required this.pushedFiles,
    required this.remoteEvents,
    required this.appliedEvents,
    required this.conflicts,
  });

  final int pushedFiles;
  final int remoteEvents;
  final int appliedEvents;
  final int conflicts;
}

class HouseholdSyncService {
  HouseholdSyncService({
    required JsonDocumentRepository documents,
    required DeviceIdentity deviceIdentity,
    required SyncTransport transport,
    DeterministicMergeEngine mergeEngine = const DeterministicMergeEngine(),
  })  : _documents = documents,
        _deviceIdentity = deviceIdentity,
        _transport = transport,
        _mergeEngine = mergeEngine,
        _store = MaterializedEntityStore(documents);

  final JsonDocumentRepository _documents;
  final DeviceIdentity _deviceIdentity;
  final SyncTransport _transport;
  final DeterministicMergeEngine _mergeEngine;
  final MaterializedEntityStore _store;

  Future<SyncReport> sync() async {
    final deviceId = await _deviceIdentity.getOrCreate();
    final safeDeviceId = _safe(deviceId);
    final localEventFiles = await _documents.listFiles('sync/events/$safeDeviceId');
    for (final path in localEventFiles) {
      final text = await _documents.readText(path);
      if (text != null) await _transport.writeText(path, text);
    }

    final processed = await _loadProcessedOps();
    var remoteEvents = 0;
    var appliedEvents = 0;
    var conflicts = 0;
    final objects = await _transport.list('sync/events/');
    objects.sort((a, b) => a.path.compareTo(b.path));

    for (final object in objects) {
      final text = await _transport.readText(object);
      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;
        final decoded = jsonDecode(line);
        if (decoded is! Map) throw FormatException('Invalid remote event in ${object.path}.');
        final event = ChangeEvent.fromJson(decoded.map((key, value) => MapEntry(key.toString(), value)));
        if (event.deviceId == deviceId || processed.contains(event.opId)) continue;
        remoteEvents++;

        final current = await _store.latestFor(event);
        final outcome = _mergeEngine.apply(current, event);
        switch (outcome.kind) {
          case MergeOutcomeKind.applied:
            await _store.append(event, outcome.record!);
            appliedEvents++;
          case MergeOutcomeKind.duplicate:
            break;
          case MergeOutcomeKind.conflict:
            conflicts++;
            await _documents.writeObject('sync/conflicts/${_safe(event.opId)}.json', {
              'opId': event.opId,
              'entityType': event.entityType,
              'entityId': event.entityId,
              'reason': outcome.reason,
              'conflictingFields': outcome.conflictingFields,
              'localRecord': current,
              'remoteEvent': event.toJson(),
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            });
        }
        processed.add(event.opId);
      }
    }

    await _documents.writeObject('sync/checkpoints/remote_ops.json', {
      'processed': processed.toList()..sort(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    return SyncReport(
      pushedFiles: localEventFiles.length,
      remoteEvents: remoteEvents,
      appliedEvents: appliedEvents,
      conflicts: conflicts,
    );
  }

  Future<Set<String>> _loadProcessedOps() async {
    final checkpoint = await _documents.readObject('sync/checkpoints/remote_ops.json');
    final raw = checkpoint?['processed'];
    if (raw is! List) return <String>{};
    return raw.whereType<String>().toSet();
  }

  String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty) throw const FormatException('Unsafe empty storage segment.');
    return safe;
  }
}
