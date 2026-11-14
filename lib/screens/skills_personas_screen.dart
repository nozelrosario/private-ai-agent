import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_persona.dart';
import '../models/custom_skill.dart';
import '../services/custom_skill_service.dart';
import '../services/persona_service.dart';
import 'skill_editor_screen.dart';

class SkillsPersonasScreen extends StatefulWidget {
  final int initialTabIndex;

  const SkillsPersonasScreen({super.key, this.initialTabIndex = 0});

  @override
  State<SkillsPersonasScreen> createState() => _SkillsPersonasScreenState();
}

class _SkillsPersonasScreenState extends State<SkillsPersonasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CustomSkillService _skillService = CustomSkillService();
  final PersonaService _personaService = PersonaService();

  List<AgentPersona> _personas = [];
  List<CustomSkill> _skills = [];
  String _activePersonaId = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadData();
  }

  Future<void> _loadData() async {
    await _skillService.init();
    await _personaService.init();
    setState(() {
      _personas = _personaService.getAllPersonas();
      _skills = _skillService.getAllSkills(includeDisabled: true);
      _activePersonaId = _personaService.getActivePersona().id;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _getIconData(String iconKey) {
    switch (iconKey) {
      case 'smart_toy':
        return Icons.smart_toy_rounded;
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
      case 'settings_suggest':
        return Icons.settings_suggest_rounded;
      case 'play_circle_filled':
        return Icons.play_circle_fill_rounded;
      case 'wifi':
        return Icons.wifi_rounded;
      case 'alarm':
        return Icons.alarm_rounded;
      case 'shopping_cart':
        return Icons.shopping_cart_rounded;
      case 'email':
        return Icons.email_rounded;
      case 'navigation':
        return Icons.navigation_rounded;
      case 'photo_camera':
        return Icons.camera_alt_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  // --- PERSONA DIALOG (CREATE / EDIT) ---
  void _openPersonaDialog([AgentPersona? personaToEdit]) {
    final nameCtrl = TextEditingController(text: personaToEdit?.name ?? '');
    final descCtrl = TextEditingController(text: personaToEdit?.description ?? '');
    final promptCtrl = TextEditingController(text: personaToEdit?.systemPromptModifier ?? '');
    String avatarIcon = personaToEdit?.avatarIcon ?? 'smart_toy';
    List<String> assignedSkills = personaToEdit != null
        ? List.from(personaToEdit.assignedSkillIds)
        : _skills.map((s) => s.id).toList(); // Default to all skills

    final iconChoices = ['smart_toy', 'chat', 'settings_suggest', 'play_circle_filled', 'star'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(personaToEdit == null ? 'Create Agent Persona' : 'Edit Persona'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Persona Name *',
                      hintText: 'e.g. Work Productivity Agent',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Role Description',
                      hintText: 'e.g. Focused on Slack, emails, calendar',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: promptCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Custom System Prompt Modifier',
                      hintText: 'Special behavioral instructions or personality',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Avatar Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: iconChoices
                        .map((ic) => ChoiceChip(
                              label: Icon(_getIconData(ic), size: 18),
                              selected: avatarIcon == ic,
                              onSelected: (selected) {
                                if (selected) setDialogState(() => avatarIcon = ic);
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Scoped Skills (Available to this Persona)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ..._skills.map((skill) {
                    final isAssigned = assignedSkills.contains(skill.id);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(skill.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(skill.category, style: const TextStyle(fontSize: 11)),
                      value: isAssigned,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            assignedSkills.add(skill.id);
                          } else {
                            assignedSkills.remove(skill.id);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final newPersona = AgentPersona(
                  id: personaToEdit?.id ?? 'persona_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  systemPromptModifier: promptCtrl.text.trim(),
                  avatarIcon: avatarIcon,
                  assignedSkillIds: assignedSkills,
                  isDefault: personaToEdit?.isDefault ?? false,
                );
                await _personaService.savePersona(newPersona);
                await _loadData();
                Navigator.pop(ctx);
              },
              child: const Text('Save Persona'),
            ),
          ],
        ),
      ),
    );
  }

  // --- EXPORT / IMPORT JSON ---
  void _showExportDialog() {
    final jsonStr = _skillService.exportSkillsJson();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Skills Catalog (JSON)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonStr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Skills JSON copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    final inputCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Skills from JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: inputCtrl,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Paste skills JSON array here...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final count = await _skillService.importSkillsJson(inputCtrl.text.trim());
              Navigator.pop(ctx);
              await _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Successfully imported $count skills!')),
              );
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personas & Skills Hub', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.psychology_rounded), text: 'Agent Personas'),
            Tab(icon: Icon(Icons.auto_stories_rounded), text: 'Skills Library'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import Skills JSON',
            onPressed: _showImportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Skills JSON',
            onPressed: _showExportDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPersonasTab(),
          _buildSkillsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _openPersonaDialog();
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SkillEditorScreen()),
            ).then((_) => _loadData());
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(_tabController.index == 0 ? 'New Persona' : 'New Skill'),
      ),
    );
  }

  // --- TAB 1: PERSONAS ---
  Widget _buildPersonasTab() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _personas.length,
      itemBuilder: (context, index) {
        final persona = _personas[index];
        final isActive = persona.id == _activePersonaId;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIconData(persona.avatarIcon),
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            persona.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            persona.description,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    if (isActive)
                      Chip(
                        label: const Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: EdgeInsets.zero,
                      )
                    else
                      OutlinedButton(
                        onPressed: () async {
                          await _personaService.setActivePersona(persona.id);
                          setState(() => _activePersonaId = persona.id);
                        },
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Activate'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.bolt_rounded, size: 14),
                      label: Text('${persona.assignedSkillIds.length} Scoped Skills', style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (persona.isDefault)
                      const Chip(
                        label: Text('Default Template', style: TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openPersonaDialog(persona),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit'),
                    ),
                    if (!persona.isDefault && _personas.length > 1) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Persona'),
                              content: Text('Delete "${persona.name}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _personaService.deletePersona(persona.id);
                            await _loadData();
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                        label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 2: SKILLS ---
  Widget _buildSkillsTab() {
    final categories = ['All', ...{..._skills.map((s) => s.category)}];
    final filteredSkills = _selectedCategory == 'All'
        ? _skills
        : _skills.where((s) => s.category == _selectedCategory).toList();

    return Column(
      children: [
        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: categories
                .map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedCategory = cat);
                        },
                      ),
                    ))
                .toList(),
          ),
        ),

        // Skills List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: filteredSkills.length,
            itemBuilder: (context, index) {
              final skill = filteredSkills[index];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ExpansionTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getIconData(skill.icon), color: Theme.of(context).colorScheme.primary, size: 20),
                  ),
                  title: Text(skill.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                  subtitle: Text(
                    '${skill.category} • ${skill.steps.length} Steps • ${skill.parameters.length} Vars',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Switch(
                    value: skill.isEnabled,
                    onChanged: (val) async {
                      await _skillService.toggleSkill(skill.id, val);
                      await _loadData();
                    },
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(skill.description, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
                          const SizedBox(height: 12),
                          const Text('Recipe SOP Steps:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          ...skill.steps.asMap().entries.map((entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${entry.key + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    Expanded(
                                      child: Text(
                                        entry.value.instruction,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    if (entry.value.requiresConfirmation)
                                      const Icon(Icons.shield_rounded, size: 14, color: Colors.amber),
                                  ],
                                ),
                              )),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SkillEditorScreen(skillToEdit: skill),
                                    ),
                                  ).then((_) => _loadData());
                                },
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Edit Recipe'),
                              ),
                              if (!skill.isSystemTemplate) ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    await _skillService.deleteSkill(skill.id);
                                    await _loadData();
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                  label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
