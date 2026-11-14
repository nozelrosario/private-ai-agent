import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/custom_skill.dart';

class CustomSkillService {
  static final CustomSkillService _instance = CustomSkillService._internal();
  factory CustomSkillService() => _instance;
  CustomSkillService._internal();

  List<CustomSkill> _skills = [];
  bool _isLoaded = false;

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/custom_skills.json');
  }

  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final file = await _localFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content) as List;
          _skills = decoded
              .map((item) => CustomSkill.fromJson(item as Map<String, dynamic>))
              .toList();
          _isLoaded = true;
          return;
        }
      }
    } catch (e) {
      // Fall back to defaults on error
    }

    // Seed starter templates if no saved skills exist
    _skills = _getDefaultTemplates();
    await _saveAll();
    _isLoaded = true;
  }

  List<CustomSkill> getAllSkills({bool includeDisabled = false}) {
    if (includeDisabled) return List.unmodifiable(_skills);
    return List.unmodifiable(_skills.where((s) => s.isEnabled));
  }

  List<CustomSkill> getSkillsByIds(List<String> ids) {
    final set = ids.toSet();
    return _skills.where((s) => set.contains(s.id) && s.isEnabled).toList();
  }

  CustomSkill? getSkillById(String id) {
    try {
      return _skills.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSkill(CustomSkill skill) async {
    final index = _skills.indexWhere((s) => s.id == skill.id);
    if (index >= 0) {
      _skills[index] = skill.copyWith(updatedAt: DateTime.now());
    } else {
      _skills.add(skill);
    }
    await _saveAll();
  }

  Future<void> deleteSkill(String id) async {
    _skills.removeWhere((s) => s.id == id);
    await _saveAll();
  }

  Future<void> toggleSkill(String id, bool isEnabled) async {
    final index = _skills.indexWhere((s) => s.id == id);
    if (index >= 0) {
      _skills[index] = _skills[index].copyWith(isEnabled: isEnabled);
      await _saveAll();
    }
  }

  String exportSkillsJson({List<String>? skillIds}) {
    final toExport = skillIds == null
        ? _skills
        : _skills.where((s) => skillIds.contains(s.id)).toList();
    return const JsonEncoder.withIndent('  ')
        .convert(toExport.map((s) => s.toJson()).toList());
  }

  Future<int> importSkillsJson(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return 0;

      int importedCount = 0;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final skill = CustomSkill.fromJson(item);
          final existingIdx = _skills.indexWhere((s) => s.id == skill.id);
          if (existingIdx >= 0) {
            _skills[existingIdx] = skill;
          } else {
            _skills.add(skill);
          }
          importedCount++;
        }
      }
      await _saveAll();
      return importedCount;
    } catch (e) {
      return 0;
    }
  }

  Future<void> resetToDefaults() async {
    _skills = _getDefaultTemplates();
    await _saveAll();
  }

  Future<void> _saveAll() async {
    try {
      final file = await _localFile;
      final encoded = jsonEncode(_skills.map((s) => s.toJson()).toList());
      await file.writeAsString(encoded, flush: true);
    } catch (e) {
      // Error writing skills
    }
  }

  List<CustomSkill> _getDefaultTemplates() {
    return [
      CustomSkill(
        id: 'whatsapp_send',
        name: 'Send WhatsApp Message',
        description: 'Opens WhatsApp, searches for a contact, and sends a message with confirmation.',
        icon: 'chat',
        category: 'Messaging',
        triggerKeywords: ['whatsapp', 'message', 'text', 'send whatsapp'],
        isSystemTemplate: true,
        parameters: [
          SkillParameter(
            name: 'recipient',
            description: 'Name of the contact or group to message',
            type: 'string',
            isRequired: true,
          ),
          SkillParameter(
            name: 'message',
            description: 'Text content of the message to send',
            type: 'string',
            isRequired: true,
          ),
        ],
        steps: [
          RecipeStep(
            stepNumber: 1,
            instruction: 'Open WhatsApp.',
            targetAppPackage: 'com.whatsapp',
            actionTypeHint: 'open_app',
          ),
          RecipeStep(
            stepNumber: 2,
            instruction: 'Click the Search icon or search bar at the top.',
            expectedElementHint: 'Search',
            actionTypeHint: 'click_text',
          ),
          RecipeStep(
            stepNumber: 3,
            instruction: 'Type "{recipient}" into the search bar to locate the contact.',
            actionTypeHint: 'type_text',
          ),
          RecipeStep(
            stepNumber: 4,
            instruction: 'Click on "{recipient}" in the search results list to open the conversation.',
            expectedElementHint: '{recipient}',
            actionTypeHint: 'click_text',
          ),
          RecipeStep(
            stepNumber: 5,
            instruction: 'Type "{message}" into the message input field at the bottom.',
            actionTypeHint: 'type_text',
          ),
          RecipeStep(
            stepNumber: 6,
            instruction: 'Click the Send button to send the message to {recipient}.',
            expectedElementHint: 'Send',
            actionTypeHint: 'click_text',
            requiresConfirmation: true,
            confirmationMessage: 'Send WhatsApp message "{message}" to {recipient}?',
          ),
        ],
      ),
      CustomSkill(
        id: 'youtube_search',
        name: 'Search & Play YouTube',
        description: 'Launches YouTube, searches for a topic, and plays the first video.',
        icon: 'play_circle_filled',
        category: 'Media',
        triggerKeywords: ['youtube', 'video', 'watch', 'play'],
        isSystemTemplate: true,
        parameters: [
          SkillParameter(
            name: 'query',
            description: 'Search query or video title to find on YouTube',
            type: 'string',
            isRequired: true,
          ),
        ],
        steps: [
          RecipeStep(
            stepNumber: 1,
            instruction: 'Open YouTube.',
            targetAppPackage: 'com.google.android.youtube',
            actionTypeHint: 'open_app',
          ),
          RecipeStep(
            stepNumber: 2,
            instruction: 'Click the Search button at the top right.',
            expectedElementHint: 'Search',
            actionTypeHint: 'click_text',
          ),
          RecipeStep(
            stepNumber: 3,
            instruction: 'Type "{query}" into the search field and submit.',
            actionTypeHint: 'type_text',
          ),
          RecipeStep(
            stepNumber: 4,
            instruction: 'Press enter or click search icon to submit query.',
            actionTypeHint: 'press_enter',
          ),
          RecipeStep(
            stepNumber: 5,
            instruction: 'Click on the first video result in the list to start playback.',
            actionTypeHint: 'click_at',
          ),
        ],
      ),
      CustomSkill(
        id: 'wifi_toggle',
        name: 'Toggle Wi-Fi Settings',
        description: 'Navigates to Android Settings to turn Wi-Fi on or off.',
        icon: 'wifi',
        category: 'System',
        triggerKeywords: ['wifi', 'wi-fi', 'internet', 'network'],
        isSystemTemplate: true,
        parameters: [
          SkillParameter(
            name: 'state',
            description: 'Desired Wi-Fi state: "on" or "off"',
            type: 'string',
            isRequired: false,
            defaultValue: 'on',
          ),
        ],
        steps: [
          RecipeStep(
            stepNumber: 1,
            instruction: 'Open Settings.',
            targetAppPackage: 'com.android.settings',
            actionTypeHint: 'open_app',
          ),
          RecipeStep(
            stepNumber: 2,
            instruction: 'Click on Network & internet or Connections.',
            expectedElementHint: 'Network & internet',
            actionTypeHint: 'click_text',
          ),
          RecipeStep(
            stepNumber: 3,
            instruction: 'Click on Internet or Wi-Fi to view the toggle.',
            expectedElementHint: 'Internet',
            actionTypeHint: 'click_text',
          ),
          RecipeStep(
            stepNumber: 4,
            instruction: 'Toggle the Wi-Fi switch to turn it {state}.',
            actionTypeHint: 'click_text',
          ),
        ],
      ),
    ];
  }
}
