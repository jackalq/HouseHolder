import 'package:flutter/material.dart';

import '../../domain/entity_ids.dart';
import 'todo_item.dart';
import 'todo_repository.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.repository});
  final TodoRepository repository;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final _title = TextEditingController();
  late Future<List<HouseholdTodoItem>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _reload() => _future = widget.repository.list(includeDone: true);

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    await widget.repository.add(HouseholdTodoItem(id: EntityIds.generate('todo'), title: title));
    _title.clear();
    if (mounted) setState(_reload);
  }

  Future<void> _setDone(HouseholdTodoItem item, bool value) async {
    await widget.repository.setDone(item.id, value);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('待辦事項')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: TextField(key: const ValueKey('todo-add-input'), controller: _title, decoration: const InputDecoration(labelText: '新增待辦', border: OutlineInputBorder()), onSubmitted: (_) => _add())),
              const SizedBox(width: 8),
              IconButton.filled(key: const ValueKey('todo-add-button'), onPressed: _add, tooltip: '新增', icon: const Icon(Icons.add)),
            ]),
          ),
          Expanded(
            child: FutureBuilder<List<HouseholdTodoItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('讀取待辦失敗：${snapshot.error}'));
                final items = snapshot.data ?? const [];
                if (items.isEmpty) return const Center(child: Text('目前沒有待辦。'));
                return ListView(
                  key: const ValueKey('todo-list'),
                  children: items.map((item) => CheckboxListTile(
                    key: ValueKey('todo-${item.id}'),
                    value: item.done,
                    onChanged: (value) => _setDone(item, value ?? false),
                    title: Text(item.title),
                    subtitle: item.dueDate == null ? null : Text('期限 ${item.dueDate}'),
                  )).toList(growable: false),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
