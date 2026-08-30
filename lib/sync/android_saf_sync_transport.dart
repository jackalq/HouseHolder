import 'package:flutter/services.dart';

import 'sync_transport.dart';

class SyncTreeStatus {
  const SyncTreeStatus({required this.configured, this.displayName, this.uri});

  final bool configured;
  final String? displayName;
  final String? uri;

  factory SyncTreeStatus.fromMap(Map<Object?, Object?> map) => SyncTreeStatus(
        configured: map['configured'] as bool? ?? false,
        displayName: map['displayName'] as String?,
        uri: map['uri'] as String?,
      );
}

class AndroidSafSyncTransport implements SyncTransport {
  static const _channel = MethodChannel('householder/sync_tree');

  Future<SyncTreeStatus> status() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>('status');
    return SyncTreeStatus.fromMap(value ?? const {});
  }

  Future<bool> pickTree() async =>
      (await _channel.invokeMethod<bool>('pickTree')) ?? false;

  Future<void> clearTree() async {
    await _channel.invokeMethod<void>('clearTree');
  }

  @override
  Future<List<SyncObject>> list(String prefix) async {
    final raw = await _channel.invokeListMethod<Object?>('list', {'prefix': prefix}) ?? const [];
    return raw.map((entry) {
      if (entry is! Map) throw const FormatException('Invalid sync tree list entry.');
      final path = entry['path'];
      if (path is! String || path.isEmpty) {
        throw const FormatException('Sync tree entry path is required.');
      }
      final millis = entry['modifiedAtMillis'];
      return SyncObject(
        path: path,
        remoteId: entry['remoteId'] as String?,
        modifiedAt: millis is num
            ? DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true)
            : null,
      );
    }).toList(growable: false);
  }

  @override
  Future<String> readText(SyncObject object) async {
    final value = await _channel.invokeMethod<String>('readText', {'path': object.path});
    if (value == null) throw StateError('Sync provider returned no content for ${object.path}.');
    return value;
  }

  @override
  Future<void> writeText(String path, String content) async {
    await _channel.invokeMethod<void>('writeText', {'path': path, 'content': content});
  }
}
