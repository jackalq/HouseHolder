import 'package:flutter/material.dart';

import 'app_services.dart';
import 'assistant/assistant_orchestrator.dart';
import 'assistant/family_action.dart';
import 'assistant/local_llama_gateway.dart';
import 'features/schedule/schedule_preview_page.dart';
import 'features/schedule/timetable_import_page.dart';
import 'platform/ocr_gateway.dart';
import 'platform/speech_gateway.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HouseHolderApp());
}

class HouseHolderApp extends StatelessWidget {
  const HouseHolderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HouseHolder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _speech = SpeechGateway();
  final _llama = LocalLlamaGateway();
  final _actionParser = const FamilyActionParser();

  late final AssistantOrchestrator _assistant = AssistantOrchestrator(_llama);
  late final Future<AppServices> _servicesFuture;
  late Future<LocalModelStatus> _modelStatusFuture;

  bool _listening = false;
  bool _thinking = false;
  String? _status;
  String? _lastDraft;

  @override
  void initState() {
    super.initState();
    _servicesFuture = AppServices.bootstrap();
    _modelStatusFuture = _llama.modelStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openTimetableImport() async {
    final document = await Navigator.of(context).push<OcrDocument>(
      MaterialPageRoute(builder: (_) => const TimetableImportPage()),
    );
    if (!mounted || document == null || document.fullText.trim().isEmpty) return;

    _controller.text = document.fullText;
    await _propose(
      ImageAssistantInput(
        ocr: document,
        context: '這是一張家庭成員的學校課表。請產生 schedule.import 草稿。',
      ),
    );
  }

  Future<void> _recognizeSpeech() async {
    if (_listening || _thinking) return;
    setState(() {
      _listening = true;
      _status = '正在聽…';
    });

    try {
      final onDeviceAvailable = await _speech.isOnDeviceAvailable();
      final transcript = await _speech.recognizeOnce(
        onDeviceOnly: onDeviceAvailable,
      );
      if (!mounted) return;
      _controller.text = transcript.text;
      setState(() {
        _status = onDeviceAvailable
            ? '語音已由裝置端辨識，正在交給管家理解。'
            : '已使用系統語音辨識服務，正在交給管家理解。';
      });
      await _propose(SpeechAssistantInput(transcript.text));
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '語音辨識失敗：$error');
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _submitText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _thinking) return;
    await _propose(TextAssistantInput(text));
  }

  Future<void> _propose(AssistantInput input) async {
    if (_thinking) return;
    setState(() {
      _thinking = true;
      _lastDraft = null;
      _status = '管家正在產生結構化動作…';
    });

    try {
      final draft = await _assistant.propose(input);
      if (!mounted) return;
      setState(() => _lastDraft = draft.rawJson);
      await _handleDraft(draft.rawJson);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '處理失敗：$error');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  Future<void> _handleDraft(String rawJson) async {
    final action = _actionParser.parse(rawJson);
    final services = await _servicesFuture;
    final result = await services.actions.execute(action);
    if (!mounted) return;

    final scheduleDraft = result.scheduleDraft;
    if (scheduleDraft == null) {
      setState(() => _status = result.message);
      return;
    }

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SchedulePreviewPage(draft: scheduleDraft),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _status = '課表草稿已取消，沒有寫入家庭資料。');
      return;
    }

    setState(() => _status = '正在寫入課表與 ChangeEvent…');
    await services.schedules.importConfirmed(scheduleDraft);
    if (!mounted) return;
    setState(() {
      _status = '課表已寫入 ${scheduleDraft.items.length} 筆；之後可直接詢問明天有什麼課。';
    });
  }

  Future<void> _showShopping() async {
    try {
      final services = await _servicesFuture;
      final result = await services.actions.execute(
        const FamilyAction(
          type: 'shopping.list',
          requiresConfirmation: false,
          payload: {'includeDone': true},
        ),
      );
      if (mounted) setState(() => _status = result.message);
    } catch (error) {
      if (mounted) setState(() => _status = '讀取購物清單失敗：$error');
    }
  }

  Future<void> _showTodos() async {
    try {
      final services = await _servicesFuture;
      final result = await services.actions.execute(
        const FamilyAction(
          type: 'todo.list',
          requiresConfirmation: false,
          payload: {'includeDone': true},
        ),
      );
      if (mounted) setState(() => _status = result.message);
    } catch (error) {
      if (mounted) setState(() => _status = '讀取待辦失敗：$error');
    }
  }

  void _refreshModelStatus() {
    setState(() => _modelStatusFuture = _llama.modelStatus());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HouseHolder'),
        actions: [
          IconButton(
            tooltip: '重新檢查本機模型',
            onPressed: _refreshModelStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '家庭管家',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('Android MVP：課表、語音、購物與待辦。'),
              const SizedBox(height: 12),
              _ModelStatusCard(status: _modelStatusFuture),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _thinking ? null : _openTimetableImport,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍課表'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _listening || _thinking ? null : _recognizeSpeech,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                    label: Text(_listening ? '辨識中…' : '語音'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _showShopping,
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('購物清單'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _showTodos,
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('待辦'),
                  ),
                ],
              ),
              if (_thinking) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(),
              ],
              if (_status != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_status!),
                  ),
                ),
              ],
              if (_lastDraft != null) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('FamilyAction 草稿'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(_lastDraft!),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: '例如：明天有什麼課？／記得買牛奶／新增待辦：繳學費',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _thinking ? null : _submitText,
                    icon: const Icon(Icons.send),
                  ),
                ),
                onSubmitted: (_) => _submitText(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard({required this.status});

  final Future<LocalModelStatus> status;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LocalModelStatus>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('正在檢查本機 Llama 模型…'),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('無法取得模型狀態：${snapshot.error}'),
            ),
          );
        }
        final model = snapshot.data!;
        if (!model.ready) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('本機模型尚未安裝。模型路徑：${model.modelPath}'),
            ),
          );
        }
        final mb = model.modelBytes / (1024 * 1024);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('本機 Llama 已就緒（${mb.toStringAsFixed(0)} MB）'),
          ),
        );
      },
    );
  }
}
