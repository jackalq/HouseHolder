import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model list refresh keeps setState callback synchronous', () {
    final source = File(
      'lib/features/model/recommended_model_installer.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('final modelsFuture = _llama.availableModels();'),
      reason: 'Async work should be started before entering setState.',
    );
    expect(
      source,
      contains('_modelsFuture = modelsFuture;'),
      reason: 'setState should synchronously assign the already-created Future.',
    );
    expect(
      source,
      isNot(contains('setState(() => _modelsFuture = _llama.availableModels());')),
      reason: 'An expression-bodied setState callback would return the Future and crash at runtime.',
    );
  });
}
