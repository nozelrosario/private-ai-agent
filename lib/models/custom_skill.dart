import 'dart:convert';

class SkillParameter {
  final String name; // Variable key e.g. 'recipient', 'amount'
  final String description; // Guidance for LLM extraction
  final String type; // 'string', 'number', 'boolean'
  final bool isRequired;
  final String? defaultValue;

  SkillParameter({
    required this.name,
    required this.description,
    this.type = 'string',
    this.isRequired = true,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'type': type,
    'is_required': isRequired,
    'default_value': defaultValue,
  };

  factory SkillParameter.fromJson(Map<String, dynamic> json) => SkillParameter(
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    type: json['type'] as String? ?? 'string',
    isRequired: json['is_required'] as bool? ?? true,
    defaultValue: json['default_value'] as String?,
  );
}

class RecipeStep {
  final int stepNumber;
  final String instruction; // SOP step description with optional placeholders like {recipient}
  final String? targetAppPackage; // Optional app package requirement
  final String? expectedElementHint; // Text or view hint on screen
  final String? actionTypeHint; // click_text, type_text, scroll, etc.
  final bool requiresConfirmation; // Checkpoint gate before execution
  final String? confirmationMessage; // User confirmation prompt

  RecipeStep({
    required this.stepNumber,
    required this.instruction,
    this.targetAppPackage,
    this.expectedElementHint,
    this.actionTypeHint,
    this.requiresConfirmation = false,
    this.confirmationMessage,
  });

  Map<String, dynamic> toJson() => {
    'step_number': stepNumber,
    'instruction': instruction,
    'target_app_package': targetAppPackage,
    'expected_element_hint': expectedElementHint,
    'action_type_hint': actionTypeHint,
    'requires_confirmation': requiresConfirmation,
    'confirmation_message': confirmationMessage,
  };

  factory RecipeStep.fromJson(Map<String, dynamic> json) => RecipeStep(
    stepNumber: json['step_number'] as int? ?? 1,
    instruction: json['instruction'] as String? ?? '',
    targetAppPackage: json['target_app_package'] as String?,
    expectedElementHint: json['expected_element_hint'] as String?,
    actionTypeHint: json['action_type_hint'] as String?,
    requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
    confirmationMessage: json['confirmation_message'] as String?,
  );

  RecipeStep copyWith({
    int? stepNumber,
    String? instruction,
    String? targetAppPackage,
    String? expectedElementHint,
    String? actionTypeHint,
    bool? requiresConfirmation,
    String? confirmationMessage,
  }) {
    return RecipeStep(
      stepNumber: stepNumber ?? this.stepNumber,
      instruction: instruction ?? this.instruction,
      targetAppPackage: targetAppPackage ?? this.targetAppPackage,
      expectedElementHint: expectedElementHint ?? this.expectedElementHint,
      actionTypeHint: actionTypeHint ?? this.actionTypeHint,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      confirmationMessage: confirmationMessage ?? this.confirmationMessage,
    );
  }
}

class CustomSkill {
  final String id;
  final String name;
  final String description;
  final String icon; // Icon name e.g. 'chat', 'payment', 'settings'
  final String category; // 'Messaging', 'Finance', 'System', 'Social'
  final List<String> triggerKeywords;
  final List<SkillParameter> parameters;
  final List<RecipeStep> steps;
  final bool isEnabled;
  final bool isSystemTemplate;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomSkill({
    required this.id,
    required this.name,
    required this.description,
    this.icon = 'star',
    this.category = 'General',
    this.triggerKeywords = const [],
    this.parameters = const [],
    this.steps = const [],
    this.isEnabled = true,
    this.isSystemTemplate = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'category': category,
    'trigger_keywords': triggerKeywords,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'steps': steps.map((s) => s.toJson()).toList(),
    'is_enabled': isEnabled,
    'is_system_template': isSystemTemplate,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory CustomSkill.fromJson(Map<String, dynamic> json) => CustomSkill(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled Skill',
    description: json['description'] as String? ?? '',
    icon: json['icon'] as String? ?? 'star',
    category: json['category'] as String? ?? 'General',
    triggerKeywords: List<String>.from(json['trigger_keywords'] ?? []),
    parameters: (json['parameters'] as List? ?? [])
        .map((p) => SkillParameter.fromJson(p as Map<String, dynamic>))
        .toList(),
    steps: (json['steps'] as List? ?? [])
        .map((s) => RecipeStep.fromJson(s as Map<String, dynamic>))
        .toList(),
    isEnabled: json['is_enabled'] as bool? ?? true,
    isSystemTemplate: json['is_system_template'] as bool? ?? false,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: json['updated_at'] != null
        ? DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  CustomSkill copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    String? category,
    List<String>? triggerKeywords,
    List<SkillParameter>? parameters,
    List<RecipeStep>? steps,
    bool? isEnabled,
    bool? isSystemTemplate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomSkill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      triggerKeywords: triggerKeywords ?? this.triggerKeywords,
      parameters: parameters ?? this.parameters,
      steps: steps ?? this.steps,
      isEnabled: isEnabled ?? this.isEnabled,
      isSystemTemplate: isSystemTemplate ?? this.isSystemTemplate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
