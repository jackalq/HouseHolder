import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'assistant/assistant_orchestrator.dart';
import 'assistant/family_action.dart';
import 'assistant/local_llama_gateway.dart';
import 'features/schedule/schedule_import_models.dart';
import 'features/schedule/schedule_preview_page.dart';
import 'features/schedule/schedule_repository.dart';
import 'features/schedule/timetable_import_page.dart';
import 'platform/ocr_gateway.dart';
import 'platform/speech_gateway.dart';
import 'storage/device_identity.dart';
import 'storage/json_repository.dart';

void main() {
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
  final _assistant = AssistantOrchestrator(LocalLlamaGateway());
  final _actionParser = const FamilyActionParser();

  bool _listening = false;
  bool _thinking = false;
  String? _status;
  String? _lastDraft;

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
        context: '這是一張家庭成員的學校課表。請使用 schedule-import skill 產生草稿。',
      ),
    );
  }

  Future<void> _recognizeSpeech() async {
    if (_listening) return;
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
      _status = '管家正在產生結構化草稿…';
    });

    try {
      final draft = await _assistant.propose(input);
      if (!mounted) return;
      setState(() => _lastDraft = draft.rawJson);
      await _handleDraft(draft.rawJson);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '本機 Llama 尚未就緒或推論失敗：$error');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  Future<void> _handleDraft(String rawJson) async {
    final action = _actionParser.parse(rawJson);

    if (action.type != 'schedule.import') {
      if (!mounted) return;
      setState(() {
        _status = '已驗證 FamilyAction：${action.type}。目前 MVP 先完成 schedule.import 寫入流程。';
      });
      return;
    }

    if (!action.requiresConfirmation) {
      throw const FormatException('schedule.import must require confirmation.');
    }

    final scheduleDraft = ScheduleImportDraft.fromPayload(action.payload);
    if (!mounted) return;

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

    setState(() => _status = '正在寫入本機家庭資料與變更事件…');
    final appDocuments = await getApplicationDocumentsDirectory();
    final documents = JsonDocumentRepository(
      Directory('${appDocuments.path}/HouseHolder'),
    );
    final repository = ScheduleRepository(
      documents: documents,
      deviceIdentity: DeviceIdentity(documents),
    );
    await repository.importConfirmed(scheduleDraft);

    if (!mounted) return;
    setState(() {
      _status = '課表已確認並寫入 ${scheduleDraft.items.length} 筆；ChangeEvent 也已建立。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HouseHolder')),
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
              const SizedBox(height: 24),
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
                    onPressed: () => setState(() => _status = '購物清單功能下一步接 JSON Repository。'),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('購物清單'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _status = '待辦功能下一步接 JSON Repository。'),
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
                    child: Text(_status!),
                  ),
                ),
              ],
              if (_lastDraft != null) ...[
                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        child: SelectableText(_lastDraft!),
                      ),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: '例如：明天有什麼課？',
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
