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
Return exactly one JSON object and no Markdown.
Do not claim an action has already been applied.
Never invent household facts absent from the supplied input/context.

FamilyAction envelope:
{
  "type": "...",
  "requiresConfirmation": true,
  "payload": {}
}

For timetable OCR, type MUST be "schedule.import", requiresConfirmation MUST be true,
and payload MUST have this shape:
{
  "items": [
    {
      "id": "stable-import-id",
      "childId": "known child id or explicit name from context",
      "dayOfWeek": 1,
      "startTime": "08:00",
      "endTime": "08:40",
      "period": 1,
      "subject": "國語",
      "teacher": null,
      "location": null,
      "note": null,
      "validFrom": "YYYY-MM-DD"
    }
  ],
  "warnings": ["任何不確定或缺失資訊"]
}

Rules:
- dayOfWeek is 1=Monday ... 7=Sunday.
- Do not guess missing times, child identity, teacher, location, or semester date.
- If validFrom or childId cannot be supported by input/context, put a warning and do not fabricate it.
- OCR imports always require user confirmation.

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
