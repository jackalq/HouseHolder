import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

/// Downloads large files reliably with HTTP Range resume and automatic retry.
///
/// The partial file is kept as `<target>.part`. Each retry re-opens the source
/// URL so expiring CDN redirects/signatures are refreshed, then requests the
/// remaining byte range. The target is only replaced after the complete body
/// has been received.
class ResumableHttpDownloader {
  ResumableHttpDownloader({
    this.maxAttempts = 8,
    this.connectionTimeout = const Duration(seconds: 30),
    this.idleReadTimeout = const Duration(minutes: 2),
    this.retryBaseDelay = const Duration(seconds: 2),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final int maxAttempts;
  final Duration connectionTimeout;
  final Duration idleReadTimeout;
  final Duration retryBaseDelay;
  final HttpClient Function() _clientFactory;

  Future<void> download(
    Uri source,
    File target, {
    required String stage,
    required void Function(String stage, int downloadedBytes, int totalBytes)
        onProgress,
  }) async {
    final part = File('${target.path}.part');
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      var existing = await part.exists() ? await part.length() : 0;
      final client = _clientFactory()..connectionTimeout = connectionTimeout;
      try {
        var response = await _open(client, source, existing);

        // Some servers ignore Range and return 200. In that case restart only
        // this file rather than appending a second full response.
        if (existing > 0 && response.statusCode == HttpStatus.ok) {
          await response.drain<void>();
          if (await part.exists()) await part.delete();
          existing = 0;
          response = await _open(client, source, 0);
        }

        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          final status = response.statusCode;
          await response.drain<void>();
          throw HttpException('HTTP $status');
        }

        if (existing > 0 && response.statusCode == HttpStatus.partialContent) {
          final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
          if (contentRange != null && !contentRange.startsWith('bytes $existing-')) {
            throw const HttpException('Server returned an invalid resume range');
          }
        }

        final total = response.contentLength > 0
            ? existing + response.contentLength
            : 0;
        var downloaded = existing;
        onProgress(
          attempt == 1 ? stage : '$stage（自動續傳 $attempt/$maxAttempts）',
          downloaded,
          total,
        );

        final sink = part.openWrite(
          mode: existing > 0 ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response.timeout(idleReadTimeout)) {
            sink.add(chunk);
            downloaded += chunk.length;
            onProgress(stage, downloaded, total);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        // contentLength is the bytes expected in this response. A clean EOF
        // before that amount means a CDN/proxy closed the transfer early.
        if (response.contentLength > 0 &&
            downloaded - existing != response.contentLength) {
          throw const HttpException('Connection ended before download completed');
        }

        if (await target.exists()) await target.delete();
        try {
          await part.rename(target.path);
        } on FileSystemException {
          await part.copy(target.path);
          await part.delete();
        }
        return;
      } catch (error) {
        lastError = error;
        if (attempt >= maxAttempts || !_isRetryable(error)) rethrow;
        final delaySeconds = math.min(
          30,
          retryBaseDelay.inSeconds * (1 << math.min(attempt - 1, 4)),
        );
        await Future<void>.delayed(Duration(seconds: delaySeconds));
      } finally {
        client.close(force: true);
      }
    }

    throw StateError(_safeMessage(lastError));
  }

  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri source,
    int existing,
  ) async {
    final request = await client.getUrl(source);
    request.followRedirects = true;
    request.maxRedirects = 10;
    request.headers.set(HttpHeaders.userAgentHeader, 'HouseHolder-Android/0.2');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (existing > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
    }
    return request.close();
  }

  bool _isRetryable(Object error) {
    return error is HttpException ||
        error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException;
  }

  String _safeMessage(Object? error) {
    if (error is HttpException) return error.message;
    if (error is SocketException) return '網路連線中斷';
    if (error is TimeoutException) return '下載逾時';
    if (error is HandshakeException) return 'TLS 連線失敗';
    return '模型下載失敗';
  }
}
