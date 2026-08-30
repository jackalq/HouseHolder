import 'package:flutter/services.dart';

class LocalModelStatus {
  const LocalModelStatus({
    required this.ready,
    required this.modelPath,
    required this.modelBytes,
    this.tokenizerPath,
  });

  final bool ready;
  final String modelPath;
  final String? tokenizerPath;
  final int modelBytes;

  factory LocalModelStatus.fromMap(Map<Object?, Object?> map) {
    return LocalModelStatus(
      ready: map['ready'] as bool? ?? false,
      modelPath: map['modelPath'] as String? ?? '',
      tokenizerPath: map['tokenizerPath'] as String?,
      modelBytes: (map['modelBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocalLlamaGateway {
  static const _channel = MethodChannel('family_butler/llm');

  Future<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.2,
  }) async {
    final result = await _channel.invokeMethod<String>('generate', {
      'prompt': prompt,
      'maxTokens': maxTokens,
      'temperature': temperature,
    });
    return result ?? '';
  }

  Future<bool> isModelReady() async =>
      (await _channel.invokeMethod<bool>('isModelReady')) ?? false;

  Future<LocalModelStatus> modelStatus() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('modelStatus');
    if (result == null) {
      throw StateError('Android Llama runtime returned no model status.');
    }
    return LocalModelStatus.fromMap(result);
  }

  Future<bool> pickModelFile() async =>
      (await _channel.invokeMethod<bool>('pickModelFile')) ?? false;

  Future<bool> pickTokenizerFile() async =>
      (await _channel.invokeMethod<bool>('pickTokenizerFile')) ?? false;

  Future<LocalModelStatus> deleteModelPack() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('deleteModelPack');
    if (result == null) {
      throw StateError('Android Llama runtime returned no model status after deletion.');
    }
    return LocalModelStatus.fromMap(result);
  }

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
