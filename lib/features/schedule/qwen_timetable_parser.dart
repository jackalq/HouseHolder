import 'dart:convert';

import 'timetable_grid_parser.dart';

class QwenTimetableParser {
  const QwenTimetableParser();

  static const _subjects = <String>{
    '國語','數學','英語','英文','體育','健康','音樂','美術','生活','自然','社會',
    '本土語','本土語言','閱讀','彈性','資訊','綜合',
  };

  TimetableGridResult? parse(String raw) {
    final jsonText = _extractJson(raw);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map || decoded['cells'] is! List) return null;
      final cells = <TimetableGridCell>[];
      final seen = <String>{};
      for (final item in decoded['cells'] as List) {
        if (item is! Map) continue;
        final day = (item['dayOfWeek'] as num?)?.toInt();
        final period = (item['period'] as num?)?.toInt();
        final subject = (item['subject'] as String?)?.trim() ?? '';
        if (day == null || day < 1 || day > 5) continue;
        if (period == null || period < 1 || period > 7) continue;
        if (!_subjects.contains(subject)) continue;
        if (!seen.add('$day:$period')) continue;
        cells.add(TimetableGridCell(dayOfWeek: day, period: period, subject: subject));
      }
      if (cells.isEmpty) return null;
      cells.sort((a, b) => a.dayOfWeek == b.dayOfWeek
          ? a.period.compareTo(b.period)
          : a.dayOfWeek.compareTo(b.dayOfWeek));
      return TimetableGridResult(
        cells: cells,
        warnings: const ['Qwen3-VL 圖片辨識結果已通過星期、節次與課程白名單驗證'],
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractJson(String raw) {
    final text = raw.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
