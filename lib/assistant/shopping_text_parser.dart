import 'dart:convert';

/// Parses common shopping-list input without involving the local LLM.
///
/// This deliberately only handles explicit add intents. Ambiguous text falls
/// back to the normal assistant planner.
class ShoppingTextParser {
  const ShoppingTextParser();

  String? tryBuildAddAction(String input) {
    var text = input.trim();
    if (text.isEmpty || !_hasExplicitAddIntent(text)) return null;

    text = _removeIntentPrefix(text)
        .replaceAll(RegExp(r'(?:到|進|至)?(?:我的)?(?:採買|採購|購物)(?:清單)?(?:裡|中)?'), ' ')
        .replaceAll(RegExp(r'(?:加入|加到|新增)'), ' ')
        .trim();
    if (text.isEmpty) return null;

    final chunks = text
        .split(RegExp(r'[、,，;；\n]+|\s+(?:跟|和|及)\s+'))
        .map(_cleanChunk)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (chunks.isEmpty) return null;

    final items = <Map<String, Object?>>[];
    for (final chunk in chunks) {
      final parsed = _parseItem(chunk);
      if (parsed == null) return null;
      items.add(parsed);
    }

    return jsonEncode({
      'type': 'shopping.add',
      'requiresConfirmation': false,
      'payload': {'items': items},
    });
  }

  bool _hasExplicitAddIntent(String text) => RegExp(
        r'(?:^|\s)(?:買|採買|採購|購買|添購|加入|新增)|(?:幫我|我要|需要|記得)\s*(?:買|採買|採購|購買|添購)',
      ).hasMatch(text) ||
      text.startsWith('買') ||
      text.startsWith('採買') ||
      text.startsWith('採購') ||
      text.startsWith('購買');

  String _removeIntentPrefix(String value) => value
      .replaceFirst(RegExp(r'^\s*(?:請|麻煩)?\s*(?:幫我)?\s*(?:我要|我想要|需要|記得)?\s*(?:買|採買|採購|購買|添購)\s*'), '')
      .replaceFirst(RegExp(r'^\s*(?:請|麻煩)?\s*(?:幫我)?\s*(?:把|將)?\s*'), '');

  String _cleanChunk(String value) => value
      .replaceAll(RegExp(r'^(?:把|將)\s*'), '')
      .replaceAll(RegExp(r'\s*(?:加入|加到|新增到).*$'), '')
      .trim();

  Map<String, Object?>? _parseItem(String chunk) {
    // Prefer an explicit trailing quantity + unit, e.g. 牛奶2瓶 / 雞蛋 12 顆.
    final match = RegExp(
      r'^(.+?)\s*([0-9]+|[一二兩三四五六七八九十]+)\s*(個|瓶|罐|盒|包|袋|串|組|捲|卷|顆|粒|片|張|條|支|杯|公斤|公克|克|kg|g|公升|毫升|l|ml)?$',
      caseSensitive: false,
    ).firstMatch(chunk);

    String name;
    int quantity;
    String unit;
    if (match != null) {
      name = match.group(1)!.trim();
      quantity = _quantity(match.group(2)!);
      unit = (match.group(3) ?? '個').trim();
      if (unit == '卷') unit = '捲';
    } else {
      name = chunk.trim();
      quantity = 1;
      unit = '個';
    }

    name = name.replaceAll(RegExp(r'^(?:買|採買|採購|購買)\s*'), '').trim();
    if (name.isEmpty || quantity < 1 || quantity > 999) return null;
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'done': false,
    };
  }

  int _quantity(String raw) {
    final numeric = int.tryParse(raw);
    if (numeric != null) return numeric;
    const digits = {'一': 1, '二': 2, '兩': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
    if (raw == '十') return 10;
    if (raw.contains('十')) {
      final parts = raw.split('十');
      final tens = parts.first.isEmpty ? 1 : (digits[parts.first] ?? 0);
      final ones = parts.length < 2 || parts[1].isEmpty ? 0 : (digits[parts[1]] ?? 0);
      return tens * 10 + ones;
    }
    return digits[raw] ?? 0;
  }
}
