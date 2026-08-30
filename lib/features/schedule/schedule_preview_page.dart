import 'package:flutter/material.dart';

import 'schedule_import_models.dart';

class SchedulePreviewPage extends StatelessWidget {
  const SchedulePreviewPage({super.key, required this.draft});

  final ScheduleImportDraft draft;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('確認課表')),
      body: SafeArea(
        child: Column(
          children: [
            if (draft.warnings.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(draft.warnings.join('\n')),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: draft.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = draft.items[index];
                  final time = item.startTime != null
                      ? '${item.startTime}${item.endTime != null ? '–${item.endTime}' : ''}'
                      : item.period != null
                          ? '第 ${item.period} 節'
                          : '時間未提供';
                  return Card(
                    child: ListTile(
                      title: Text(item.subject),
                      subtitle: Text(
                        '星期${_weekday(item.dayOfWeek)} · $time\n'
                        '孩子：${item.childId}'
                        '${item.teacher != null ? ' · ${item.teacher}' : ''}'
                        '${item.location != null ? ' · ${item.location}' : ''}',
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('確認寫入'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekday(int day) => const ['一', '二', '三', '四', '五', '六', '日'][day - 1];
}
