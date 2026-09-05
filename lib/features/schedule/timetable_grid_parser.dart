import '../../platform/ocr_gateway.dart';

class TimetableGridCell {
  const TimetableGridCell({
    required this.dayOfWeek,
    required this.period,
    required this.subject,
  });

  final int dayOfWeek;
  final int period;
  final String subject;
}

class TimetableGridResult {
  const TimetableGridResult({required this.cells, required this.warnings});

  final List<TimetableGridCell> cells;
  final List<String> warnings;

  bool get usable => cells.isNotEmpty;

  String toPromptText() {
    final lines = cells
        .map((cell) =>
            'dayOfWeek=${cell.dayOfWeek},period=${cell.period},subject=${cell.subject}')
        .join('\n');
    final warningText = warnings.isEmpty ? '(none)' : warnings.join(' | ');
    return 'STRUCTURED_TIMETABLE_GRID:\n$lines\nGRID_WARNINGS:$warningText';
  }
}

/// Geometry-first parser for school timetable OCR.
///
/// It never attempts to reconstruct a table from flattened OCR text. Instead it
/// locates weekday headers and period-number anchors, derives cell boundaries,
/// then assigns OCR elements to the matching cell by their bounding-box center.
///
/// Newer Android builds return fine-grained ML Kit elements. For compatibility
/// with older builds that return a whole text block, [_explodeCoarseBlocks]
/// creates approximate line/word boxes before applying the same geometry logic.
class TimetableGridParser {
  const TimetableGridParser();

  static const _subjects = <String>{
    '國語',
    '數學',
    '英語',
    '英文',
    '體育',
    '健康',
    '音樂',
    '美術',
    '生活',
    '自然',
    '社會',
    '本土語',
    '本土語言',
    '閱讀',
    '彈性',
    '資訊',
    '綜合',
  };

  static const _aliases = <String, String>{
    '本士語': '本土語',
    '本十語': '本土語',
    '本上語': '本土語',
    '国语': '國語',
    '数学': '數學',
    '体育': '體育',
    '音乐': '音樂',
    '美术': '美術',
    '英语': '英語',
    '弹性': '彈性',
    '阅读': '閱讀',
  };

  TimetableGridResult parse(OcrDocument document) {
    final bounded = document.blocks.where(_hasBounds).toList(growable: false);
    final blocks = _explodeCoarseBlocks(bounded);
    final warnings = <String>[];

    final weekdayAnchors = <int, OcrBlock>{};
    for (final block in blocks) {
      final day = _weekday(block.text);
      if (day != null && day <= 5) {
        final current = weekdayAnchors[day];
        if (current == null || _top(block) < _top(current)) weekdayAnchors[day] = block;
      }
    }
    if (weekdayAnchors.length < 4) {
      return TimetableGridResult(
        cells: const [],
        warnings: ['找不到足夠的星期欄位（${weekdayAnchors.length}/5）'],
      );
    }

    final orderedDays = weekdayAnchors.entries.toList()
      ..sort((a, b) => _centerX(a.value).compareTo(_centerX(b.value)));
    final dayCenters = orderedDays.map((e) => _centerX(e.value)).toList(growable: false);
    final headerBottom = weekdayAnchors.values.map(_bottom).reduce((a, b) => a > b ? a : b);

    final periodAnchors = <int, OcrBlock>{};
    for (final block in blocks) {
      if (_centerY(block) <= headerBottom) continue;
      final period = _periodNumber(block.text);
      if (period == null) continue;
      final leftMostDay = dayCenters.first;
      if (_centerX(block) >= leftMostDay) continue;
      final current = periodAnchors[period];
      if (current == null || _centerX(block) < _centerX(current)) periodAnchors[period] = block;
    }
    if (periodAnchors.length < 3) {
      return TimetableGridResult(
        cells: const [],
        warnings: ['找不到足夠的節次列（${periodAnchors.length}）'],
      );
    }

    final orderedPeriods = periodAnchors.entries.toList()
      ..sort((a, b) => _centerY(a.value).compareTo(_centerY(b.value)));
    final periodCenters = orderedPeriods.map((e) => _centerY(e.value)).toList(growable: false);

    final cells = <TimetableGridCell>[];
    for (var dayIndex = 0; dayIndex < orderedDays.length; dayIndex++) {
      final day = orderedDays[dayIndex].key;
      final xRange = _axisRange(dayCenters, dayIndex);
      for (var periodIndex = 0; periodIndex < orderedPeriods.length; periodIndex++) {
        final period = orderedPeriods[periodIndex].key;
        final yRange = _axisRange(periodCenters, periodIndex);
        final candidates = blocks.where((block) {
          final x = _centerX(block);
          final y = _centerY(block);
          return x >= xRange.$1 && x < xRange.$2 && y >= yRange.$1 && y < yRange.$2;
        }).toList(growable: false);
        final subject = _subjectFrom(candidates);
        if (subject != null) {
          cells.add(TimetableGridCell(dayOfWeek: day, period: period, subject: subject));
        }
      }
    }

    if (weekdayAnchors.length < 5) warnings.add('只定位到 ${weekdayAnchors.length}/5 個星期欄位');
    if (periodAnchors.length < 7) warnings.add('只定位到 ${periodAnchors.length}/7 個節次列');
    if (bounded.any((b) => b.text.contains('\n'))) {
      warnings.add('OCR 回傳較粗文字區塊，已用區塊內行列位置近似還原；建議逐格確認');
    }
    if (cells.isEmpty) warnings.add('表格已定位，但沒有可靠的課程名稱');
    return TimetableGridResult(cells: cells, warnings: warnings);
  }

  /// Converts paragraph-like ML Kit blocks into approximate geometry tokens.
  /// This fallback is intentionally conservative: fine-grained element boxes
  /// pass through unchanged, while multiline/space-separated blocks are split
  /// proportionally inside their original bounding box.
  List<OcrBlock> _explodeCoarseBlocks(List<OcrBlock> source) {
    final result = <OcrBlock>[];
    for (final block in source) {
      final lines = block.text
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (lines.length <= 1) {
        result.addAll(_splitHorizontal(block, block.text.trim()));
        continue;
      }

      final height = block.bottom! - block.top!;
      final lineHeight = height / lines.length;
      for (var i = 0; i < lines.length; i++) {
        final line = OcrBlock(
          text: lines[i],
          left: block.left,
          right: block.right,
          top: block.top! + lineHeight * i,
          bottom: block.top! + lineHeight * (i + 1),
        );
        result.addAll(_splitHorizontal(line, lines[i]));
      }
    }
    return result;
  }

  List<OcrBlock> _splitHorizontal(OcrBlock block, String text) {
    final pieces = text
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (pieces.length <= 1) return [block];

    final width = block.right! - block.left!;
    final pieceWidth = width / pieces.length;
    return [
      for (var i = 0; i < pieces.length; i++)
        OcrBlock(
          text: pieces[i],
          left: block.left! + pieceWidth * i,
          right: block.left! + pieceWidth * (i + 1),
          top: block.top,
          bottom: block.bottom,
        ),
    ];
  }

  (double, double) _axisRange(List<double> centers, int index) {
    final center = centers[index];
    final left = index == 0
        ? center - (centers.length > 1 ? (centers[1] - center) / 2 : 100000)
        : (centers[index - 1] + center) / 2;
    final right = index == centers.length - 1
        ? center + (centers.length > 1 ? (center - centers[index - 1]) / 2 : 100000)
        : (center + centers[index + 1]) / 2;
    return (left, right);
  }

  String? _subjectFrom(List<OcrBlock> blocks) {
    final normalized = blocks
        .map((block) => _normalize(block.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    for (final text in normalized) {
      final alias = _aliases[text] ?? text;
      if (_subjects.contains(alias)) return alias;
    }
    return null;
  }

  String _normalize(String value) => value
      .replaceAll(RegExp(r'[\s:：,，。．|｜]'), '')
      .trim();

  int? _weekday(String value) {
    final text = _normalize(value);
    const names = <String, int>{
      '星期一': 1,
      '星期二': 2,
      '星期三': 3,
      '星期四': 4,
      '星期五': 5,
      '週一': 1,
      '週二': 2,
      '週三': 3,
      '週四': 4,
      '週五': 5,
    };
    for (final entry in names.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  int? _periodNumber(String value) {
    final text = _normalize(value);
    final match = RegExp(r'^(?:第)?([1-7])(?:節)?$').firstMatch(text);
    return match == null ? null : int.parse(match.group(1)!);
  }

  bool _hasBounds(OcrBlock block) =>
      block.left != null && block.top != null && block.right != null && block.bottom != null;
  double _centerX(OcrBlock b) => (b.left! + b.right!) / 2;
  double _centerY(OcrBlock b) => (b.top! + b.bottom!) / 2;
  double _top(OcrBlock b) => b.top!;
  double _bottom(OcrBlock b) => b.bottom!;
}
