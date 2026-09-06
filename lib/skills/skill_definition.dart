class SkillDefinition {
  const SkillDefinition({
    required this.id,
    required this.version,
    required this.description,
    required this.inputFormats,
    required this.outputFormat,
    required this.instructions,
    this.requiresConfirmation = false,
  });

  final String id;
  final int version;
  final String description;
  final List<String> inputFormats;
  final String outputFormat;
  final String instructions;
  final bool requiresConfirmation;

  factory SkillDefinition.fromJson(Map<String, Object?> json) {
    return SkillDefinition(
      id: json['id']! as String,
      version: json['version']! as int,
      description: json['description']! as String,
      inputFormats: (json['inputFormats']! as List).cast<String>(),
      outputFormat: json['outputFormat']! as String,
      instructions: json['instructions']! as String,
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
    );
  }
}

abstract interface class SkillRegistry {
  Future<List<SkillDefinition>> list();
  Future<SkillDefinition?> get(String id);

  /// Installs only validated declarative definitions. Executable code is not
  /// accepted through this interface.
  Future<void> install(SkillDefinition definition);
}
