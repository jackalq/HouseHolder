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
          80,
        ),
      SpeechAssistantInput(:final transcript) => (
          _householdActionPrompt(
            inputLabel: 'SPEECH_TRANSCRIPT',
            inputText: transcript,
            today: today,
            weekday: now.weekday,
          ),
          80,
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
      rawJson: await _llama.generate(prompt, maxTokens: maxTokens, temperature: 0),
    );
  }

  String _householdActionPrompt({
    required String inputLabel,
    required String inputText,
    required String today,
    required int weekday,
  }) {
    final lower = inputText.toLowerCase();
    final scheduleIntent = _containsAny(lower, const [
      '課表', '課程', '上課', 'schedule', 'class', 'lesson', 'tomorrow', 'today',
    ]);
    final shoppingIntent = _containsAny(lower, const [
      '採購', '購物', '買', 'shopping', 'buy', 'purchase', 'milk',
    ]);
    final todoIntent = _containsAny(lower, const [
      '待辦', '提醒', 'todo', 'task', 'remember',
    ]);

    final actions = scheduleIntent && !shoppingIntent && !todoIntent
        ? _scheduleActions
        : shoppingIntent && !scheduleIntent && !todoIntent
            ? _shoppingActions
            : todoIntent && !scheduleIntent && !shoppingIntent
                ? _todoActions
                : '$_scheduleActions\n$_shoppingActions\n$_todoActions';

    return '''
HouseHolder action planner. Return ONE JSON object only.
Today=$today weekday=$weekday (Mon=1..Sun=7). Do not invent stored facts.
$actions
unsupported={"type":"unsupported","requiresConfirmation":false,"payload":{"reason":"reason"}}
Resolve relative dates. Repository questions emit query/list actions, never answer stored facts yourself. Keep user names/titles exactly.
$inputLabel: $inputText
''';
  }

  static const _scheduleActions =
      'schedule.query={"type":"schedule.query","requiresConfirmation":false,"payload":{"date":"YYYY-MM-DD","childId":null}}';

  static const _shoppingActions = '''
shopping.add={"type":"shopping.add","requiresConfirmation":false,"payload":{"items":[{"name":"item","quantity":1,"unit":"個","done":false}]}}
shopping.list={"type":"shopping.list","requiresConfirmation":false,"payload":{"includeDone":false}}
shopping.setDone={"type":"shopping.setDone","requiresConfirmation":false,"payload":{"name":"item","done":true}}''';

  static const _todoActions = '''
todo.add={"type":"todo.add","requiresConfirmation":false,"payload":{"items":[{"title":"task","done":false,"dueDate":null}]}}
todo.list={"type":"todo.list","requiresConfirmation":false,"payload":{"includeDone":false}}
todo.setDone={"type":"todo.setDone","requiresConfirmation":false,"payload":{"title":"task","done":true}}''';

  bool _containsAny(String text, List<String> values) => values.any(text.contains);

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
Rules: schedule.import requires confirmation; never invent OCR fields; unknown optional values are null; context childId/validFrom/validUntil is authoritative; IDs must be unique ASCII.
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
