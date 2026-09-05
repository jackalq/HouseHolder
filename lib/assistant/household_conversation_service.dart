import 'assistant_orchestrator.dart';
import 'family_action.dart';
import 'family_action_executor.dart';
import '../features/schedule/schedule_import_models.dart';

enum ConversationRole { user, assistant }

class ConversationMessage {
  const ConversationMessage({required this.role, required this.text});

  final ConversationRole role;
  final String text;
}

class ConversationTurnResult {
  const ConversationTurnResult({
    required this.userMessage,
    required this.assistantMessage,
    this.scheduleDraft,
    this.rawActionJson,
  });

  final ConversationMessage userMessage;
  final ConversationMessage assistantMessage;
  final ScheduleImportDraft? scheduleDraft;
  final String? rawActionJson;
}

typedef AssistantProposer = Future<FamilyActionDraft> Function(AssistantInput input);

class HouseholdConversationService {
  HouseholdConversationService({
    required AssistantProposer propose,
    required FamilyActionExecutor executor,
    FamilyActionParser parser = const FamilyActionParser(),
  })  : _propose = propose,
        _executor = executor,
        _parser = parser;

  final AssistantProposer _propose;
  final FamilyActionExecutor _executor;
  final FamilyActionParser _parser;

  Future<ConversationTurnResult> sendText(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw const FormatException('訊息不能是空白。');
    }
    return _run(TextAssistantInput(normalized), normalized);
  }

  Future<ConversationTurnResult> sendInput(AssistantInput input, String displayText) async {
    final normalized = displayText.trim();
    if (normalized.isEmpty) {
      throw const FormatException('訊息不能是空白。');
    }
    return _run(input, normalized);
  }

  Future<ConversationTurnResult> _run(AssistantInput input, String userText) async {
    final draft = await _propose(input);
    final action = _parser.parse(draft.rawJson);
    final result = await _executor.execute(action);
    return ConversationTurnResult(
      userMessage: ConversationMessage(role: ConversationRole.user, text: userText),
      assistantMessage: ConversationMessage(
        role: ConversationRole.assistant,
        text: result.scheduleDraft == null ? result.message : '我已整理出課表草稿，請確認後再寫入家庭資料。',
      ),
      scheduleDraft: result.scheduleDraft,
      rawActionJson: draft.rawJson,
    );
  }
}
