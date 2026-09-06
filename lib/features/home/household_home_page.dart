import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../assistant/assistant_orchestrator.dart';
import '../../assistant/household_conversation_service.dart';
import '../../assistant/local_llama_gateway.dart';
import '../../platform/ocr_gateway.dart';
import '../model/recommended_model_installer.dart';
import '../schedule/schedule_import_models.dart';
import '../schedule/schedule_page.dart';
import '../schedule/schedule_preview_page.dart';
import '../schedule/timetable_import_page.dart';
import '../shopping/shopping_compare_page.dart';
import '../todo/todo_page.dart';

class HouseholdHomePage extends StatefulWidget {
  const HouseholdHomePage({super.key});

  @override
  State<HouseholdHomePage> createState() => _HouseholdHomePageState();
}

class _HouseholdHomePageState extends State<HouseholdHomePage> {
  final _controller = TextEditingController();
  final _llama = LocalLlamaGateway();
  final _messages = <ConversationMessage>[
    const ConversationMessage(
      role: ConversationRole.assistant,
      text: '我是家庭管家。可以問課表、記錄待辦與採購清單；採購清單也能進一步比價並開啟購買連結。',
    ),
  ];

  late final AssistantOrchestrator _orchestrator = AssistantOrchestrator(_llama);
  late final Future<AppServices> _servicesFuture = AppServices.bootstrap();
  bool _thinking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<HouseholdConversationService> _conversation() async {
    final services = await _servicesFuture;
    return HouseholdConversationService(propose: _orchestrator.propose, executor: services.actions);
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _thinking) return;
    _controller.clear();
    await _run(TextAssistantInput(text), text);
  }

  Future<void> _run(AssistantInput input, String displayText) async {
    setState(() {
      _thinking = true;
      _error = null;
      _messages.add(ConversationMessage(role: ConversationRole.user, text: displayText));
    });
    try {
      final service = await _conversation();
      final result = await service.sendInput(input, displayText);
      if (!mounted) return;
      setState(() => _messages.add(result.assistantMessage));
      if (kDebugMode) debugPrint('HOUSEHOLDER_CHAT_ASSISTANT:${result.assistantMessage.text}');
      if (result.scheduleDraft != null) await _confirmSchedule(result.scheduleDraft!);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '處理失敗：$error';
        _messages.add(ConversationMessage(role: ConversationRole.assistant, text: '這次沒有處理成功：$error'));
      });
      if (kDebugMode) debugPrint('HOUSEHOLDER_CHAT_ERROR:$error');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  Future<void> _confirmSchedule(ScheduleImportDraft draft) async {
    final confirmed = await Navigator.of(context).push<ScheduleImportDraft>(
      MaterialPageRoute(builder: (_) => SchedulePreviewPage(draft: draft)),
    );
    if (!mounted) return;
    if (confirmed == null) {
      setState(() => _messages.add(const ConversationMessage(role: ConversationRole.assistant, text: '課表草稿已取消，沒有寫入家庭資料。')));
      return;
    }
    final services = await _servicesFuture;
    await services.schedules.importConfirmed(confirmed);
    if (!mounted) return;
    setState(() => _messages.add(ConversationMessage(
      role: ConversationRole.assistant,
      text: '課表已儲存 ${confirmed.items.length} 筆。現在可以直接問我今天、明天或指定日期有什麼課。',
    )));
  }

  Future<void> _importTimetable() async {
    final document = await Navigator.of(context).push<OcrDocument>(MaterialPageRoute(builder: (_) => const TimetableImportPage()));
    if (!mounted || document == null) return;
    await _run(
      ImageAssistantInput(ocr: document, context: '這是一張家庭成員的學校課表。請依 HOUSEHOLDER_IMPORT_CONTEXT 產生 schedule.import 草稿。'),
      '請幫我匯入這張課表',
    );
  }

  Future<void> _openSchedule() async {
    final services = await _servicesFuture;
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => SchedulePage(repository: services.schedules)));
  }

  Future<void> _openTodos() async {
    final services = await _servicesFuture;
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TodoPage(repository: services.todos)));
  }

  Future<void> _openShopping() async {
    final services = await _servicesFuture;
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ShoppingComparePage(services: services)));
  }

  void _openModels() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(child: RecommendedModelInstaller(onInstalled: () {})),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HouseHolder 家庭管家'),
        actions: [
          IconButton(key: const ValueKey('todo-open-button'), tooltip: '待辦', onPressed: _openTodos, icon: const Icon(Icons.checklist)),
          IconButton(key: const ValueKey('shopping-open-button'), tooltip: '採購比價', onPressed: _openShopping, icon: const Icon(Icons.shopping_cart_outlined)),
          IconButton(key: const ValueKey('schedule-open-button'), tooltip: '課表', onPressed: _openSchedule, icon: const Icon(Icons.calendar_month_outlined)),
          IconButton(tooltip: '本機模型', onPressed: _openModels, icon: const Icon(Icons.memory_outlined)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                Expanded(child: FilledButton.tonalIcon(key: const ValueKey('timetable-import-button'), onPressed: _thinking ? null : _importTimetable, icon: const Icon(Icons.document_scanner_outlined), label: const Text('拍照匯入課表'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonalIcon(onPressed: _openShopping, icon: const Icon(Icons.price_check_outlined), label: const Text('採購清單／比價'))),
              ]),
            ),
            if (_thinking) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('household-chat-list'),
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final user = message.role == ConversationRole.user;
                  return Align(
                    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: user ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(message.text, key: index == _messages.length - 1 ? const ValueKey('latest-chat-message') : null),
                    ),
                  );
                },
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                key: const ValueKey('household-chat-input'),
                controller: _controller,
                enabled: !_thinking,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: '例如：新增待辦繳學費，或把牛奶加入採購清單',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(key: const ValueKey('household-chat-send'), tooltip: '送出', onPressed: _thinking ? null : _sendText, icon: const Icon(Icons.send)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
