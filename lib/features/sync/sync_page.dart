import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../sync/android_saf_sync_transport.dart';
import '../../sync/conflict_inbox.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late Future<SyncTreeStatus> _treeStatus;
  late Future<List<SyncConflict>> _conflicts;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _treeStatus = widget.services.syncTransport.status();
    _conflicts = widget.services.conflicts.listOpen();
  }

  Future<void> _pickFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selected = await widget.services.syncTransport.pickTree();
      if (!mounted) return;
      setState(() {
        _message = selected
            ? '共享資料夾已授權。另一支手機請選擇同一個 Google Drive 共享資料夾。'
            : '已取消選擇資料夾。';
        _refresh();
      });
    } catch (error) {
      if (mounted) setState(() => _message = '選擇共享資料夾失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '正在同步家庭變更…';
    });
    try {
      final report = await widget.services.sync.sync();
      if (!mounted) return;
      setState(() {
        _message = '同步完成：上傳 ${report.pushedFiles} 個事件檔、收到 ${report.remoteEvents} 個新事件、'
            '套用 ${report.appliedEvents} 個、衝突 ${report.conflicts} 個。';
        _refresh();
      });
    } catch (error) {
      if (mounted) setState(() => _message = '同步失敗：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await widget.services.syncTransport.clearTree();
    if (!mounted) return;
    setState(() {
      _message = '已移除 HouseHolder 對共享資料夾的持久授權。';
      _refresh();
    });
  }

  Future<void> _keepLocal(SyncConflict conflict) async {
    await widget.services.conflicts.keepLocal(conflict);
    if (!mounted) return;
    setState(() {
      _message = '衝突已保留本機版本並結案。';
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家庭同步')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '共享資料夾',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '先在 Google Drive 建立並分享一個 HouseHolder 資料夾。兩支 Android 手機都用下方按鈕選擇同一個資料夾。'
              'HouseHolder 只取得你選取的資料夾樹讀寫權限。',
            ),
            const SizedBox(height: 12),
            FutureBuilder<SyncTreeStatus>(
              future: _treeStatus,
              builder: (context, snapshot) {
                final value = snapshot.data;
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value?.configured == true
                              ? '已連接：${value?.displayName ?? '共享資料夾'}'
                              : '尚未選擇共享資料夾',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: _busy ? null : _pickFolder,
                              child: Text(value?.configured == true ? '更換資料夾' : '選擇共享資料夾'),
                            ),
                            FilledButton(
                              onPressed: _busy || value?.configured != true ? null : _syncNow,
                              child: const Text('立即同步'),
                            ),
                            if (value?.configured == true)
                              TextButton(
                                onPressed: _busy ? null : _disconnect,
                                child: const Text('移除授權'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
            ],
            const SizedBox(height: 24),
            const Text(
              '同步衝突',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<SyncConflict>>(
              future: _conflicts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final conflicts = snapshot.data ?? const [];
                if (conflicts.isEmpty) return const Text('目前沒有未處理衝突。');
                return Column(
                  children: conflicts.map((conflict) {
                    final fields = conflict.conflictingFields.isEmpty
                        ? ''
                        : '\n欄位：${conflict.conflictingFields.join('、')}';
                    return Card(
                      child: ListTile(
                        title: Text('${conflict.entityType} · ${conflict.entityId}'),
                        subtitle: Text('${conflict.reason}$fields'),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _keepLocal(conflict),
                          child: const Text('保留本機'),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
