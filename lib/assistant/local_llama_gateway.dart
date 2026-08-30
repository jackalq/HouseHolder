import 'package:flutter/services.dart';

class LocalLlamaGateway {
  static const _channel = MethodChannel('family_butler/llm');

  Future<String> generate(String prompt) async {
    final result = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
      'maxTokens': 256,
      'temperature': 0.2,
    });
    return result ?? '';
  }

  Future<bool> isModelReady() async =>
      (await _channel.invokeMethod<bool>('isModelReady')) ?? false;
}
