enum ChangeOperation { create, update, delete }

class ChangeEvent {
  const ChangeEvent({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.deviceId,
    required this.timestamp,
    this.baseHash,
    this.baseData,
    this.value,
    this.patch,
  });

  final String opId;
  final String entityType;
  final String entityId;
  final ChangeOperation operation;
  final String deviceId;
  final DateTime timestamp;

  /// Hash of the entity version the editor observed before making the change.
  final String? baseHash;

  /// Business data for [baseHash]. Required for deterministic three-way merge
  /// when the current materialized record has advanced independently.
  final Map<String, Object?>? baseData;

  /// Full value for create/snapshot operations.
  final Map<String, Object?>? value;

  /// Field-level changes for update operations.
  final Map<String, Object?>? patch;

  factory ChangeEvent.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key is required.');
      }
      return value.trim();
    }

    Map<String, Object?>? object(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! Map) throw FormatException('$key must be an object.');
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    final operationText = requiredString('operation');
    ChangeOperation? operation;
    for (final candidate in ChangeOperation.values) {
      if (candidate.name == operationText) {
        operation = candidate;
        break;
      }
    }
    if (operation == null) {
      throw FormatException('Unsupported change operation: $operationText');
    }

    final timestamp = DateTime.tryParse(requiredString('timestamp'));
    if (timestamp == null) throw const FormatException('timestamp must be ISO-8601.');

    return ChangeEvent(
      opId: requiredString('opId'),
      entityType: requiredString('entityType'),
      entityId: requiredString('entityId'),
      operation: operation,
      deviceId: requiredString('deviceId'),
      timestamp: timestamp,
      baseHash: json['baseHash'] as String?,
      baseData: object('baseData'),
      value: object('value'),
      patch: object('patch'),
    );
  }

  Map<String, Object?> toJson() => {
        'opId': opId,
        'entityType': entityType,
        'entityId': entityId,
        'operation': operation.name,
        'deviceId': deviceId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (baseHash != null) 'baseHash': baseHash,
        if (baseData != null) 'baseData': baseData,
        if (value != null) 'value': value,
        if (patch != null) 'patch': patch,
      };
}
