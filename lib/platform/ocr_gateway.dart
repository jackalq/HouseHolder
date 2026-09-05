import 'package:flutter/services.dart';

class OcrBlock {
  const OcrBlock({required this.text, this.left, this.top, this.right, this.bottom});

  final String text;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  factory OcrBlock.fromMap(Map<Object?, Object?> map) => OcrBlock(
        text: map['text'] as String? ?? '',
        left: (map['left'] as num?)?.toDouble(),
        top: (map['top'] as num?)?.toDouble(),
        right: (map['right'] as num?)?.toDouble(),
        bottom: (map['bottom'] as num?)?.toDouble(),
      );
}

class OcrDocument {
  const OcrDocument({required this.fullText, required this.blocks});

  final String fullText;

  /// Geometry-bearing OCR tokens. Android returns both ML Kit elements and
  /// lines: elements preserve cell position while lines preserve Chinese words
  /// that ML Kit may otherwise split into individual characters.
  final List<OcrBlock> blocks;
}

class OcrGateway {
  static const _channel = MethodChannel('householder/ocr');

  Future<OcrDocument> recognizeImage(String imagePath) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'recognizeImage',
      {'imagePath': imagePath},
    );

    if (result == null) {
      throw StateError('OCR returned no result.');
    }

    final elements = result['elements'] as List<Object?>? ?? const <Object?>[];
    final lines = result['lines'] as List<Object?>? ?? const <Object?>[];
    final blocks = result['blocks'] as List<Object?>? ?? const <Object?>[];
    final rawBlocks = <Object?>[
      ...elements,
      ...lines,
      if (elements.isEmpty && lines.isEmpty) ...blocks,
    ];
    return OcrDocument(
      fullText: result['fullText'] as String? ?? '',
      blocks: rawBlocks
          .whereType<Map<Object?, Object?>>()
          .map(OcrBlock.fromMap)
          .toList(growable: false),
    );
  }
}
