class ScheduleImportItem {
  const ScheduleImportItem({
    required this.id,
    required this.childId,
    required this.dayOfWeek,
    required this.subject,
    required this.validFrom,
    this.startTime,
    this.endTime,
    this.period,
    this.teacher,
    this.location,
    this.note,
  });

  final String id;
  final String childId;
  final int dayOfWeek;
  final String? startTime;
  final String? endTime;
  final int? period;
  final String subject;
  final String? teacher;
  final String? location;
  final String? note;
  final String validFrom;

  factory ScheduleImportItem.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key is required.');
      }
      return value.trim();
    }

    final weekday = json['dayOfWeek'];
    if (weekday is! int || weekday < 1 || weekday > 7) {
      throw const FormatException('dayOfWeek must be 1..7.');
    }

    final item = ScheduleImportItem(
      id: requiredString('id'),
      childId: requiredString('childId'),
      dayOfWeek: weekday,
      subject: requiredString('subject'),
      validFrom: requiredString('validFrom'),
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      period: json['period'] as int?,
      teacher: json['teacher'] as String?,
      location: json['location'] as String?,
      note: json['note'] as String?,
    );

    if (!_isIsoDate(item.validFrom)) {
      throw const FormatException('validFrom must be YYYY-MM-DD.');
    }
    if (item.startTime != null && !_isTime(item.startTime!)) {
      throw const FormatException('startTime must be HH:mm.');
    }
    if (item.endTime != null && !_isTime(item.endTime!)) {
      throw const FormatException('endTime must be HH:mm.');
    }
    return item;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'childId': childId,
        'dayOfWeek': dayOfWeek,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (period != null) 'period': period,
        'subject': subject,
        if (teacher != null) 'teacher': teacher,
        if (location != null) 'location': location,
        if (note != null) 'note': note,
        'validFrom': validFrom,
      };

  static bool _isIsoDate(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) && DateTime.tryParse(value) != null;

  static bool _isTime(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
}

class ScheduleImportDraft {
  const ScheduleImportDraft({required this.items, this.warnings = const []});

  final List<ScheduleImportItem> items;
  final List<String> warnings;

  factory ScheduleImportDraft.fromPayload(Map<String, Object?> payload) {
    final rawItems = payload['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('schedule.import payload.items is required.');
    }

    final items = rawItems.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Each schedule item must be an object.');
      }
      return ScheduleImportItem.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList(growable: false);

    final warnings = (payload['warnings'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
    return ScheduleImportDraft(items: items, warnings: warnings);
  }
}
