import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/agent_persona.dart';
import '../models/custom_skill.dart';
import '../models/autonomous_routine.dart';
import '../services/custom_skill_service.dart';
import '../services/persona_service.dart';
import '../services/routine_service.dart';
import '../services/routine_scheduler_service.dart';
import '../services/screen_automation_service.dart';
import 'skill_editor_screen.dart';
import 'persona_editor_screen.dart';
import 'routine_editor_screen.dart';

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
  final RoutineService _routineService = RoutineService();
  final RoutineSchedulerService _schedulerService = RoutineSchedulerService();
  final ScreenAutomationService _screenService = ScreenAutomationService();

  List<AgentPersona> _personas = [];
  List<CustomSkill> _skills = [];
  List<AutonomousRoutine> _routines = [];
  String _activePersonaId = '';
  String _selectedCategory = 'All';
  String? _triggeringRoutineId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(_handleTabChange);
    _loadData();
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadData() async {
    await _skillService.init();
    await _personaService.init();
    await _routineService.init();
    setState(() {
      _personas = _personaService.getAllPersonas();
      _skills = _skillService.getAllSkills(includeDisabled: true);
      _routines = _routineService.getAllRoutines();
      _activePersonaId = _personaService.getActivePersona().id;
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
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

  // --- PERSONA EDITOR (FULL-FEATURED COMPOSER) ---
  void _openPersonaDialog([AgentPersona? personaToEdit]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonaEditorScreen(personaToEdit: personaToEdit),
      ),
    ).then((_) => _loadData());
  }

  // --- UNIFIED CATALOG EXPORT / IMPORT (FILE & CLIPBOARD) ---
  void _showCatalogExportDialog({
    required String title,
    required String defaultFileName,
    required String jsonStr,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonStr,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final path = await _screenService.saveJsonFileToDownloads(
                        defaultFileName,
                        jsonStr,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(path != null
                                ? 'Exported file to: $path'
                                : 'Failed to save file to Downloads'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Save to Downloads'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final tempDir = await getTemporaryDirectory();
                        final tempFile = File('${tempDir.path}/$defaultFileName');
                        await tempFile.writeAsString(jsonStr);
                        if (ctx.mounted) Navigator.pop(ctx);
                        await Share.shareXFiles(
                          [XFile(tempFile.path, mimeType: 'application/json')],
                          text: 'PrivateAgent Export: $defaultFileName',
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Share failed: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Share File'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonStr));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('JSON copied to clipboard!')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy JSON'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showCatalogImportDialog({
    required String title,
    required String hintText,
    required Future<int> Function(String jsonStr) onImport,
  }) {
    final inputCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  try {
                    final content = await _screenService.pickJsonFile();
                    if (content == null || content.isEmpty) return;
                    final count = await onImport(content);
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Successfully imported $count items from file!'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Import error: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Pick File from Device / SD Card'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('OR PASTE JSON', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              TextField(
                controller: inputCtrl,
                maxLines: 6,
                decoration: InputDecoration(
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = inputCtrl.text.trim();
              if (text.isEmpty) return;
              try {
                final count = await onImport(text);
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Successfully imported $count items!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import error: $e')),
                  );
                }
              }
            },
            child: const Text('Import Text'),
          ),
        ],
      ),
    );
  }

  // --- SKILLS EXPORT / IMPORT JSON ---
  void _showExportDialog() {
    _showCatalogExportDialog(
      title: 'Export Skills Catalog',
      defaultFileName: 'privateagent_skills_${DateTime.now().millisecondsSinceEpoch}.json',
      jsonStr: _skillService.exportSkillsJson(),
    );
  }

  void _showImportDialog() {
    _showCatalogImportDialog(
      title: 'Import Skills from JSON',
      hintText: 'Paste skills JSON array here...',
      onImport: (content) => _skillService.importSkillsJson(content.trim()),
    );
  }

  // --- PERSONAS EXPORT / IMPORT JSON ---
  void _showPersonaExportDialog() {
    _showCatalogExportDialog(
      title: 'Export Personas Catalog',
      defaultFileName: 'privateagent_personas_${DateTime.now().millisecondsSinceEpoch}.json',
      jsonStr: _personaService.exportPersonasJson(),
    );
  }

  void _showPersonaImportDialog() {
    _showCatalogImportDialog(
      title: 'Import Personas from JSON',
      hintText: 'Paste personas JSON array here...',
      onImport: (content) => _personaService.importPersonasJson(content.trim()),
    );
  }

  Future<void> _confirmResetDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset All Templates?'),
        content: const Text(
          'This will restore all default skills and agent personas to their initial configurations.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset to Defaults'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _skillService.resetToDefaults();
      await _personaService.resetToDefaults();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All templates reset to defaults!')),
        );
      }
    }
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
            Tab(icon: Icon(Icons.repeat_rounded), text: 'Routines'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'JSON Actions & Reset',
            onSelected: (val) {
              if (val == 'export_skills') _showExportDialog();
              if (val == 'import_skills') _showImportDialog();
              if (val == 'export_personas') _showPersonaExportDialog();
              if (val == 'import_personas') _showPersonaImportDialog();
              if (val == 'export_routines') _showRoutineExportDialog();
              if (val == 'import_routines') _showRoutineImportDialog();
              if (val == 'reset_defaults') _confirmResetDefaults();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export_skills',
                child: Row(children: [Icon(Icons.file_download_outlined, size: 18), SizedBox(width: 8), Text('Export Skills JSON')]),
              ),
              const PopupMenuItem(
                value: 'import_skills',
                child: Row(children: [Icon(Icons.file_upload_outlined, size: 18), SizedBox(width: 8), Text('Import Skills JSON')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export_personas',
                child: Row(children: [Icon(Icons.file_download_outlined, size: 18), SizedBox(width: 8), Text('Export Personas JSON')]),
              ),
              const PopupMenuItem(
                value: 'import_personas',
                child: Row(children: [Icon(Icons.file_upload_outlined, size: 18), SizedBox(width: 8), Text('Import Personas JSON')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export_routines',
                child: Row(children: [Icon(Icons.file_download_outlined, size: 18), SizedBox(width: 8), Text('Export Routines JSON')]),
              ),
              const PopupMenuItem(
                value: 'import_routines',
                child: Row(children: [Icon(Icons.file_upload_outlined, size: 18), SizedBox(width: 8), Text('Import Routines JSON')]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset_defaults',
                child: Row(children: [Icon(Icons.restore_rounded, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Reset All Defaults')]),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPersonasTab(),
          _buildSkillsTab(),
          _buildRoutinesTab(),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final currentIdx = (_tabController.animation?.value ?? _tabController.index).round();
          String label = 'New Persona';
          IconData icon = Icons.person_add_outlined;
          if (currentIdx == 1) {
            label = 'New Skill';
            icon = Icons.add_task_rounded;
          } else if (currentIdx == 2) {
            label = 'New Routine';
            icon = Icons.add_alarm_rounded;
          }

          return FloatingActionButton.extended(
            onPressed: () {
              if (currentIdx == 0) {
                _openPersonaDialog();
              } else if (currentIdx == 1) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SkillEditorScreen()),
                ).then((_) => _loadData());
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RoutineEditorScreen()),
                ).then((_) => _loadData());
              }
            },
            icon: Icon(icon),
            label: Text(label),
          );
        },
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

  void _showRoutineExportDialog() {
    _showCatalogExportDialog(
      title: 'Export Routines Catalog',
      defaultFileName: 'privateagent_routines_${DateTime.now().millisecondsSinceEpoch}.json',
      jsonStr: _routineService.exportCatalogJson(),
    );
  }

  void _showRoutineImportDialog() {
    _showCatalogImportDialog(
      title: 'Import Routines from JSON',
      hintText: 'Paste routines JSON array here...',
      onImport: (content) async {
        final count = await _routineService.importCatalogJson(content.trim());
        await _schedulerService.syncAllSchedules();
        return count;
      },
    );
  }

  Widget _buildRoutinesTab() {
    if (_routines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.repeat_rounded,
                  size: 64, color: Colors.grey.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text('No Autonomous Routines Yet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Create a routine to periodically automate WhatsApp replies, notifications, or custom device loops.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RoutineEditorScreen()),
                  ).then((_) => _loadData());
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create Starter Routine'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _routines.length,
      itemBuilder: (context, index) {
        final routine = _routines[index];
        final isTriggering = _triggeringRoutineId == routine.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: routine.isEnabled
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.12)
                            : Colors.grey.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.repeat_rounded,
                        color: routine.isEnabled
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            routine.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            routine.description.isNotEmpty
                                ? routine.description
                                : routine.goalPrompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: routine.isEnabled,
                      onChanged: (val) async {
                        await _routineService.toggleRoutine(routine.id, val);
                        if (val) {
                          await _schedulerService.scheduleRoutine(
                              routine.copyWith(isEnabled: true));
                        } else {
                          await _schedulerService.cancelRoutine(routine.id);
                        }
                        await _loadData();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.person_pin_rounded, size: 14),
                      label: Text(routine.personaId,
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: Icon(
                        routine.executionMode == RoutineExecutionMode.autonomous
                            ? Icons.bolt_rounded
                            : Icons.verified_user_rounded,
                        size: 14,
                        color: routine.executionMode ==
                                RoutineExecutionMode.autonomous
                            ? Colors.amber
                            : Colors.blue,
                      ),
                      label: Text(
                        routine.executionMode == RoutineExecutionMode.autonomous
                            ? 'Auto-Reply'
                            : 'Supervised',
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: const Icon(Icons.timer_outlined, size: 14),
                      label: Text(
                        routine.schedule.type == ScheduleType.interval
                            ? 'Every ${routine.schedule.intervalMinutes}m'
                            : 'Daily ${routine.schedule.dailyHour}:${routine.schedule.dailyMinute}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (routine.lastRunStatus != null)
                      Chip(
                        avatar: Icon(
                          routine.lastRunStatus == 'success'
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 14,
                          color: routine.lastRunStatus == 'success'
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                        label: Text(
                          'Last: ${routine.lastRunStatus}',
                          style: TextStyle(
                            fontSize: 11,
                            color: routine.lastRunStatus == 'success'
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: isTriggering
                          ? null
                          : () async {
                              setState(
                                  () => _triggeringRoutineId = routine.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Triggering routine: "${routine.name}"...')),
                              );
                              final res =
                                  await _schedulerService.triggerRoutine(
                                routine.id,
                                isManual: true,
                              );
                              if (mounted) {
                                setState(() => _triggeringRoutineId = null);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Routine completed: $res')),
                                );
                                await _loadData();
                              }
                            },
                      icon: isTriggering
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text(isTriggering ? 'Running...' : 'Run Now'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RoutineEditorScreen(routineToEdit: routine),
                          ),
                        ).then((_) => _loadData());
                      },
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Edit'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: Colors.redAccent),
                      tooltip: 'Delete Routine',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Routine?'),
                            content: Text(
                                'Are you sure you want to delete "${routine.name}"?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _schedulerService.cancelRoutine(routine.id);
                          await _routineService.deleteRoutine(routine.id);
                          await _loadData();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
