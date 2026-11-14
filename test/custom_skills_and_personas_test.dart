import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/models/agent_persona.dart';
import 'package:private_agent/models/custom_skill.dart';
import 'package:private_agent/services/skill_router_service.dart';

void main() {
  group('CustomSkill & RecipeStep Models', () {
    test('serializes and deserializes CustomSkill with parameters and recipe steps', () {
      final skill = CustomSkill(
        id: 'test_skill_1',
        name: 'Send Telegram Alert',
        description: 'Sends an alert to a Telegram channel',
        category: 'Messaging',
        icon: 'chat',
        triggerKeywords: ['alert', 'notify', 'telegram'],
        parameters: [
          SkillParameter(
            name: 'chat_id',
            description: 'Target chat identifier',
            type: 'string',
            isRequired: true,
          ),
          SkillParameter(
            name: 'priority',
            description: 'Alert priority level',
            type: 'number',
            isRequired: false,
            defaultValue: '1',
          ),
        ],
        steps: [
          RecipeStep(
            stepNumber: 1,
            instruction: 'Open Telegram and locate chat {chat_id}',
            actionTypeHint: 'open_app',
          ),
          RecipeStep(
            stepNumber: 2,
            instruction: 'Type priority {priority} alert and send',
            requiresConfirmation: true,
            confirmationMessage: 'Send priority {priority} alert to {chat_id}?',
          ),
        ],
      );

      final jsonMap = skill.toJson();
      final roundtrip = CustomSkill.fromJson(jsonMap);

      expect(roundtrip.id, 'test_skill_1');
      expect(roundtrip.name, 'Send Telegram Alert');
      expect(roundtrip.category, 'Messaging');
      expect(roundtrip.parameters.length, 2);
      expect(roundtrip.parameters[0].name, 'chat_id');
      expect(roundtrip.parameters[1].defaultValue, '1');
      expect(roundtrip.steps.length, 2);
      expect(roundtrip.steps[1].requiresConfirmation, isTrue);
      expect(
        roundtrip.steps[1].confirmationMessage,
        'Send priority {priority} alert to {chat_id}?',
      );
    });

    test('SkillMatchResult accurately replaces parameters in recipe templates', () {
      final skill = CustomSkill(
        id: 'mock_pay',
        name: 'Mock Payment',
        description: 'Transfers money',
        steps: [
          RecipeStep(
            stepNumber: 1,
            instruction: 'Transfer \${amount} to {recipient}',
            requiresConfirmation: true,
            confirmationMessage: 'Confirm sending \${amount} to {recipient}?',
          ),
        ],
      );

      final matchResult = SkillMatchResult(
        skill: skill,
        extractedParameters: {
          'amount': '50',
          'recipient': 'Alice',
        },
        confidence: 0.98,
      );

      final step = skill.steps.first;
      final substitutedInstruction = matchResult.applyParameters(step.instruction);
      final substitutedConfirmation = matchResult.applyParameters(step.confirmationMessage!);

      expect(substitutedInstruction, 'Transfer \$50 to Alice');
      expect(substitutedConfirmation, 'Confirm sending \$50 to Alice?');
    });
  });

  group('AgentPersona Model & Scoping', () {
    test('creates persona with scoped skill IDs and serialization', () {
      final persona = AgentPersona(
        id: 'finance_agent',
        name: 'Finance Agent',
        description: 'Handles banking and payment apps',
        avatarIcon: 'account_balance',
        systemPromptModifier: 'Always verify transfer amounts carefully.',
        assignedSkillIds: ['revolut_pay', 'paypal_send'],
        isDefault: false,
      );

      final jsonMap = persona.toJson();
      final roundtrip = AgentPersona.fromJson(jsonMap);

      expect(roundtrip.id, 'finance_agent');
      expect(roundtrip.name, 'Finance Agent');
      expect(roundtrip.assignedSkillIds, ['revolut_pay', 'paypal_send']);
      expect(roundtrip.systemPromptModifier, contains('verify transfer amounts'));
    });

    test('AgentPersona copyWith updates fields immutably', () {
      final persona = AgentPersona(
        id: 'p1',
        name: 'Persona One',
        description: 'First version',
        assignedSkillIds: ['s1'],
      );

      final updated = persona.copyWith(
        name: 'Persona One Updated',
        assignedSkillIds: ['s1', 's2'],
      );

      expect(updated.id, 'p1');
      expect(updated.name, 'Persona One Updated');
      expect(updated.assignedSkillIds, ['s1', 's2']);
      expect(persona.name, 'Persona One'); // Original untouched
    });
  });
}
