import 'dart:convert';

class FamilyAction {
  const FamilyAction({
    required this.type,
    required this.requiresConfirmation,
    required this.payload,
  });

  final String type;
  final bool requiresConfirmation;
  final Map<String, Object?> payload;

  factory FamilyAction.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final requiresConfirmation = json['requiresConfirmation'];
    final payload = json['payload'];

    if (type is! String || type.trim().isEmpty) {
      throw const FormatException('FamilyAction.type must be a non-empty string.');
    }
    if (requiresConfirmation is! bool) {
      throw const FormatException('FamilyAction.requiresConfirmation must be boolean.');
    }
    if (payload is! Map) {
      throw const FormatException('FamilyAction.payload must be an object.');
    }

    return FamilyAction(
      type: type,
      requiresConfirmation: requiresConfirmation,
      payload: payload.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Map<String, Object?> toJson() => {
        'type': type,
        'requiresConfirmation': requiresConfirmation,
        'payload': payload,
      };
}

class FamilyActionParser {
  const FamilyActionParser();

  FamilyAction parse(String rawModelOutput) {
    final cleaned = _stripCodeFence(rawModelOutput.trim());
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map) {
      throw const FormatException('Model output must be one JSON object.');
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    return FamilyAction.fromJson(map);
  }

  String _stripCodeFence(String text) {
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    final lastFence = text.lastIndexOf('```');
    if (firstNewline < 0 || lastFence <= firstNewline) return text;
    return text.substring(firstNewline + 1, lastFence).trim();
  }
}
