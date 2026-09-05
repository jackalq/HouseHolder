import 'package:flutter_test/flutter_test.dart';
import 'package:family_butler/assistant/family_action.dart';

void main() {
  const parser = FamilyActionParser();

  test('parses valid FamilyAction JSON', () {
    final action = parser.parse('''
{
  "type": "schedule.import",
  "requiresConfirmation": true,
  "payload": {"items": []}
}
''');

    expect(action.type, 'schedule.import');
    expect(action.requiresConfirmation, isTrue);
    expect(action.payload, contains('items'));
  });

  test('accepts fenced JSON but still validates envelope', () {
    final action = parser.parse('''```json
{"type":"todo.create","requiresConfirmation":false,"payload":{}}
```''');
    expect(action.type, 'todo.create');
  });

  test('rejects missing confirmation flag', () {
    expect(
      () => parser.parse('{"type":"schedule.import","payload":{}}'),
      throwsFormatException,
    );
  });

  test('rejects non-object output', () {
    expect(() => parser.parse('[1,2,3]'), throwsFormatException);
  });
}
