import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:householder/platform/vision_language_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('householder/vision_language');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends image path and prompt to Android Qwen3-VL runtime', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <String, Object?>{
        'text': '{"cells":[]}',
        'modelId': VisionLanguageGateway.qwen3VlModelId,
        'runtime': 'llama.cpp/mtmd',
      };
    });

    final result = await VisionLanguageGateway().analyzeImage(
      '/tmp/timetable.jpg',
      prompt: 'Read timetable',
      maxTokens: 384,
      temperature: 0.0,
    );

    expect(captured?.method, 'analyzeImage');
    expect((captured?.arguments as Map)['imagePath'], '/tmp/timetable.jpg');
    expect((captured?.arguments as Map)['prompt'], 'Read timetable');
    expect((captured?.arguments as Map)['maxTokens'], 384);
    expect(result.modelId, VisionLanguageGateway.qwen3VlModelId);
    expect(result.runtime, 'llama.cpp/mtmd');
  });

  test('rejects empty image path before invoking native code', () async {
    expect(
      () => VisionLanguageGateway().analyzeImage('', prompt: 'read'),
      throwsArgumentError,
    );
  });
}
