import 'dart:convert';
import 'dart:developer' as developer;
import '../models/custom_skill.dart';
import '../models/agent_persona.dart';
import 'ai_service.dart';
import 'custom_skill_service.dart';
import 'persona_service.dart';

class SkillMatchResult {
  final CustomSkill skill;
  final Map<String, String> extractedParameters;
  final double confidence;

  SkillMatchResult({
    required this.skill,
    required this.extractedParameters,
    this.confidence = 1.0,
  });

  /// Substitute parameter placeholders in a recipe string (e.g. "{recipient}" -> "Alice")
  String applyParameters(String text) {
    String result = text;
    extractedParameters.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}

class SkillRouterService {
  final AiService _aiService;
  final CustomSkillService _skillService = CustomSkillService();
  final PersonaService _personaService = PersonaService();

  SkillRouterService(this._aiService);

  /// Analyzes user request against skills assigned to the active persona.
  /// Returns a matched skill with extracted parameters, or null if no skill applies.
  Future<SkillMatchResult?> routeTask(String userGoal) async {
    final activePersona = _personaService.getActivePersona();
    final availableSkills = _skillService.getSkillsByIds(activePersona.assignedSkillIds);

    if (availableSkills.isEmpty) {
      return null;
    }

    // Fast-path: check if trigger keywords strongly match any skill
    final lowerGoal = userGoal.toLowerCase();
    CustomSkill? keywordCandidate;
    for (final skill in availableSkills) {
      for (final kw in skill.triggerKeywords) {
        if (lowerGoal.contains(kw.toLowerCase())) {
          keywordCandidate = skill;
          break;
        }
      }
      if (keywordCandidate != null) break;
    }

    // Build skill catalog schema for the LLM
    final skillsSchema = availableSkills.map((s) => {
      'id': s.id,
      'name': s.name,
      'description': s.description,
      'parameters': s.parameters.map((p) => {
        'name': p.name,
        'description': p.description,
        'type': p.type,
        'is_required': p.isRequired,
      }).toList(),
    }).toList();

    const systemPrompt = '''
You are a precise task intent router. Analyze the user request against the available skills catalog.
If the user request can be accomplished by one of the skills, return a JSON object with the matched skill ID and extracted parameters.
If no skill matches, return {"matched_skill_id": null}.

RESPONSE FORMAT (JSON ONLY, NO MARKDOWN):
{
  "matched_skill_id": "skill_id_or_null",
  "confidence": 0.95,
  "parameters": {
    "param_name": "extracted_value"
  }
}
''';

    final prompt = '''
USER REQUEST: "$userGoal"

AVAILABLE SKILLS CATALOG:
${jsonEncode(skillsSchema)}

Which skill should handle this, and what are the extracted parameters?
''';

    try {
      final response = await _aiService.sendTaskMessage(systemPrompt, prompt);
      String rawJson = response.content.trim();

      // Extract JSON if wrapped in markdown
      if (rawJson.startsWith('```')) {
        final lines = rawJson.split('\n');
        lines.removeAt(0);
        if (lines.isNotEmpty && lines.last.trim() == '```') {
          lines.removeLast();
        }
        rawJson = lines.join('\n').trim();
      }

      final startIndex = rawJson.indexOf('{');
      final endIndex = rawJson.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        rawJson = rawJson.substring(startIndex, endIndex + 1);
      }

      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;
      final matchedId = parsed['matched_skill_id'] as String?;
      final confidence = (parsed['confidence'] as num?)?.toDouble() ?? 0.0;

      if (matchedId != null && matchedId != 'null' && confidence >= 0.7) {
        final matchedSkill = availableSkills.firstWhere((s) => s.id == matchedId);
        final rawParams = parsed['parameters'] as Map<String, dynamic>? ?? {};
        final Map<String, String> extracted = {};
        rawParams.forEach((k, v) {
          extracted[k] = v?.toString() ?? '';
        });

        // Fill in default values for missing optional parameters
        for (final p in matchedSkill.parameters) {
          if (!extracted.containsKey(p.name) || extracted[p.name]!.isEmpty) {
            if (p.defaultValue != null) {
              extracted[p.name] = p.defaultValue!;
            }
          }
        }

        developer.log('Skill Matched: ${matchedSkill.name} with params $extracted', name: 'SkillRouter');
        return SkillMatchResult(
          skill: matchedSkill,
          extractedParameters: extracted,
          confidence: confidence,
        );
      }
    } catch (e) {
      developer.log('Skill routing LLM error: $e', name: 'SkillRouter');
    }

    // Fallback: If LLM router fails but keyword was an exact hit with no mandatory params
    if (keywordCandidate != null && keywordCandidate.parameters.every((p) => !p.isRequired)) {
      return SkillMatchResult(
        skill: keywordCandidate,
        extractedParameters: {},
        confidence: 0.75,
      );
    }

    return null;
  }
}
