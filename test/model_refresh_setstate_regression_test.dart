import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model status refresh does not return a Future from setState callback', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      isNot(contains('setState(() => _modelStatusFuture = _llama.modelStatus())')),
      reason: 'Flutter setState callbacks must not return the Future assigned by modelStatus().',
    );
    expect(
      source,
      contains('setState(() {\n      _modelStatusFuture = nextStatus;\n    });'),
    );
  });
}
