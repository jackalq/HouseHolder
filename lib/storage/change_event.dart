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

  /// Full value for create/snapshot operations.
  final Map<String, Object?>? value;

  /// Field-level changes for update operations.
  final Map<String, Object?>? patch;

  Map<String, Object?> toJson() => {
        'opId': opId,
        'entityType': entityType,
        'entityId': entityId,
        'operation': operation.name,
        'deviceId': deviceId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (baseHash != null) 'baseHash': baseHash,
        if (value != null) 'value': value,
        if (patch != null) 'patch': patch,
      };
}
