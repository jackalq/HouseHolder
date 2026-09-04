import 'package:flutter/services.dart';

class VisionLanguageResult {
  const VisionLanguageResult({
    required this.text,
    required this.modelId,
    required this.runtime,
  });

  final String text;
  final String modelId;
  final String runtime;

  factory VisionLanguageResult.fromMap(Map<Object?, Object?> map) {
    return VisionLanguageResult(
      text: map['text'] as String? ?? '',
      modelId: map['modelId'] as String? ?? '',
      runtime: map['runtime'] as String? ?? '',
    );
  }
}

/// Android-local multimodal inference entry point.
///
/// The native implementation is intentionally separate from the text-only
/// llama.android wrapper: Qwen3-VL requires llama.cpp libmtmd plus an mmproj
/// vision encoder. Keeping this channel independent lets OCR remain a reliable
/// fallback while the native vision runtime is installed/updated independently.
class VisionLanguageGateway {
  static const qwen3VlModelId = 'qwen3-vl-2b-instruct-q4_k_m';
  static const _channel = MethodChannel('householder/vision_language');

  Future<bool> isReady() async =>
      (await _channel.invokeMethod<bool>('isReady')) ?? false;

  Future<Map<Object?, Object?>> modelStatus() async =>
      await _channel.invokeMapMethod<Object?, Object?>('modelStatus') ?? const {};

  Future<VisionLanguageResult> analyzeImage(
    String imagePath, {
    required String prompt,
    int maxTokens = 512,
    double temperature = 0.1,
  }) async {
    if (imagePath.trim().isEmpty) throw ArgumentError.value(imagePath, 'imagePath');
    if (prompt.trim().isEmpty) throw ArgumentError.value(prompt, 'prompt');
    final result = await _channel.invokeMapMethod<Object?, Object?>('analyzeImage', {
      'imagePath': imagePath,
      'prompt': prompt,
      'maxTokens': maxTokens,
      'temperature': temperature,
    });
    if (result == null) throw StateError('Android vision runtime returned no result.');
    return VisionLanguageResult.fromMap(result);
  }
}
