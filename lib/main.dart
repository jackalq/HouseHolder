import 'package:flutter/material.dart';

import 'features/schedule/timetable_import_page.dart';
import 'platform/speech_gateway.dart';

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

  bool _listening = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openTimetableImport() async {
    final ocrText = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const TimetableImportPage()),
    );
    if (!mounted || ocrText == null || ocrText.trim().isEmpty) return;

    setState(() {
      _controller.text = '這是一張課表，請解析以下內容：\n\n$ocrText';
      _status = 'OCR 已完成，下一步會交給 Schedule Import Skill 解析。';
    });
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
      setState(() {
        _controller.text = transcript.text;
        _status = onDeviceAvailable
            ? '語音已由裝置端辨識。'
            : '此裝置沒有本機語音服務，已使用系統語音辨識服務。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '語音辨識失敗：$error');
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _submitText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _status = '已收到輸入。下一步接上 AssistantOrchestrator / Local Llama。';
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
                    onPressed: _openTimetableImport,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍課表'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _listening ? null : _recognizeSpeech,
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                    label: Text(_listening ? '辨識中…' : '語音'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _status = '購物清單功能正在接 Repository。'),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('購物清單'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _status = '待辦功能正在接 Repository。'),
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('待辦'),
                  ),
                ],
              ),
              if (_status != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_status!),
                  ),
                ),
              ],
              const Spacer(),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: '例如：明天有什麼課？',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _submitText,
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
