import 'package:flutter/material.dart';

import 'app_services.dart';
import 'assistant/assistant_orchestrator.dart';
import 'assistant/family_action.dart';
import 'assistant/local_llama_gateway.dart';
import 'features/schedule/schedule_import_models.dart';
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
  bool _modelBusy = false;
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

    final confirmedDraft = await Navigator.of(context).push<ScheduleImportDraft>(
      MaterialPageRoute(
        builder: (_) => SchedulePreviewPage(draft: scheduleDraft),
      ),
    );
    if (!mounted) return;
    if (confirmedDraft == null) {
      setState(() => _status = '課表草稿已取消，沒有寫入家庭資料。');
      return;
    }

    setState(() => _status = '正在寫入課表與 ChangeEvent…');
    await services.schedules.importConfirmed(confirmedDraft);
    if (!mounted) return;
    setState(() {
      _status = '課表已寫入 ${confirmedDraft.items.length} 筆；之後可直接詢問明天有什麼課。';
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

  Future<void> _pickModelFile() async {
    if (_modelBusy) return;
    setState(() {
      _modelBusy = true;
      _status = '請選擇 Llama 3.2 3B 的 ExecuTorch .pte 檔案。';
    });
    try {
      final installed = await _llama.pickModelFile();
      if (!mounted) return;
      setState(() {
        _status = installed ? '模型檔已複製到 App 私有儲存空間。' : '已取消選擇模型檔。';
      });
      _refreshModelStatus();
    } catch (error) {
      if (mounted) setState(() => _status = '模型檔安裝失敗：$error');
    } finally {
      if (mounted) setState(() => _modelBusy = false);
    }
  }

  Future<void> _pickTokenizerFile() async {
    if (_modelBusy) return;
    setState(() {
      _modelBusy = true;
      _status = '請選擇對應的 tokenizer 檔案。';
    });
    try {
      final installed = await _llama.pickTokenizerFile();
      if (!mounted) return;
      setState(() => _status = installed ? 'Tokenizer 已安裝。' : '已取消選擇 tokenizer。');
      _refreshModelStatus();
    } catch (error) {
      if (mounted) setState(() => _status = 'Tokenizer 安裝失敗：$error');
    } finally {
      if (mounted) setState(() => _modelBusy = false);
    }
  }

  Future<void> _deleteModelPack() async {
    if (_modelBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除本機模型？'),
        content: const Text('只會刪除 App 私有空間中的模型與 tokenizer，不會刪除家庭資料。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _modelBusy = true);
    try {
      await _llama.deleteModelPack();
      if (!mounted) return;
      setState(() => _status = '本機模型已刪除。');
      _refreshModelStatus();
    } catch (error) {
      if (mounted) setState(() => _status = '刪除模型失敗：$error');
    } finally {
      if (mounted) setState(() => _modelBusy = false);
    }
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '家庭管家',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('Android MVP：課表、語音、購物與待辦。'),
            const SizedBox(height: 12),
            _ModelStatusCard(
              status: _modelStatusFuture,
              busy: _modelBusy,
              onPickModel: _pickModelFile,
              onPickTokenizer: _pickTokenizerFile,
              onDelete: _deleteModelPack,
            ),
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
            if (_thinking || _modelBusy) ...[
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
            const SizedBox(height: 24),
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
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard({
    required this.status,
    required this.busy,
    required this.onPickModel,
    required this.onPickTokenizer,
    required this.onDelete,
  });

  final Future<LocalModelStatus> status;
  final bool busy;
  final VoidCallback onPickModel;
  final VoidCallback onPickTokenizer;
  final VoidCallback onDelete;

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
        final mb = model.modelBytes / (1024 * 1024);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.ready
                      ? '本機 Llama 已就緒（${mb.toStringAsFixed(0)} MB）'
                      : '本機 Llama 尚未就緒',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (!model.ready) ...[
                  const SizedBox(height: 6),
                  Text(
                    model.modelBytes > 0
                        ? '模型檔已存在，尚缺 tokenizer。'
                        : '請安裝 .pte 模型與 tokenizer。',
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: busy ? null : onPickModel,
                      child: Text(model.modelBytes > 0 ? '更換 .pte' : '選擇 .pte'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : onPickTokenizer,
                      child: Text(
                        model.tokenizerPath != null ? '更換 tokenizer' : '選擇 tokenizer',
                      ),
                    ),
                    if (model.modelBytes > 0 || model.tokenizerPath != null)
                      TextButton(
                        onPressed: busy ? null : onDelete,
                        child: const Text('刪除模型'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
