import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../platform/ocr_gateway.dart';

class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({super.key});

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  final _picker = ImagePicker();
  final _ocr = OcrGateway();
  final _textController = TextEditingController();

  XFile? _image;
  OcrDocument? _document;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _error = null;
      _document = null;
    });

    final image = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null || !mounted) return;

    setState(() {
      _image = image;
      _busy = true;
    });

    try {
      final document = await _ocr.recognizeImage(image.path);
      if (!mounted) return;
      _textController.text = document.fullText;
      setState(() => _document = document);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueToParse() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先取得或輸入課表文字。')),
      );
      return;
    }

    final reviewed = OcrDocument(
      fullText: text,
      blocks: _document?.blocks ?? const [],
    );
    Navigator.of(context).pop(reviewed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('匯入課表')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '拍攝或選擇課表',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('OCR 會在 Android 裝置上執行。辨識後請先檢查文字，再交給管家解析。'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('相簿'),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('正在辨識課表…'),
            ],
            if (_image != null) ...[
              const SizedBox(height: 18),
              Text(
                '圖片：${_image!.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _textController,
              minLines: 10,
              maxLines: 20,
              decoration: const InputDecoration(
                labelText: 'OCR 結果（可修正）',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_document != null) ...[
              const SizedBox(height: 8),
              Text('辨識到 ${_document!.blocks.length} 個文字區塊'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _continueToParse,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('確認文字並繼續解析'),
            ),
          ],
        ),
      ),
    );
  }
}
