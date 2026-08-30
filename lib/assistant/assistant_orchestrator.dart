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

class AssistantOrchestrator {
  const AssistantOrchestrator(this._llama);

  final LocalLlamaGateway _llama;

  Future<FamilyActionDraft> propose(AssistantInput input) async {
    final groundedInput = switch (input) {
      TextAssistantInput(:final text) => 'USER_TEXT:\n$text',
      SpeechAssistantInput(:final transcript) => 'SPEECH_TRANSCRIPT:\n$transcript',
      ImageAssistantInput(:final ocr, :final context) => _imagePrompt(ocr, context),
    };

    final now = DateTime.now();
    final today = _date(now);
    final prompt = '''
You are HouseHolder's local planning model. You NEVER answer household facts from memory.
Return exactly one JSON object and no prose or markdown.
Current local date: $today
Current local weekday: ${now.weekday} (Monday=1, Sunday=7)

Allowed actions only:
1. schedule.import
{"type":"schedule.import","requiresConfirmation":true,"payload":{"items":[{"id":"stable-id","childId":"child-id","dayOfWeek":1,"subject":"國文","validFrom":"YYYY-MM-DD","validUntil":null,"startTime":null,"endTime":null,"period":1,"teacher":null,"location":null,"note":null}],"warnings":[]}}
2. schedule.query
{"type":"schedule.query","requiresConfirmation":false,"payload":{"date":"YYYY-MM-DD","childId":null}}
3. shopping.add
{"type":"shopping.add","requiresConfirmation":false,"payload":{"items":[{"id":"stable-id","name":"牛奶","quantity":1,"unit":"瓶","done":false,"note":null}]}}
4. shopping.list
{"type":"shopping.list","requiresConfirmation":false,"payload":{"includeDone":false}}
5. shopping.setDone
{"type":"shopping.setDone","requiresConfirmation":false,"payload":{"id":"item-id","done":true}}
6. todo.add
{"type":"todo.add","requiresConfirmation":false,"payload":{"items":[{"id":"stable-id","title":"繳學費","done":false,"dueDate":"YYYY-MM-DD","note":null}]}}
7. todo.list
{"type":"todo.list","requiresConfirmation":false,"payload":{"includeDone":false}}
8. todo.setDone
{"type":"todo.setDone","requiresConfirmation":false,"payload":{"id":"todo-id","done":true}}

Rules:
- Resolve relative dates such as today/tomorrow into exact YYYY-MM-DD using Current local date.
- For schedule queries, do not answer courses yourself. Emit schedule.query so the app reads the repository.
- For shopping/todo lists, emit list actions; do not invent list content.
- schedule.import ALWAYS requires confirmation.
- Never invent OCR fields. Unknown optional fields must be null or omitted; add uncertainty to warnings.
- IDs for new items must be short unique ASCII identifiers. Never reuse an ID from another item in the same response.
- If the request is outside supported actions, return {"type":"unsupported","requiresConfirmation":false,"payload":{"reason":"..."}}.

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

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
