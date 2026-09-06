import 'package:flutter/services.dart';

class LocalModelStatus {
  const LocalModelStatus({
    required this.ready,
    required this.modelPath,
    required this.modelBytes,
    required this.modelId,
    required this.modelName,
    required this.runtime,
    required this.selected,
    this.tokenizerPath,
  });

  final bool ready;
  final String modelPath;
  final String? tokenizerPath;
  final int modelBytes;
  final String modelId;
  final String modelName;
  final String runtime;
  final bool selected;

  factory LocalModelStatus.fromMap(Map<Object?, Object?> map) {
    return LocalModelStatus(
      ready: map['ready'] as bool? ?? false,
      modelPath: map['modelPath'] as String? ?? '',
      tokenizerPath: map['tokenizerPath'] as String?,
      modelBytes: (map['modelBytes'] as num?)?.toInt() ?? 0,
      modelId: map['modelId'] as String? ?? '',
      modelName: map['modelName'] as String? ?? 'Local model',
      runtime: map['runtime'] as String? ?? 'unknown',
      selected: map['selected'] as bool? ?? false,
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

  double get progress => totalBytes <= 0
      ? 0
      : (downloadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();

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
  static const llamaModelId = 'llama3.2-3b-instruct-spinquant-int4-eo8';
  static const qwenModelId = 'qwen2.5-1.5b-instruct-q4_k_m';
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
    if (result == null) throw StateError('Android LLM runtime returned no model status.');
    return LocalModelStatus.fromMap(result);
  }

  Future<List<LocalModelStatus>> availableModels() async {
    final result = await _channel.invokeListMethod<Object?>('availableModels');
    if (result == null) return const [];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(LocalModelStatus.fromMap)
        .toList(growable: false);
  }

  Future<LocalModelStatus> selectModel(String modelId) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>('selectModel', {
      'modelId': modelId,
    });
    if (result == null) throw StateError('Android LLM runtime returned no selected model.');
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
      throw StateError('Android LLM runtime returned no model status after deletion.');
    }
    return LocalModelStatus.fromMap(result);
  }

  Future<void> stop() => _channel.invokeMethod<void>('stop');
}

extension HouseHolderIterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
