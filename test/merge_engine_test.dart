import 'package:family_butler/storage/change_event.dart';
import 'package:family_butler/storage/hash_service.dart';
import 'package:family_butler/sync/merge_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hashes = HashService();
  const engine = DeterministicMergeEngine();

  Map<String, Object?> record(Map<String, Object?> data) => {
        'id': 'x',
        'version': 2,
        'data': data,
        'hash': hashes.contentHash(data),
        'createdBy': 'a',
        'createdAt': '2026-08-30T00:00:00Z',
        'modifiedBy': 'a',
        'modifiedAt': '2026-08-30T00:01:00Z',
        'deleted': false,
      };

  ChangeEvent update({required Map<String, Object?> base, required Map<String, Object?> patch}) =>
      ChangeEvent(
        opId: 'op-1',
        entityType: 'shoppingItem',
        entityId: 'x',
        operation: ChangeOperation.update,
        deviceId: 'b',
        timestamp: DateTime.utc(2026, 8, 30, 1),
        baseHash: hashes.contentHash(base),
        baseData: base,
        patch: patch,
      );

  test('exact base hash applies patch', () {
    final base = <String, Object?>{'name': '牛奶', 'quantity': 1, 'done': false};
    final outcome = engine.apply(record(base), update(base: base, patch: {'quantity': 2}));
    expect(outcome.kind, MergeOutcomeKind.applied);
    expect((outcome.record!['data'] as Map)['quantity'], 2);
  });

  test('non-overlapping concurrent fields merge automatically', () {
    final base = <String, Object?>{'name': '牛奶', 'quantity': 1, 'note': null};
    final local = <String, Object?>{'name': '牛奶', 'quantity': 2, 'note': null};
    final outcome = engine.apply(record(local), update(base: base, patch: {'note': '低脂'}));
    expect(outcome.kind, MergeOutcomeKind.applied);
    final data = outcome.record!['data'] as Map;
    expect(data['quantity'], 2);
    expect(data['note'], '低脂');
  });

  test('same-field concurrent edit becomes conflict', () {
    final base = <String, Object?>{'name': '牛奶', 'quantity': 1};
    final local = <String, Object?>{'name': '牛奶', 'quantity': 2};
    final outcome = engine.apply(record(local), update(base: base, patch: {'quantity': 3}));
    expect(outcome.kind, MergeOutcomeKind.conflict);
    expect(outcome.conflictingFields, ['quantity']);
  });

  test('user resolution can replace either known conflict branch', () {
    final local = <String, Object?>{'name': '牛奶', 'quantity': 2};
    final remote = <String, Object?>{'name': '牛奶', 'quantity': 3};
    final event = ChangeEvent(
      opId: 'resolution-1',
      entityType: 'shoppingItem',
      entityId: 'x',
      operation: ChangeOperation.update,
      deviceId: 'a',
      timestamp: DateTime.utc(2026, 8, 30, 2),
      baseHash: hashes.contentHash(local),
      alternateBaseHash: hashes.contentHash(remote),
      resolutionOf: 'op-conflict',
      baseData: local,
      patch: {'quantity': 2},
    );
    final outcome = engine.apply(record(remote), event);
    expect(outcome.kind, MergeOutcomeKind.applied);
    expect((outcome.record!['data'] as Map)['quantity'], 2);
  });

  test('stale user resolution cannot overwrite a newer third state', () {
    final local = <String, Object?>{'name': '牛奶', 'quantity': 2};
    final remote = <String, Object?>{'name': '牛奶', 'quantity': 3};
    final newer = <String, Object?>{'name': '牛奶', 'quantity': 4};
    final event = ChangeEvent(
      opId: 'resolution-1',
      entityType: 'shoppingItem',
      entityId: 'x',
      operation: ChangeOperation.update,
      deviceId: 'a',
      timestamp: DateTime.utc(2026, 8, 30, 2),
      baseHash: hashes.contentHash(local),
      alternateBaseHash: hashes.contentHash(remote),
      resolutionOf: 'op-conflict',
      baseData: local,
      patch: {'quantity': 2},
    );
    final outcome = engine.apply(record(newer), event);
    expect(outcome.kind, MergeOutcomeKind.conflict);
  });
}
