import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_persona.dart';
import '../models/custom_skill.dart';
import '../services/custom_skill_service.dart';
import '../services/persona_service.dart';

class PersonaEditorScreen extends StatefulWidget {
  final AgentPersona? personaToEdit;

  const PersonaEditorScreen({super.key, this.personaToEdit});

  @override
  State<PersonaEditorScreen> createState() => _PersonaEditorScreenState();
}

class _PersonaEditorScreenState extends State<PersonaEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final PersonaService _personaService = PersonaService();
  final CustomSkillService _skillService = CustomSkillService();

  // Visual Form Controllers
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _promptController;
  late TextEditingController _jsonController;
  late TextEditingController _skillSearchController;

  String _selectedAvatar = 'smart_toy';
  List<String> _assignedSkillIds = [];
  bool _isDefault = false;
  double _temperature = 1.0;
  String? _jsonError;
  String _skillCategoryFilter = 'All';

  List<CustomSkill> _allSkills = [];

  final List<Map<String, dynamic>> _avatarOptions = [
    {'key': 'smart_toy', 'label': 'AI Agent', 'icon': Icons.smart_toy_rounded},
    {'key': 'chat', 'label': 'Chat', 'icon': Icons.chat_bubble_outline_rounded},
    {'key': 'settings_suggest', 'label': 'Operator', 'icon': Icons.settings_suggest_rounded},
    {'key': 'play_circle_filled', 'label': 'Media', 'icon': Icons.play_circle_fill_rounded},
    {'key': 'account_balance', 'label': 'Finance', 'icon': Icons.account_balance_rounded},
    {'key': 'shopping_cart', 'label': 'Shop', 'icon': Icons.shopping_cart_rounded},
    {'key': 'work', 'label': 'Work', 'icon': Icons.work_rounded},
    {'key': 'star', 'label': 'Star', 'icon': Icons.star_rounded},
  ];

  final List<Map<String, String>> _behaviorTemplates = [
    {
      'title': 'General Assistant',
      'prompt': 'You are an all-around Android automation assistant. Maintain clear and helpful reasoning.',
    },
    {
      'title': 'Strict Operator',
      'prompt': 'You are a high-speed device operator. Execute native actions concisely with minimal conversation.',
    },
    {
      'title': 'Cautious & Safe',
      'prompt': 'Prioritize user safety. Always require explicit confirmation before sending messages or altering settings.',
    },
    {
      'title': 'Media Specialist',
      'prompt': 'Specialized in video playback, music streaming, and entertainment navigation.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);

    final p = widget.personaToEdit;
    _nameController = TextEditingController(text: p?.name ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _promptController = TextEditingController(text: p?.systemPromptModifier ?? '');
    _selectedAvatar = p?.avatarIcon ?? 'smart_toy';
    _assignedSkillIds = p != null ? List.from(p.assignedSkillIds) : [];
    _isDefault = p?.isDefault ?? false;
    _temperature = p?.temperatureOverride ?? 1.0;

    _jsonController = TextEditingController();
    _skillSearchController = TextEditingController();

    _loadSkills();
    _syncVisualToJson();
  }

  Future<void> _loadSkills() async {
    await _skillService.init();
    setState(() {
      _allSkills = _skillService.getAllSkills(includeDisabled: true);
      // Default new personas to all skills if none set
      if (widget.personaToEdit == null && _assignedSkillIds.isEmpty) {
        _assignedSkillIds = _allSkills.map((s) => s.id).toList();
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _promptController.dispose();
    _jsonController.dispose();
    _skillSearchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      // Switched to JSON tab -> update JSON from visual form
      _syncVisualToJson();
    } else {
      // Switched to Visual tab -> parse JSON into form
      _syncJsonToVisual();
    }
  }

  AgentPersona _buildPersonaFromForm() {
    return AgentPersona(
      id: widget.personaToEdit?.id ??
          'persona_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim().isEmpty ? 'New Agent Persona' : _nameController.text.trim(),
      description: _descController.text.trim(),
      avatarIcon: _selectedAvatar,
      systemPromptModifier: _promptController.text.trim(),
      assignedSkillIds: _assignedSkillIds,
      isDefault: _isDefault,
      temperatureOverride: _temperature,
    );
  }

  void _syncVisualToJson() {
    final persona = _buildPersonaFromForm();
    const encoder = JsonEncoder.withIndent('  ');
    _jsonController.text = encoder.convert(persona.toJson());
    setState(() {
      _jsonError = null;
    });
  }

  bool _syncJsonToVisual() {
    final raw = _jsonController.text.trim();
    if (raw.isEmpty) return true;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = AgentPersona.fromJson(decoded);

      setState(() {
        _nameController.text = parsed.name;
        _descController.text = parsed.description;
        _promptController.text = parsed.systemPromptModifier;
        _selectedAvatar = parsed.avatarIcon;
        _assignedSkillIds = List.from(parsed.assignedSkillIds);
        _isDefault = parsed.isDefault;
        _temperature = parsed.temperatureOverride ?? 1.0;
        _jsonError = null;
      });
      return true;
    } catch (e) {
      setState(() {
        _jsonError = 'Invalid JSON: $e';
      });
      return false;
    }
  }

  Future<void> _savePersona() async {
    // If on JSON tab, ensure JSON parses correctly first
    if (_tabController.index == 1) {
      final success = _syncJsonToVisual();
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_jsonError ?? 'Please fix JSON errors before saving.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    } else {
      if (!_formKey.currentState!.validate()) return;
    }

    final persona = _buildPersonaFromForm();
    await _personaService.savePersona(persona);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Persona "${persona.name}" saved successfully!'),
          backgroundColor: Colors.indigoAccent,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  IconData _getIconData(String key) {
    for (final opt in _avatarOptions) {
      if (opt['key'] == key) return opt['icon'] as IconData;
    }
    return Icons.smart_toy_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.personaToEdit == null ? 'Create Agent Persona' : 'Edit Persona',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded), text: 'Visual Studio'),
            Tab(icon: Icon(Icons.data_object_rounded), text: 'JSON Editor'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save Persona',
            onPressed: _savePersona,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisualTab(isDark),
          _buildJsonTab(isDark),
        ],
      ),
    );
  }

  // --- TAB 1: VISUAL STUDIO ---
  Widget _buildVisualTab(bool isDark) {
    final filteredSkills = _allSkills.where((s) {
      final matchesCat = _skillCategoryFilter == 'All' || s.category == _skillCategoryFilter;
      final query = _skillSearchController.text.toLowerCase().trim();
      final matchesQuery = query.isEmpty ||
          s.name.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query);
      return matchesCat && matchesQuery;
    }).toList();

    final categories = ['All', ...{for (var s in _allSkills) s.category}];

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Basic Profile Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.15),
                        child: Icon(
                          _getIconData(_selectedAvatar),
                          color: Theme.of(context).primaryColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Persona Identity',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Define the agent role and display appearance',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Persona Name *',
                      hintText: 'e.g. Work Productivity Specialist',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Role Overview / Summary',
                      hintText: 'e.g. Handles emails, slack chats, and calendar tasks',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Avatar Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _avatarOptions.map((opt) {
                      final isSelected = _selectedAvatar == opt['key'];
                      return ChoiceChip(
                        avatar: Icon(opt['icon'] as IconData, size: 16),
                        label: Text(opt['label'] as String),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedAvatar = opt['key'] as String);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Behavioral Prompt Studio
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology_outlined, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Behavioral Prompt Studio',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'System prompt instructions injected into the LLM context when this persona is active.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  const Text('Quick Style Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _behaviorTemplates.map((t) {
                      return ActionChip(
                        avatar: const Icon(Icons.auto_awesome_rounded, size: 14),
                        label: Text(t['title']!, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          setState(() {
                            _promptController.text = t['prompt']!;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _promptController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Custom System Instructions',
                      hintText: 'e.g. Prioritize communication accuracy and always verify recipient contact names.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Creativity (Temperature):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('${_temperature.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _temperature,
                    min: 0.0,
                    max: 1.5,
                    divisions: 15,
                    label: _temperature.toStringAsFixed(1),
                    onChanged: (val) => setState(() => _temperature = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Scoped Skills Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          const Text('Scoped Skills', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_assignedSkillIds.length} / ${_allSkills.length} assigned',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Only assigned skills are accessible to this agent persona, preventing cross-domain confusion.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  // Search & Filter Row
                  TextField(
                    controller: _skillSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Search skills...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Category Chips & Select/Clear All
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: categories.map((cat) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(cat, style: const TextStyle(fontSize: 11)),
                                  selected: _skillCategoryFilter == cat,
                                  onSelected: (selected) {
                                    if (selected) setState(() => _skillCategoryFilter = cat);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_assignedSkillIds.length == _allSkills.length) {
                              _assignedSkillIds.clear();
                            } else {
                              _assignedSkillIds = _allSkills.map((s) => s.id).toList();
                            }
                          });
                        },
                        child: Text(
                          _assignedSkillIds.length == _allSkills.length ? 'Clear All' : 'Select All',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),

                  if (filteredSkills.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('No skills match your search/filter.', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ...filteredSkills.map((skill) {
                      final isAssigned = _assignedSkillIds.contains(skill.id);
                      return CheckboxListTile(
                        value: isAssigned,
                        contentPadding: EdgeInsets.zero,
                        title: Text(skill.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: Text(
                          '${skill.category} • ${skill.steps.length} steps • ${skill.parameters.length} params',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isAssigned
                                ? Theme.of(context).primaryColor.withOpacity(0.12)
                                : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.auto_stories_rounded,
                            size: 18,
                            color: isAssigned ? Theme.of(context).primaryColor : Colors.grey,
                          ),
                        ),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _assignedSkillIds.add(skill.id);
                            } else {
                              _assignedSkillIds.remove(skill.id);
                            }
                          });
                        },
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 4. Default Toggle
          SwitchListTile(
            title: const Text('Default Persona', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Use this persona when launching PrivateAgent'),
            value: _isDefault,
            onChanged: (val) => setState(() => _isDefault = val),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _savePersona,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save Agent Persona', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 2: RAW JSON CODE EDITOR ---
  Widget _buildJsonTab(bool isDark) {
    return Column(
      children: [
        // Action toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              const Icon(Icons.code_rounded, size: 18),
              const SizedBox(width: 8),
              const Text('Persona JSON Schema', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.format_align_left_rounded, size: 16),
                label: const Text('Format', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  try {
                    final obj = jsonDecode(_jsonController.text);
                    const encoder = JsonEncoder.withIndent('  ');
                    _jsonController.text = encoder.convert(obj);
                    setState(() => _jsonError = null);
                  } catch (e) {
                    setState(() => _jsonError = 'Format error: $e');
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copy JSON',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _jsonController.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Persona JSON copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
        ),

        if (_jsonError != null)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.redAccent.withOpacity(0.15),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _jsonError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _jsonController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.4,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{\n  "id": "...",\n  "name": "..."\n}',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
