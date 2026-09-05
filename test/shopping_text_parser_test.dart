import 'dart:convert';

import 'package:family_butler/assistant/shopping_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ShoppingTextParser();

  test('parses multi-item shopping list with quantities and units', () {
    final raw = parser.tryBuildAddAction('幫我買牛奶2瓶、雞蛋一盒、衛生紙3串');
    expect(raw, isNotNull);
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    final items = (json['payload'] as Map<String, dynamic>)['items'] as List<dynamic>;
    expect(items, hasLength(3));
    expect(items[0], containsPair('name', '牛奶'));
    expect(items[0], containsPair('quantity', 2));
    expect(items[0], containsPair('unit', '瓶'));
    expect(items[1], containsPair('name', '雞蛋'));
    expect(items[1], containsPair('quantity', 1));
    expect(items[1], containsPair('unit', '盒'));
    expect(items[2], containsPair('quantity', 3));
  });

  test('parses newline separated shopping input', () {
    final raw = parser.tryBuildAddAction('採買\n牛奶 2 瓶\n吐司 1 包');
    expect(raw, isNotNull);
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    final items = (json['payload'] as Map<String, dynamic>)['items'] as List<dynamic>;
    expect(items, hasLength(2));
  });

  test('supports chinese quantities above ten', () {
    final raw = parser.tryBuildAddAction('買雞蛋十二顆');
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    final item = ((json['payload'] as Map<String, dynamic>)['items'] as List<dynamic>).single as Map<String, dynamic>;
    expect(item['quantity'], 12);
    expect(item['unit'], '顆');
  });

  test('does not hijack text without explicit shopping add intent', () {
    expect(parser.tryBuildAddAction('購物清單有什麼？'), isNull);
    expect(parser.tryBuildAddAction('明天有什麼課？'), isNull);
  });
}
