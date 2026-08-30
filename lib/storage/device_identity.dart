import 'dart:math';

import 'json_repository.dart';

class DeviceIdentity {
  DeviceIdentity(this._repository);

  final JsonDocumentRepository _repository;

  Future<String> getOrCreate() async {
    final existing = await _repository.readObject('sync/device.json');
    final id = existing?['deviceId'];
    if (id is String && id.isNotEmpty) return id;

    final created = _newId();
    await _repository.writeObject('sync/device.json', {
      'deviceId': created,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    return created;
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(10, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'android-$hex';
  }
}
