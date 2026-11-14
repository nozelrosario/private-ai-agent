import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_persona.dart';
import 'custom_skill_service.dart';

class PersonaService {
  static final PersonaService _instance = PersonaService._internal();
  factory PersonaService() => _instance;
  PersonaService._internal();

  List<AgentPersona> _personas = [];
  String _activePersonaId = 'general_assistant';
  bool _isLoaded = false;

  final ValueNotifier<AgentPersona?> activePersonaNotifier = ValueNotifier(null);

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/personas.json');
  }

  Future<void> init() async {
    if (_isLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _activePersonaId = prefs.getString('active_persona_id') ?? 'general_assistant';

    try {
      final file = await _localFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content) as List;
          _personas = decoded
              .map((item) => AgentPersona.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}

    if (_personas.isEmpty) {
      _personas = _getDefaultPersonas();
      await _saveAll();
    }

    _updateActiveNotifier();
    _isLoaded = true;
  }

  List<AgentPersona> getAllPersonas() {
    return List.unmodifiable(_personas);
  }

  AgentPersona getActivePersona() {
    try {
      return _personas.firstWhere((p) => p.id == _activePersonaId);
    } catch (_) {
      return _personas.isNotEmpty ? _personas.first : _getDefaultPersonas().first;
    }
  }

  Future<void> setActivePersona(String id) async {
    if (_personas.any((p) => p.id == id)) {
      _activePersonaId = id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_persona_id', id);
      _updateActiveNotifier();
    }
  }

  Future<void> savePersona(AgentPersona persona) async {
    final index = _personas.indexWhere((p) => p.id == persona.id);
    if (index >= 0) {
      _personas[index] = persona;
    } else {
      _personas.add(persona);
    }
    await _saveAll();
    if (_activePersonaId == persona.id) {
      _updateActiveNotifier();
    }
  }

  Future<void> deletePersona(String id) async {
    if (_personas.length <= 1) return; // Prevent deleting the last persona
    _personas.removeWhere((p) => p.id == id);
    if (_activePersonaId == id) {
      _activePersonaId = _personas.first.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_persona_id', _activePersonaId);
    }
    await _saveAll();
    _updateActiveNotifier();
  }

  void _updateActiveNotifier() {
    activePersonaNotifier.value = getActivePersona();
  }

  String exportPersonasJson() {
    return const JsonEncoder.withIndent('  ')
        .convert(_personas.map((p) => p.toJson()).toList());
  }

  Future<int> importPersonasJson(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) return 0;
      int count = 0;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final persona = AgentPersona.fromJson(item);
          final index = _personas.indexWhere((p) => p.id == persona.id);
          if (index >= 0) {
            _personas[index] = persona;
          } else {
            _personas.add(persona);
          }
          count++;
        }
      }
      await _saveAll();
      _updateActiveNotifier();
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> resetToDefaults() async {
    _personas = _getDefaultPersonas();
    _activePersonaId = _personas.first.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_persona_id', _activePersonaId);
    await _saveAll();
    _updateActiveNotifier();
  }

  Future<void> _saveAll() async {
    try {
      final file = await _localFile;
      final encoded = jsonEncode(_personas.map((p) => p.toJson()).toList());
      await file.writeAsString(encoded, flush: true);
    } catch (_) {}
  }

  List<AgentPersona> _getDefaultPersonas() {
    return [
      AgentPersona(
        id: 'general_assistant',
        name: 'General Assistant',
        description: 'Omni-purpose phone automation and conversation assistant with all skills enabled.',
        avatarIcon: 'smart_toy',
        systemPromptModifier: 'You are an all-around Android automation assistant. Maintain clear and helpful reasoning.',
        assignedSkillIds: ['whatsapp_send', 'youtube_search', 'wifi_toggle'],
        isDefault: true,
      ),
      AgentPersona(
        id: 'messaging_specialist',
        name: 'Messaging Agent',
        description: 'Focused exclusively on messaging, chats, contacts, calls, and email communications.',
        avatarIcon: 'chat',
        systemPromptModifier: 'You are a messaging specialist. Prioritize communication accuracy and always verify recipient contact names carefully before sending.',
        assignedSkillIds: ['whatsapp_send'],
      ),
      AgentPersona(
        id: 'device_operator',
        name: 'Device Operator',
        description: 'Expert in system settings, Wi-Fi, Bluetooth, volume, alarms, and OS controls.',
        avatarIcon: 'settings_suggest',
        systemPromptModifier: 'You are a device settings operator. Execute system modifications concisely and confirm status changes cleanly.',
        assignedSkillIds: ['wifi_toggle'],
      ),
      AgentPersona(
        id: 'media_agent',
        name: 'Media & Entertainment',
        description: 'Specialized in YouTube, music, media browsing, and video playback.',
        avatarIcon: 'play_circle_filled',
        systemPromptModifier: 'You are a media navigation assistant. Help find videos, podcasts, and media efficiently.',
        assignedSkillIds: ['youtube_search'],
      ),
    ];
  }
}
