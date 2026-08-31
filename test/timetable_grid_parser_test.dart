import 'package:flutter_test/flutter_test.dart';
import 'package:householder/features/schedule/timetable_grid_parser.dart';
import 'package:householder/platform/ocr_gateway.dart';

void main() {
  test('reconstructs the 23 course cells from weekday/period geometry', () {
    const xs = <int, double>{1: 200, 2: 300, 3: 400, 4: 500, 5: 600};
    const ys = <int, double>{1: 220, 2: 320, 3: 420, 4: 520, 5: 660, 6: 760, 7: 860};
    const expected = <(int, int, String)>[
      (1, 1, '數學'), (2, 1, '數學'), (3, 1, '數學'), (4, 1, '彈性'), (5, 1, '數學'),
      (1, 2, '國語'), (2, 2, '體育'), (3, 2, '國語'), (4, 2, '國語'), (5, 2, '體育'),
      (1, 3, '健康'), (2, 3, '音樂'), (3, 3, '英語'), (4, 3, '美術'), (5, 3, '國語'),
      (1, 4, '本土語'), (2, 4, '國語'), (3, 4, '生活'), (4, 4, '美術'), (5, 4, '生活'),
      (2, 5, '閱讀'), (2, 6, '國語'), (2, 7, '生活'),
    ];

    final blocks = <OcrBlock>[
      for (var day = 1; day <= 5; day++)
        _block('星期${const ['一', '二', '三', '四', '五'][day - 1]}', xs[day]!, 120),
      for (var period = 1; period <= 7; period++) _block('$period', 70, ys[period]!),
      for (final item in expected) _block(item.$3, xs[item.$1]!, ys[item.$2]!),
      _block('張嘉峰', xs[2]!, ys[2]! + 30),
      _block('吳羽涵', xs[4]!, ys[3]! + 30),
      _block('午餐', 400, 590),
      _block('制服', 200, 930),
      _block('04-22956975', 350, 1000),
    ];

    final result = const TimetableGridParser().parse(
      OcrDocument(fullText: 'flattened OCR is intentionally irrelevant', blocks: blocks),
    );

    expect(result.cells.length, 23);
    for (final item in expected) {
      expect(
        result.cells.any((c) =>
            c.dayOfWeek == item.$1 && c.period == item.$2 && c.subject == item.$3),
        isTrue,
        reason: 'missing weekday ${item.$1} period ${item.$2} ${item.$3}',
      );
    }
    expect(result.cells.any((c) => c.subject == '張嘉峰'), isFalse);
    expect(result.cells.any((c) => c.subject == '午餐'), isFalse);
    expect(result.cells.any((c) => c.subject == '制服'), isFalse);
  });

  test('normalizes common OCR confusion for 本土語', () {
    final blocks = <OcrBlock>[
      _block('星期一', 200, 100),
      _block('星期二', 300, 100),
      _block('星期三', 400, 100),
      _block('星期四', 500, 100),
      _block('星期五', 600, 100),
      _block('1', 70, 220),
      _block('2', 70, 320),
      _block('3', 70, 420),
      _block('4', 70, 520),
      _block('本士語', 200, 520),
    ];
    final result = const TimetableGridParser().parse(OcrDocument(fullText: '', blocks: blocks));
    expect(result.cells.single.subject, '本土語');
  });
}

OcrBlock _block(String text, double centerX, double centerY) => OcrBlock(
      text: text,
      left: centerX - 30,
      right: centerX + 30,
      top: centerY - 15,
      bottom: centerY + 15,
    );
