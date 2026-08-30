import 'local_llama_gateway.dart';
import '../platform/ocr_gateway.dart';

sealed class AssistantInput {
  const AssistantInput();
}

class TextAssistantInput extends AssistantInput {
  const TextAssistantInput(this.text);
  final String text;
}

class SpeechAssistantInput extends AssistantInput {
  const SpeechAssistantInput(this.transcript);
  final String transcript;
}

class ImageAssistantInput extends AssistantInput {
  const ImageAssistantInput({required this.ocr, this.context});
  final OcrDocument ocr;
  final String? context;
}

class FamilyActionDraft {
  const FamilyActionDraft({required this.rawJson});
  final String rawJson;
}

/// One entry point for text, speech and image/OCR input.
///
/// The orchestrator may ask the local model to propose structured actions, but
/// it never applies them directly. Schema validation, confirmation and storage
/// belong to the application layer.
class AssistantOrchestrator {
  const AssistantOrchestrator(this._llama);

  final LocalLlamaGateway _llama;

  Future<FamilyActionDraft> propose(AssistantInput input) async {
    final groundedInput = switch (input) {
      TextAssistantInput(:final text) => 'USER_TEXT:\n$text',
      SpeechAssistantInput(:final transcript) => 'SPEECH_TRANSCRIPT:\n$transcript',
      ImageAssistantInput(:final ocr, :final context) => _imagePrompt(ocr, context),
    };

    final prompt = '''
You are HouseHolder's local planning model.
Return JSON only. Propose actions; do not claim they have already been applied.
Never invent household facts that are absent from the supplied input/context.
For OCR timetable imports, preserve uncertainty and require user confirmation.

$groundedInput
''';

    return FamilyActionDraft(rawJson: await _llama.generate(prompt));
  }

  String _imagePrompt(OcrDocument ocr, String? context) {
    final blocks = ocr.blocks
        .map((block) => '${block.text} @ [${block.left},${block.top},${block.right},${block.bottom}]')
        .join('\n');

    return '''
IMAGE_CONTEXT:
${context ?? '(none)'}
OCR_FULL_TEXT:
${ocr.fullText}
OCR_BLOCKS_WITH_BOUNDS:
$blocks
''';
  }
}
