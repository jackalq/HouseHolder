import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android OCR bridge returns element and line bounding boxes', () {
    final source = File(
      'android/app/src/main/kotlin/com/householder/app/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('line.elements.map { element ->'));
    expect(source, contains('geometryToken(element.text, element.boundingBox)'));
    expect(source, contains('"elements" to elements'));
    expect(source, contains('"lines" to lines'));
  });

  test('Flutter OCR gateway keeps element precision plus line context', () {
    final source = File('lib/platform/ocr_gateway.dart').readAsStringSync();

    expect(source, contains('...elements,'));
    expect(source, contains('...lines,'));
    expect(source, contains('if (elements.isEmpty && lines.isEmpty) ...blocks'));
  });
}
