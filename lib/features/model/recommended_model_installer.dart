import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../assistant/local_llama_gateway.dart';

class RecommendedModelInstaller extends StatefulWidget {
  const RecommendedModelInstaller({
    super.key,
    required this.onInstalled,
  });

  final VoidCallback onInstalled;

  @override
  State<RecommendedModelInstaller> createState() => _RecommendedModelInstallerState();
}

class _RecommendedModelInstallerState extends State<RecommendedModelInstaller> {
  final _llama = LocalLlamaGateway();
  final _qwen = _QwenModelPackDownloader();
  Timer? _pollTimer;
  RecommendedModelDownloadStatus? _downloadStatus;
  late Future<List<LocalModelStatus>> _modelsFuture;
  bool _busy = false;
  bool _qwenBusy = false;
  bool _testBusy = false;
  double? _qwenProgress;
  String _qwenStage = 'idle';
  String? _error;
  String? _qwenError;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _modelsFuture = _llama.availableModels();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _refreshModels() {
    if (!mounted) return;
    setState(() => _modelsFuture = _llama.availableModels());
    widget.onInstalled();
  }

  Future<void> _start() async {
    if (_busy || _qwenBusy || _testBusy) return;

    RecommendedModelInfo info;
    try {
      info = await _llama.recommendedModelInfo();
    } catch (error) {
      if (mounted) setState(() => _error = '無法取得推薦模型資訊：$error');
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一鍵下載推薦模型'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('下載大小：約 ${_gb(info.totalBytes)} GB'),
              Text('建議裝置記憶體：${_gb(info.recommendedRamBytes)} GB 以上'),
              Text('來源：${info.source}'),
              const SizedBox(height: 12),
              const Text('會直接下載 .pte 與 tokenizer 到 App 私有空間，完成後自動檢查 SHA-256。建議使用 Wi-Fi，下載期間請保持 App 開啟。'),
              const SizedBox(height: 10),
              const Text('此模型使用 Llama 3.2 Community License。HouseHolder 不把模型權重包進 APK，而是從模型提供者來源下載。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _openExternal(info.sourceUrl),
            child: const Text('模型來源'),
          ),
          TextButton(
            onPressed: () => _openExternal(info.licenseUrl),
            child: const Text('Llama 授權'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('下載並安裝'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _downloadStatus = const RecommendedModelDownloadStatus(
        downloading: true,
        stage: 'starting',
        downloadedBytes: 0,
        totalBytes: 1,
      );
    });

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());

    LocalModelStatus status;
    try {
      await _llama.downloadRecommendedModelPack();
      status = await _llama.selectModel(LocalLlamaGateway.llamaModelId);
    } catch (error) {
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _busy = false;
        _error = '推薦模型下載失敗：$error';
      });
      return;
    }

    if (!mounted) return;
    _pollTimer?.cancel();
    setState(() {
      _busy = false;
      _downloadStatus = null;
      _error = null;
    });
    _refreshModels();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status.ready ? 'Llama 模型已下載、驗證並設為目前模型。' : '下載完成，但模型狀態仍未就緒。',
        ),
      ),
    );
  }

  Future<void> _startQwen() async {
    if (_busy || _qwenBusy || _testBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安裝 Qwen2.5 1.5B Q4_K_M'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Qwen2.5-1.5B-Instruct-Q4_K_M',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text('模型格式：GGUF / Q4_K_M，約 1.12 GB'),
              Text('Tokenizer：Qwen 官方 Qwen2.5-1.5B-Instruct tokenizer.json'),
              Text('授權：Apache-2.0'),
              SizedBox(height: 12),
              Text('GGUF 本身已包含 llama.cpp 所需 tokenizer metadata；另外保存官方 tokenizer.json，供工具與未來 runtime 共用。'),
              SizedBox(height: 10),
              Text('安裝完成後會自動切換到 llama.cpp runtime，可直接在下方按「測試推理」驗證本機推論。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _openExternal(_QwenModelPackDownloader.sourceUrl),
            child: const Text('模型來源'),
          ),
          TextButton(
            onPressed: () => _openExternal(_QwenModelPackDownloader.tokenizerSourceUrl),
            child: const Text('Tokenizer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('下載並安裝'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _qwenBusy = true;
      _qwenError = null;
      _qwenProgress = null;
      _qwenStage = '準備下載…';
    });

    try {
      final installed = await _qwen.downloadAndInstall(
        onProgress: (stage, downloaded, total) {
          if (!mounted) return;
          setState(() {
            _qwenStage = stage;
            _qwenProgress = total <= 0 ? null : downloaded / total;
          });
        },
      );
      final selected = await _llama.selectModel(LocalLlamaGateway.qwenModelId);
      if (!mounted) return;
      setState(() {
        _qwenBusy = false;
        _qwenProgress = 1;
        _qwenStage = '模型已安裝並啟用';
      });
      _refreshModels();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Qwen 已啟用（${selected.runtime}）：${installed.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _qwenBusy = false;
        _qwenError = 'Qwen 模型下載或啟用失敗：$error';
        _qwenStage = '安裝失敗';
      });
    }
  }

  Future<void> _selectModel(LocalModelStatus model) async {
    if (!model.ready || _busy || _qwenBusy || _testBusy) return;
    try {
      final selected = await _llama.selectModel(model.modelId);
      if (!mounted) return;
      setState(() => _testResult = null);
      _refreshModels();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('目前模型：${selected.modelName}（${selected.runtime}）')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '切換模型失敗：$error');
    }
  }

  Future<void> _testInference() async {
    if (_testBusy || _busy || _qwenBusy) return;
    setState(() {
      _testBusy = true;
      _testResult = '本機模型推理中…';
    });
    try {
      final status = await _llama.modelStatus();
      if (!status.ready) throw StateError('尚未安裝可用模型');
      final output = await _llama.generate(
        '這是 HouseHolder 本機推理測試。請只用一句簡短中文回答：本機推理正常。',
        maxTokens: 32,
        temperature: 0,
      );
      if (output.trim().isEmpty) throw StateError('模型回傳空白內容');
      if (!mounted) return;
      setState(() => _testResult = '推理完成｜${status.modelName}｜${status.runtime}\n$output');
    } catch (error) {
      if (!mounted) return;
      setState(() => _testResult = '推理失敗：$error');
    } finally {
      if (mounted) setState(() => _testBusy = false);
    }
  }

  Future<void> _poll() async {
    if (!_busy) return;
    try {
      final status = await _llama.recommendedDownloadStatus();
      if (!mounted) return;
      setState(() => _downloadStatus = status);
    } catch (_) {
      // The primary download call owns the final error; polling is best-effort.
    }
  }

  Future<void> _openExternal(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _stageLabel(String stage) {
    switch (stage) {
      case 'starting':
        return '準備下載…';
      case 'model':
        return '下載 .pte 模型…';
      case 'tokenizer':
        return '下載 tokenizer…';
      case 'verifying_model':
        return '驗證模型 SHA-256…';
      case 'verifying_tokenizer':
        return '驗證 tokenizer SHA-256…';
      case 'installing':
        return '安裝模型…';
      case 'ready':
        return '模型已就緒';
      case 'failed':
        return '下載失敗';
      default:
        return '下載中…';
    }
  }

  String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final status = _downloadStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: (_busy || _qwenBusy || _testBusy) ? null : _start,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: Text(_busy ? '下載推薦模型中…' : '一鍵下載 Llama 3.2 3B'),
        ),
        if (status != null && _busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: status.totalBytes > 1 ? status.progress : null),
          const SizedBox(height: 4),
          Text(
            '${_stageLabel(status.stage)}  '
            '${(status.downloadedBytes / (1024 * 1024)).toStringAsFixed(0)} / '
            '${(status.totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: (_busy || _qwenBusy || _testBusy) ? null : _startQwen,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: Text(_qwenBusy ? '下載 Qwen2.5 1.5B 中…' : '一鍵下載 Qwen2.5 1.5B Q4_K_M'),
        ),
        if (_qwenBusy || _qwenProgress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _qwenProgress),
          const SizedBox(height: 4),
          Text(_qwenStage),
        ],
        if (_qwenError != null) ...[
          const SizedBox(height: 6),
          Text(_qwenError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        const Text('本機模型', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        FutureBuilder<List<LocalModelStatus>>(
          future: _modelsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Text('正在檢查已安裝模型…');
            }
            if (snapshot.hasError) return Text('模型狀態讀取失敗：${snapshot.error}');
            final models = snapshot.data ?? const <LocalModelStatus>[];
            return Column(
              children: models.map((model) {
                final sizeMb = model.modelBytes / (1024 * 1024);
                return RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: model.modelId,
                  groupValue: models.where((m) => m.selected && m.ready).firstOrNull?.modelId,
                  onChanged: model.ready ? (_) => _selectModel(model) : null,
                  title: Text(model.modelName),
                  subtitle: Text(
                    model.ready
                        ? '${model.runtime} · ${sizeMb.toStringAsFixed(0)} MB${model.selected ? ' · 使用中' : ''}'
                        : '${model.runtime} · 尚未安裝',
                  ),
                );
              }).toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const ValueKey('local-llm-inference-smoke-button'),
          onPressed: (_busy || _qwenBusy || _testBusy) ? null : _testInference,
          icon: const Icon(Icons.smart_toy_outlined),
          label: Text(_testBusy ? '本機推理中…' : '測試推理'),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            _testResult!,
            key: const ValueKey('local-llm-inference-smoke-result'),
          ),
        ],
      ],
    );
  }
}

class _QwenModelPackDownloader {
  static const sourceUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF';
  static const tokenizerSourceUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/blob/main/tokenizer.json';
  static const _modelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true';
  static const _tokenizerUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/resolve/main/tokenizer.json?download=true';
  static const _modelSha256 =
      '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e';
  static const _modelFile = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';
  static const _tokenizerFile = 'tokenizer.json';

  Future<File> downloadAndInstall({
    required void Function(String stage, int downloadedBytes, int totalBytes) onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}/model-pack/qwen2.5-1.5b-instruct-q4_k_m',
    );
    await directory.create(recursive: true);

    final model = File('${directory.path}/$_modelFile');
    final tokenizer = File('${directory.path}/$_tokenizerFile');

    await _download(
      Uri.parse(_modelUrl),
      model,
      stage: '下載 GGUF 模型…',
      onProgress: onProgress,
    );
    onProgress('驗證 GGUF SHA-256…', 0, 0);
    final actualModelSha = await _sha256(model);
    if (actualModelSha != _modelSha256) {
      await model.delete();
      throw StateError('GGUF SHA-256 驗證失敗');
    }

    await _download(
      Uri.parse(_tokenizerUrl),
      tokenizer,
      stage: '下載官方 tokenizer.json…',
      onProgress: onProgress,
    );
    onProgress('驗證 tokenizer.json…', 0, 0);
    final decoded = jsonDecode(await tokenizer.readAsString());
    if (decoded is! Map || !decoded.containsKey('model')) {
      await tokenizer.delete();
      throw StateError('tokenizer.json 格式不正確');
    }

    final manifest = File('${directory.path}/manifest.json');
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'id': 'qwen2.5-1.5b-instruct-q4_k_m',
        'name': 'Qwen2.5-1.5B-Instruct-Q4_K_M',
        'runtime': 'llama.cpp',
        'format': 'gguf',
        'quantization': 'Q4_K_M',
        'modelFile': _modelFile,
        'modelSha256': _modelSha256,
        'tokenizerFile': _tokenizerFile,
        'tokenizerSource': tokenizerSourceUrl,
        'tokenizerNote': 'GGUF embeds llama.cpp tokenizer metadata; tokenizer.json is retained as the official sidecar.',
        'source': sourceUrl,
        'license': 'Apache-2.0',
      }),
      flush: true,
    );
    onProgress('模型包已安裝', 1, 1);
    return model;
  }

  Future<void> _download(
    Uri uri,
    File target, {
    required String stage,
    required void Function(String stage, int downloadedBytes, int totalBytes) onProgress,
  }) async {
    final part = File('${target.path}.part');
    var existing = await part.exists() ? await part.length() : 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      var request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'HouseHolder-Android/0.1');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (existing > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      var response = await request.close();

      if (existing > 0 && response.statusCode == HttpStatus.ok) {
        await response.drain<void>();
        await part.delete();
        existing = 0;
        request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, 'HouseHolder-Android/0.1');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        response = await request.close();
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }

      final total = response.contentLength > 0 ? existing + response.contentLength : 0;
      var downloaded = existing;
      onProgress(stage, downloaded, total);
      final sink = part.openWrite(mode: existing > 0 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress(stage, downloaded, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
