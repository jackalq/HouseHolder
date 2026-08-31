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
    final now = DateTime.now();
    final today = _date(now);

    final (prompt, maxTokens) = switch (input) {
      TextAssistantInput(:final text) => (
          _householdActionPrompt(
            inputLabel: 'USER_TEXT',
            inputText: text,
            today: today,
            weekday: now.weekday,
          ),
          128,
        ),
      SpeechAssistantInput(:final transcript) => (
          _householdActionPrompt(
            inputLabel: 'SPEECH_TRANSCRIPT',
            inputText: transcript,
            today: today,
            weekday: now.weekday,
          ),
          128,
        ),
      ImageAssistantInput(:final ocr, :final context) => (
          _scheduleImportPrompt(
            ocr: ocr,
            context: context,
            today: today,
            weekday: now.weekday,
          ),
          768,
        ),
    };

    return FamilyActionDraft(
      rawJson: await _llama.generate(
        prompt,
        maxTokens: maxTokens,
        temperature: 0,
      ),
    );
  }

  String _householdActionPrompt({
    required String inputLabel,
    required String inputText,
    required String today,
    required int weekday,
  }) =>
      '''
You are HouseHolder's local action planner. Output exactly ONE JSON object, no prose or markdown.
Today=$today; weekday=$weekday (Mon=1..Sun=7).
Never invent household facts. Queries must ask the app repository.

Actions and exact JSON shapes:
schedule.query: {"type":"schedule.query","requiresConfirmation":false,"payload":{"date":"YYYY-MM-DD","childId":null}}
shopping.add: {"type":"shopping.add","requiresConfirmation":false,"payload":{"items":[{"id":"new-id","name":"item","quantity":1,"unit":null,"done":false,"note":null}]}}
shopping.list: {"type":"shopping.list","requiresConfirmation":false,"payload":{"includeDone":false}}
shopping.setDone: {"type":"shopping.setDone","requiresConfirmation":false,"payload":{"name":"item","done":true}}
todo.add: {"type":"todo.add","requiresConfirmation":false,"payload":{"items":[{"id":"new-id","title":"task","done":false,"dueDate":null,"note":null}]}}
todo.list: {"type":"todo.list","requiresConfirmation":false,"payload":{"includeDone":false}}
todo.setDone: {"type":"todo.setDone","requiresConfirmation":false,"payload":{"title":"task","done":true}}
unsupported: {"type":"unsupported","requiresConfirmation":false,"payload":{"reason":"reason"}}

Resolve today/tomorrow/relative dates to YYYY-MM-DD. For schedule questions ALWAYS emit schedule.query; never answer courses yourself. Use user-stated item names/titles, never internal IDs. New IDs are short unique ASCII.

$inputLabel:
$inputText
''';

  String _scheduleImportPrompt({
    required OcrDocument ocr,
    required String? context,
    required String today,
    required int weekday,
  }) {
    final blocks = ocr.blocks
        .map((block) => '${block.text} @ [${block.left},${block.top},${block.right},${block.bottom}]')
        .join('\n');

    return '''
You are HouseHolder's local timetable importer. Output exactly ONE JSON object, no prose or markdown.
Today=$today; weekday=$weekday (Mon=1..Sun=7).
Output only this action shape:
{"type":"schedule.import","requiresConfirmation":true,"payload":{"items":[{"id":"new-id","childId":"child-id","dayOfWeek":1,"subject":"subject","validFrom":"YYYY-MM-DD","validUntil":null,"startTime":null,"endTime":null,"period":1,"teacher":null,"location":null,"note":null}],"warnings":[]}}

Rules:
- schedule.import ALWAYS requiresConfirmation=true.
- Never invent OCR fields. Unknown optional fields are null/omitted and uncertainty goes in warnings.
- HOUSEHOLDER_IMPORT_CONTEXT values are authoritative and must be copied exactly into every item's childId/validFrom/validUntil.
- New IDs are short unique ASCII and must not repeat.

HOUSEHOLDER_IMPORT_CONTEXT:
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
