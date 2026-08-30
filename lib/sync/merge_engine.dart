import '../storage/canonical_json.dart';
import '../storage/change_event.dart';
import '../storage/hash_service.dart';

enum MergeOutcomeKind { applied, duplicate, conflict }

class MergeOutcome {
  const MergeOutcome._(this.kind, {this.record, this.reason, this.conflictingFields = const []});

  final MergeOutcomeKind kind;
  final Map<String, Object?>? record;
  final String? reason;
  final List<String> conflictingFields;

  const MergeOutcome.applied(Map<String, Object?> record)
      : this._(MergeOutcomeKind.applied, record: record);
  const MergeOutcome.duplicate() : this._(MergeOutcomeKind.duplicate);
  const MergeOutcome.conflict(String reason, [List<String> fields = const []])
      : this._(MergeOutcomeKind.conflict, reason: reason, conflictingFields: fields);
}

class DeterministicMergeEngine {
  const DeterministicMergeEngine({HashService hashService = const HashService()})
      : _hashService = hashService;

  final HashService _hashService;

  MergeOutcome apply(Map<String, Object?>? currentRecord, ChangeEvent event) {
    if (event.resolutionOf != null) return _resolution(currentRecord, event);
    return switch (event.operation) {
      ChangeOperation.create => _create(currentRecord, event),
      ChangeOperation.update => _update(currentRecord, event),
      ChangeOperation.delete => _delete(currentRecord, event),
    };
  }

  MergeOutcome _resolution(Map<String, Object?>? current, ChangeEvent event) {
    if (current == null) return const MergeOutcome.conflict('Resolution target does not exist.');
    final currentHash = current['hash'];
    if (currentHash != event.baseHash && currentHash != event.alternateBaseHash) {
      return const MergeOutcome.conflict('Conflict resolution is stale because the entity changed again.');
    }

    if (event.operation == ChangeOperation.delete) {
      if (current['deleted'] == true) return const MergeOutcome.duplicate();
      return MergeOutcome.applied({
        ...current,
        'version': (current['version'] as int? ?? 1) + 1,
        'modifiedBy': event.deviceId,
        'modifiedAt': event.timestamp.toUtc().toIso8601String(),
        'deleted': true,
      });
    }

    final patch = event.patch;
    if (patch == null) return const MergeOutcome.conflict('Resolution update has no resolved values.');
    final currentData = _dataOf(current);
    final nextData = <String, Object?>{...currentData, ...patch};
    if (current['deleted'] != true && _same(currentData, nextData)) {
      return const MergeOutcome.duplicate();
    }
    return MergeOutcome.applied(_nextRecord(current, nextData, event));
  }

  MergeOutcome _create(Map<String, Object?>? current, ChangeEvent event) {
    final incoming = event.value;
    if (incoming == null) return const MergeOutcome.conflict('Create event has no value.');
    if (current == null) return MergeOutcome.applied(incoming);
    if (current['hash'] == incoming['hash']) return const MergeOutcome.duplicate();
    return const MergeOutcome.conflict('Entity already exists with different content.');
  }

  MergeOutcome _update(Map<String, Object?>? current, ChangeEvent event) {
    if (current == null) return const MergeOutcome.conflict('Update target does not exist.');
    final patch = event.patch;
    if (patch == null || patch.isEmpty) return const MergeOutcome.duplicate();
    final currentData = _dataOf(current);

    if (current['hash'] == event.baseHash) {
      return MergeOutcome.applied(_nextRecord(current, {...currentData, ...patch}, event));
    }

    final baseData = event.baseData;
    if (baseData == null) {
      return const MergeOutcome.conflict('Concurrent update has no baseData for three-way merge.');
    }

    final localChanged = _changedFields(baseData, currentData);
    final remoteChanged = _changedFields(baseData, {...baseData, ...patch});
    final overlap = localChanged.intersection(remoteChanged).where((field) {
      return !_same(currentData[field], patch[field]);
    }).toList()
      ..sort();

    if (overlap.isNotEmpty) {
      return MergeOutcome.conflict('Same-field concurrent update.', overlap);
    }

    final merged = Map<String, Object?>.from(currentData);
    for (final field in remoteChanged) {
      if (patch.containsKey(field)) merged[field] = patch[field];
    }
    if (_same(merged, currentData)) return const MergeOutcome.duplicate();
    return MergeOutcome.applied(_nextRecord(current, merged, event));
  }

  MergeOutcome _delete(Map<String, Object?>? current, ChangeEvent event) {
    if (current == null || current['deleted'] == true) return const MergeOutcome.duplicate();
    if (current['hash'] != event.baseHash) {
      return const MergeOutcome.conflict('Delete conflicts with a newer local version.');
    }
    return MergeOutcome.applied({
      ...current,
      'version': (current['version'] as int? ?? 1) + 1,
      'modifiedBy': event.deviceId,
      'modifiedAt': event.timestamp.toUtc().toIso8601String(),
      'deleted': true,
    });
  }

  Map<String, Object?> _nextRecord(
    Map<String, Object?> current,
    Map<String, Object?> data,
    ChangeEvent event,
  ) => {
        ...current,
        'version': (current['version'] as int? ?? 1) + 1,
        'data': data,
        'hash': _hashService.contentHash(data),
        'modifiedBy': event.deviceId,
        'modifiedAt': event.timestamp.toUtc().toIso8601String(),
        'deleted': false,
      };

  Set<String> _changedFields(Map<String, Object?> base, Map<String, Object?> next) {
    final keys = <String>{...base.keys, ...next.keys};
    return keys.where((key) => !_same(base[key], next[key])).toSet();
  }

  bool _same(Object? a, Object? b) => CanonicalJson.encode(a) == CanonicalJson.encode(b);

  Map<String, Object?> _dataOf(Map<String, Object?> record) {
    final raw = record['data'];
    if (raw is! Map) throw const FormatException('Entity record data must be an object.');
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
}
