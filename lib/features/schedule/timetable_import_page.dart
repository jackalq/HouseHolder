import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../platform/ocr_gateway.dart';
import 'timetable_grid_parser.dart';

class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({super.key});

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  final _picker = ImagePicker();
  final _ocr = OcrGateway();
  final _gridParser = const TimetableGridParser();
  final _textController = TextEditingController();
  final _childController = TextEditingController();
  final _validFromController = TextEditingController();
  final _validUntilController = TextEditingController();

  XFile? _image;
  OcrDocument? _document;
  TimetableGridResult? _grid;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    _childController.dispose();
    _validFromController.dispose();
    _validUntilController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _error = null;
      _document = null;
      _grid = null;
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
      final grid = _gridParser.parse(document);
      if (!mounted) return;
      _textController.text = document.fullText;
      setState(() {
        _document = document;
        _grid = grid;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueToParse() {
    final text = _textController.text.trim();
    final childId = _childController.text.trim();
    final validFrom = _validFromController.text.trim();
    final validUntilText = _validUntilController.text.trim();

    if (text.isEmpty) {
      _showError('請先取得或輸入課表文字。');
      return;
    }
    if (childId.isEmpty) {
      _showError('請填寫這張課表屬於哪位孩子。');
      return;
    }
    if (!_isIsoDate(validFrom)) {
      _showError('請填寫有效起日，格式為 YYYY-MM-DD。');
      return;
    }
    if (validUntilText.isNotEmpty && !_isIsoDate(validUntilText)) {
      _showError('有效迄日格式必須是 YYYY-MM-DD。');
      return;
    }
    if (validUntilText.isNotEmpty && validUntilText.compareTo(validFrom) < 0) {
      _showError('有效迄日不能早於有效起日。');
      return;
    }

    final gridText = _grid?.usable == true
        ? _grid!.toPromptText()
        : 'STRUCTURED_TIMETABLE_GRID:\n(unavailable; use OCR cautiously)';
    final reviewed = OcrDocument(
      fullText: '''
HOUSEHOLDER_IMPORT_CONTEXT:
childId=$childId
validFrom=$validFrom
validUntil=${validUntilText.isEmpty ? 'null' : validUntilText}
$gridText
OCR_TEXT:
$text
'''.trim(),
      blocks: _document?.blocks ?? const [],
    );
    Navigator.of(context).pop(reviewed);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isIsoDate(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      DateTime.tryParse(value) != null;

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
            const Text('先用 OCR 座標還原星期 × 節次表格，再交給本機模型做文字修正；孩子與學期日期由你提供。'),
            const SizedBox(height: 16),
            TextField(
              controller: _childController,
              decoration: const InputDecoration(
                labelText: '孩子 ID / 名稱 *',
                hintText: '例如：小明',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _validFromController,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: '有效起日 *',
                      hintText: '2026-09-01',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _validUntilController,
                    keyboardType: TextInputType.datetime,
                    decoration: const InputDecoration(
                      labelText: '有效迄日',
                      hintText: '2027-01-20',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
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
              const Text('正在辨識並還原課表格線…'),
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
            if (_grid != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _grid!.usable
                            ? '表格定位：已找到 ${_grid!.cells.length} 個課程格'
                            : '表格定位不足，將保留 OCR 文字供人工修正',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (_grid!.warnings.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(_grid!.warnings.join('；')),
                      ],
                      if (_grid!.usable) ...[
                        const SizedBox(height: 8),
                        Text(
                          _grid!.cells
                              .map((c) => '星期${c.dayOfWeek} 第${c.period}節 ${c.subject}')
                              .join('\n'),
                          key: const ValueKey('timetable-grid-preview'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _textController,
              minLines: 10,
              maxLines: 20,
              decoration: const InputDecoration(
                labelText: 'OCR 原文（必要時可修正）',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_document != null) ...[
              const SizedBox(height: 8),
              Text('辨識到 ${_document!.blocks.length} 個帶座標文字區塊'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _continueToParse,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('確認並產生課表草稿'),
            ),
          ],
        ),
      ),
    );
  }
}
