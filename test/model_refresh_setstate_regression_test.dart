import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model list refresh keeps setState callback synchronous', () {
    final source = File(
      'lib/features/model/recommended_model_installer.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('setState(() => _modelsFuture = _llama.availableModels());'),
      reason: 'The model refresh should replace the Future synchronously inside setState.',
    );
    expect(
      source,
      isNot(contains('setState(() => _llama.availableModels())')),
      reason: 'Flutter setState callbacks must not return the Future from availableModels().',
    );
  });
}
