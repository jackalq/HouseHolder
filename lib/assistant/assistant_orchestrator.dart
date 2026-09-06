import 'dart:convert';

import 'local_llama_gateway.dart';
import 'shopping_text_parser.dart';
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
  const AssistantOrchestrator(
    this._llama, {
    ShoppingTextParser shoppingTextParser = const ShoppingTextParser(),
  }) : _shoppingTextParser = shoppingTextParser;

  final LocalLlamaGateway _llama;
  final ShoppingTextParser _shoppingTextParser;

  Future<FamilyActionDraft> propose(AssistantInput input) async {
    final now = DateTime.now();
    final today = _date(now);

    if (input case TextAssistantInput(:final text)) {
      return _proposeTextLike('USER_TEXT', text, today, now.weekday);
    }
    if (input case SpeechAssistantInput(:final transcript)) {
      return _proposeTextLike('SPEECH_TRANSCRIPT', transcript, today, now.weekday);
    }
    final image = input as ImageAssistantInput;
    return FamilyActionDraft(
      rawJson: await _llama.generate(
        _scheduleImportPrompt(
          ocr: image.ocr,
          context: image.context,
          today: today,
          weekday: now.weekday,
        ),
        maxTokens: 768,
        temperature: 0,
      ),
    );
  }

  Future<FamilyActionDraft> _proposeTextLike(
    String inputLabel,
    String inputText,
    String today,
    int weekday,
  ) async {
    // Explicit shopping additions are deterministic. This prevents malformed
    // or truncated model JSON from corrupting a multi-item shopping entry.
    final deterministicShopping = _shoppingTextParser.tryBuildAddAction(inputText);
    if (deterministicShopping != null) {
      return FamilyActionDraft(rawJson: deterministicShopping);
    }

    final intents = _intents(inputText);
    if (intents.schedule && !intents.shopping && !intents.todo) {
      final raw = await _llama.generate(
        '''
Resolve the requested schedule date. Return JSON only: {"date":"YYYY-MM-DD"}.
Today=$today weekday=$weekday (Mon=1..Sun=7). Resolve today/tomorrow/relative dates; do not answer courses.
$inputLabel: $inputText
''',
        maxTokens: 24,
        temperature: 0,
      );
      return FamilyActionDraft(rawJson: _wrapScheduleDate(raw));
    }

    return FamilyActionDraft(
      rawJson: await _llama.generate(
        _householdActionPrompt(
          inputLabel: inputLabel,
          inputText: inputText,
          today: today,
          weekday: weekday,
          intents: intents,
        ),
        // 80 tokens was too small for multi-item actions and could truncate a
        // valid JSON object. Keep enough headroom for structured responses.
        maxTokens: 256,
        temperature: 0,
      ),
    );
  }

  String _wrapScheduleDate(String raw) {
    final cleaned = _stripFence(raw.trim());
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map || decoded['date'] is! String) {
      throw const FormatException('Local model must return a schedule date object.');
    }
    final date = (decoded['date'] as String).trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) || DateTime.tryParse(date) == null) {
      throw const FormatException('Local model schedule date must be YYYY-MM-DD.');
    }
    return jsonEncode({
      'type': 'schedule.query',
      'requiresConfirmation': false,
      'payload': {'date': date, 'childId': null},
    });
  }

  String _stripFence(String text) {
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    final lastFence = text.lastIndexOf('```');
    if (firstNewline < 0 || lastFence <= firstNewline) return text;
    return text.substring(firstNewline + 1, lastFence).trim();
  }

  String _householdActionPrompt({
    required String inputLabel,
    required String inputText,
    required String today,
    required int weekday,
    required _HouseholdIntents intents,
  }) {
    final actions = intents.shopping && !intents.schedule && !intents.todo
        ? _shoppingActions
        : intents.todo && !intents.schedule && !intents.shopping
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

  _HouseholdIntents _intents(String text) {
    final lower = text.toLowerCase();
    return _HouseholdIntents(
      schedule: _containsAny(lower, const [
        '課表', '課程', '上課', 'schedule', 'class', 'lesson', 'tomorrow', 'today',
      ]),
      shopping: _containsAny(lower, const [
        '採購', '採買', '購物', '買', 'shopping', 'buy', 'purchase', 'milk',
      ]),
      todo: _containsAny(lower, const [
        '待辦', '提醒', 'todo', 'task', 'remember',
      ]),
    );
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

class _HouseholdIntents {
  const _HouseholdIntents({required this.schedule, required this.shopping, required this.todo});
  final bool schedule;
  final bool shopping;
  final bool todo;
}
