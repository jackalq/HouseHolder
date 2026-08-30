import 'dart:async';

import 'package:flutter/material.dart';
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
  Timer? _pollTimer;
  RecommendedModelDownloadStatus? _downloadStatus;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;

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

    try {
      final status = await _llama.downloadRecommendedModelPack();
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _busy = false;
        _downloadStatus = null;
      });
      widget.onInstalled();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.ready ? '推薦模型已下載並完成驗證。' : '下載完成，但模型狀態仍未就緒。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _pollTimer?.cancel();
      setState(() {
        _busy = false;
        _error = '推薦模型下載失敗：$error';
      });
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
          onPressed: _busy ? null : _start,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: Text(_busy ? '下載推薦模型中…' : '一鍵下載推薦模型'),
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
      ],
    );
  }
}
