import 'package:flutter/services.dart';

class SpeechTranscript {
  const SpeechTranscript({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

class SpeechGateway {
  static const _channel = MethodChannel('householder/speech');

  Future<bool> isOnDeviceAvailable() async =>
      (await _channel.invokeMethod<bool>('isOnDeviceAvailable')) ?? false;

  Future<SpeechTranscript> recognizeOnce({bool onDeviceOnly = false}) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'recognizeOnce',
      {'onDeviceOnly': onDeviceOnly},
    );

    if (result == null) {
      throw StateError('Speech recognition returned no result.');
    }

    return SpeechTranscript(
      text: result['text'] as String? ?? '',
      isFinal: result['isFinal'] as bool? ?? true,
    );
  }
}
