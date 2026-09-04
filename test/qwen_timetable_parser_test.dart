import 'package:flutter_test/flutter_test.dart';
import 'package:householder/features/schedule/qwen_timetable_parser.dart';

void main() {
  const parser = QwenTimetableParser();

  test('accepts valid timetable cells and removes duplicates/noise', () {
    final result = parser.parse('''
```json
{"cells":[
 {"dayOfWeek":1,"period":1,"subject":"數學","teacher":""},
 {"dayOfWeek":1,"period":1,"subject":"國語","teacher":""},
 {"dayOfWeek":2,"period":3,"subject":"英語","teacher":"李老師"},
 {"dayOfWeek":3,"period":4,"subject":"午餐","teacher":""},
 {"dayOfWeek":6,"period":1,"subject":"數學","teacher":""}
]}
```
''');
    expect(result, isNotNull);
    expect(result!.cells.length, 2);
    expect(result.cells[0].subject, '數學');
    expect(result.cells[1].subject, '英語');
  });

  test('rejects malformed or untrusted output', () {
    expect(parser.parse('not json'), isNull);
    expect(parser.parse('{"cells":[{"dayOfWeek":1,"period":1,"subject":"老師"}]}'), isNull);
  });
}
