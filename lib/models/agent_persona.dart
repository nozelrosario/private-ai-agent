import 'dart:convert';

class AgentPersona {
  final String id;
  final String name; // e.g. "Personal Assistant", "Finance Agent"
  final String description; // Short overview
  final String avatarIcon; // Material icon key e.g. 'smart_toy', 'account_balance', 'chat'
  final String systemPromptModifier; // Specialized instructions for this persona
  final List<String> assignedSkillIds; // Subset of custom skill IDs scoped to this persona
  final bool isDefault;
  final double? temperatureOverride;

  AgentPersona({
    required this.id,
    required this.name,
    required this.description,
    this.avatarIcon = 'smart_toy',
    this.systemPromptModifier = '',
    this.assignedSkillIds = const [],
    this.isDefault = false,
    this.temperatureOverride,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'avatar_icon': avatarIcon,
    'system_prompt_modifier': systemPromptModifier,
    'assigned_skill_ids': assignedSkillIds,
    'is_default': isDefault,
    'temperature_override': temperatureOverride,
  };

  factory AgentPersona.fromJson(Map<String, dynamic> json) => AgentPersona(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Agent',
    description: json['description'] as String? ?? '',
    avatarIcon: json['avatar_icon'] as String? ?? 'smart_toy',
    systemPromptModifier: json['system_prompt_modifier'] as String? ?? '',
    assignedSkillIds: List<String>.from(json['assigned_skill_ids'] ?? []),
    isDefault: json['is_default'] as bool? ?? false,
    temperatureOverride: (json['temperature_override'] as num?)?.toDouble(),
  );

  AgentPersona copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarIcon,
    String? systemPromptModifier,
    List<String>? assignedSkillIds,
    bool? isDefault,
    double? temperatureOverride,
  }) {
    return AgentPersona(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarIcon: avatarIcon ?? this.avatarIcon,
      systemPromptModifier: systemPromptModifier ?? this.systemPromptModifier,
      assignedSkillIds: assignedSkillIds ?? this.assignedSkillIds,
      isDefault: isDefault ?? this.isDefault,
      temperatureOverride: temperatureOverride ?? this.temperatureOverride,
    );
  }
}
