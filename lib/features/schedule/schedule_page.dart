import 'package:flutter/material.dart';

import 'schedule_import_models.dart';
import 'schedule_repository.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.repository});

  final ScheduleRepository repository;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late DateTime _weekStart;
  late Future<Map<DateTime, List<ScheduleImportItem>>> _weekFuture;

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(DateTime.now());
    _reload();
  }

  void _reload() {
    _weekFuture = _loadWeek(_weekStart);
  }

  Future<Map<DateTime, List<ScheduleImportItem>>> _loadWeek(DateTime monday) async {
    final result = <DateTime, List<ScheduleImportItem>>{};
    for (var i = 0; i < 7; i++) {
      final date = DateTime(monday.year, monday.month, monday.day + i);
      result[date] = await widget.repository.forDate(date);
    }
    return result;
  }

  void _moveWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      _reload();
    });
  }

  DateTime _monday(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  String _date(DateTime date) => '${date.month}/${date.day}';

  String _weekday(DateTime date) => const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1];

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(
        title: const Text('課表'),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                IconButton(onPressed: () => _moveWeek(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(
                    '${_weekStart.year}/${_weekStart.month}/${_weekStart.day} - ${weekEnd.year}/${weekEnd.month}/${weekEnd.day}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(onPressed: () => _moveWeek(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<DateTime, List<ScheduleImportItem>>>(
              future: _weekFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('讀取課表失敗：${snapshot.error}'));
                }
                final days = snapshot.data ?? const <DateTime, List<ScheduleImportItem>>{};
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: days.entries.map((entry) {
                    final items = entry.value;
                    return Card(
                      child: ExpansionTile(
                        initiallyExpanded: entry.key.weekday <= 5,
                        title: Text('週${_weekday(entry.key)}  ${_date(entry.key)}'),
                        subtitle: Text(items.isEmpty ? '沒有課程' : '${items.length} 堂課'),
                        children: items.isEmpty
                            ? const [ListTile(title: Text('這一天沒有課程'))]
                            : items.map((item) {
                                final when = item.period != null
                                    ? '第 ${item.period} 節'
                                    : [item.startTime, item.endTime].whereType<String>().join(' - ');
                                final details = <String>[
                                  if (when.isNotEmpty) when,
                                  if (item.teacher != null) '老師：${item.teacher}',
                                  if (item.location != null) '地點：${item.location}',
                                ].join(' · ');
                                return ListTile(
                                  leading: const Icon(Icons.school_outlined),
                                  title: Text(item.subject),
                                  subtitle: details.isEmpty ? null : Text(details),
                                  trailing: Text(item.childId),
                                );
                              }).toList(growable: false),
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
