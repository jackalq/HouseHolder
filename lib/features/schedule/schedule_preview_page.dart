import 'package:flutter/material.dart';

import 'schedule_import_models.dart';

class SchedulePreviewPage extends StatefulWidget {
  const SchedulePreviewPage({super.key, required this.draft});

  final ScheduleImportDraft draft;

  @override
  State<SchedulePreviewPage> createState() => _SchedulePreviewPageState();
}

class _SchedulePreviewPageState extends State<SchedulePreviewPage> {
  late final List<ScheduleImportItem> _items = [...widget.draft.items];

  Future<void> _editItem(int index) async {
    final edited = await showDialog<ScheduleImportItem>(
      context: context,
      builder: (context) => _ScheduleItemEditor(item: _items[index]),
    );
    if (edited == null || !mounted) return;
    setState(() => _items[index] = edited);
  }

  void _deleteItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _confirm() {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要保留一筆課程。')),
      );
      return;
    }
    Navigator.of(context).pop(
      ScheduleImportDraft(items: List.unmodifiable(_items), warnings: widget.draft.warnings),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('確認課表')),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.draft.warnings.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(widget.draft.warnings.join('\n')),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final time = item.startTime != null
                      ? '${item.startTime}${item.endTime != null ? '–${item.endTime}' : ''}'
                      : item.period != null
                          ? '第 ${item.period} 節'
                          : '時間未提供';
                  return Card(
                    child: ListTile(
                      onTap: () => _editItem(index),
                      title: Text(item.subject),
                      subtitle: Text(
                        '星期${_weekday(item.dayOfWeek)} · $time\n'
                        '孩子：${item.childId}'
                        '${item.teacher != null ? ' · ${item.teacher}' : ''}'
                        '${item.location != null ? ' · ${item.location}' : ''}\n'
                        '有效：${item.validFrom}${item.validUntil != null ? ' ～ ${item.validUntil}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _editItem(index);
                          if (value == 'delete') _deleteItem(index);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('編輯')),
                          PopupMenuItem(value: 'delete', child: Text('刪除')),
                        ],
                      ),
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
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirm,
                      child: Text('確認寫入 (${_items.length})'),
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

class _ScheduleItemEditor extends StatefulWidget {
  const _ScheduleItemEditor({required this.item});

  final ScheduleImportItem item;

  @override
  State<_ScheduleItemEditor> createState() => _ScheduleItemEditorState();
}

class _ScheduleItemEditorState extends State<_ScheduleItemEditor> {
  late final TextEditingController _child = TextEditingController(text: widget.item.childId);
  late final TextEditingController _subject = TextEditingController(text: widget.item.subject);
  late final TextEditingController _period = TextEditingController(text: widget.item.period?.toString() ?? '');
  late final TextEditingController _start = TextEditingController(text: widget.item.startTime ?? '');
  late final TextEditingController _end = TextEditingController(text: widget.item.endTime ?? '');
  late final TextEditingController _teacher = TextEditingController(text: widget.item.teacher ?? '');
  late final TextEditingController _location = TextEditingController(text: widget.item.location ?? '');
  late final TextEditingController _validFrom = TextEditingController(text: widget.item.validFrom);
  late final TextEditingController _validUntil = TextEditingController(text: widget.item.validUntil ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.item.note ?? '');
  late int _weekday = widget.item.dayOfWeek;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _child,
      _subject,
      _period,
      _start,
      _end,
      _teacher,
      _location,
      _validFrom,
      _validUntil,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  void _save() {
    try {
      final periodText = _period.text.trim();
      final edited = ScheduleImportItem.fromJson({
        'id': widget.item.id,
        'childId': _child.text.trim(),
        'dayOfWeek': _weekday,
        'subject': _subject.text.trim(),
        'validFrom': _validFrom.text.trim(),
        'validUntil': _optional(_validUntil),
        'startTime': _optional(_start),
        'endTime': _optional(_end),
        'period': periodText.isEmpty ? null : int.tryParse(periodText),
        'teacher': _optional(_teacher),
        'location': _optional(_location),
        'note': _optional(_note),
      });
      Navigator.of(context).pop(edited);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯課程'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _child, decoration: const InputDecoration(labelText: '孩子 ID / 名稱')),
              TextField(controller: _subject, decoration: const InputDecoration(labelText: '科目')),
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: '星期'),
                items: List.generate(
                  7,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('星期${const ['一', '二', '三', '四', '五', '六', '日'][index]}'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) setState(() => _weekday = value);
                },
              ),
              TextField(controller: _period, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '節次')),
              Row(
                children: [
                  Expanded(child: TextField(controller: _start, decoration: const InputDecoration(labelText: '開始 HH:mm'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _end, decoration: const InputDecoration(labelText: '結束 HH:mm'))),
                ],
              ),
              TextField(controller: _teacher, decoration: const InputDecoration(labelText: '老師')),
              TextField(controller: _location, decoration: const InputDecoration(labelText: '地點')),
              TextField(controller: _validFrom, decoration: const InputDecoration(labelText: '有效起日 YYYY-MM-DD')),
              TextField(controller: _validUntil, decoration: const InputDecoration(labelText: '有效迄日 YYYY-MM-DD')),
              TextField(controller: _note, decoration: const InputDecoration(labelText: '備註')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('套用')),
      ],
    );
  }
}
