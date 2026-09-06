import 'dart:io';

import 'package:family_butler/features/model/resumable_http_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('householder-download-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('resumes an existing .part file with HTTP Range', () async {
    final bytes = List<int>.generate(128 * 1024, (index) => index % 251);
    final target = File('${temp.path}/model.gguf');
    final part = File('${target.path}.part');
    const existing = 32768;
    await part.writeAsBytes(bytes.take(existing).toList(), flush: true);

    String? rangeHeader;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $existing-${bytes.length - 1}/${bytes.length}',
      );
      request.response.contentLength = bytes.length - existing;
      request.response.add(bytes.skip(existing).toList());
      await request.response.close();
    });

    try {
      final downloader = ResumableHttpDownloader(
        retryBaseDelay: Duration.zero,
      );
      await downloader.download(
        Uri.parse('http://${server.address.host}:${server.port}/model'),
        target,
        stage: '下載',
        onProgress: (_, __, ___) {},
      );

      expect(rangeHeader, 'bytes=$existing-');
      expect(await target.readAsBytes(), bytes);
      expect(await part.exists(), isFalse);
    } finally {
      await server.close(force: true);
    }
  });

  test('automatically retries a transient HTTP failure', () async {
    final bytes = List<int>.generate(4096, (index) => index % 239);
    final target = File('${temp.path}/tokenizer.json');
    var requests = 0;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests += 1;
      if (requests == 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });

    try {
      final downloader = ResumableHttpDownloader(
        maxAttempts: 3,
        retryBaseDelay: Duration.zero,
      );
      await downloader.download(
        Uri.parse('http://${server.address.host}:${server.port}/tokenizer'),
        target,
        stage: '下載',
        onProgress: (_, __, ___) {},
      );

      expect(requests, 2);
      expect(await target.readAsBytes(), bytes);
    } finally {
      await server.close(force: true);
    }
  });
}
