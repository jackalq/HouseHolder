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

class RecommendedModelInfo {
  const RecommendedModelInfo({
    required this.name,
    required this.source,
    required this.sourceUrl,
    required this.licenseUrl,
    required this.modelBytes,
    required this.tokenizerBytes,
    required this.totalBytes,
    required this.recommendedRamBytes,
  });

  final String name;
  final String source;
  final String sourceUrl;
  final String licenseUrl;
  final int modelBytes;
  final int tokenizerBytes;
  final int totalBytes;
  final int recommendedRamBytes;

  factory RecommendedModelInfo.fromMap(Map<Object?, Object?> map) {
    return RecommendedModelInfo(
      name: map['name'] as String? ?? 'Recommended Llama model',
      source: map['source'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      licenseUrl: map['licenseUrl'] as String? ?? '',
      modelBytes: (map['modelBytes'] as num?)?.toInt() ?? 0,
      tokenizerBytes: (map['tokenizerBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      recommendedRamBytes: (map['recommendedRamBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class RecommendedModelDownloadStatus {
  const RecommendedModelDownloadStatus({
    required this.downloading,
    required this.stage,
    required this.downloadedBytes,
    required this.totalBytes,
    this.error,
  });

  final bool downloading;
  final String stage;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;

  double get progress => totalBytes <= 0 ? 0 : (downloadedBytes / totalBytes).clamp(0, 1);

  factory RecommendedModelDownloadStatus.fromMap(Map<Object?, Object?> map) {
    return RecommendedModelDownloadStatus(
      downloading: map['downloading'] as bool? ?? false,
      stage: map['stage'] as String? ?? 'idle',
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      error: map['error'] as String?,
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
    if (result == null) throw StateError('Android Llama runtime returned no model status.');
    return LocalModelStatus.fromMap(result);
  }

  Future<RecommendedModelInfo> recommendedModelInfo() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('recommendedModelInfo');
    if (result == null) throw StateError('Android returned no recommended model info.');
    return RecommendedModelInfo.fromMap(result);
  }

  Future<RecommendedModelDownloadStatus> recommendedDownloadStatus() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('recommendedDownloadStatus');
    if (result == null) throw StateError('Android returned no download status.');
    return RecommendedModelDownloadStatus.fromMap(result);
  }

  Future<LocalModelStatus> downloadRecommendedModelPack() async {
    final result =
        await _channel.invokeMapMethod<Object?, Object?>('downloadRecommendedModelPack');
    if (result == null) throw StateError('Android returned no model status after download.');
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
