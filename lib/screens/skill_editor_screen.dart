import 'package:flutter/material.dart';
import '../models/custom_skill.dart';
import '../services/custom_skill_service.dart';
import '../services/teach_mode_service.dart';

class SkillEditorScreen extends StatefulWidget {
  final CustomSkill? skillToEdit;

  const SkillEditorScreen({super.key, this.skillToEdit});

  @override
  State<SkillEditorScreen> createState() => _SkillEditorScreenState();
}

class _SkillEditorScreenState extends State<SkillEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final CustomSkillService _skillService = CustomSkillService();

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _categoryController;
  late TextEditingController _keywordsController;
  String _selectedIcon = 'star';

  late List<SkillParameter> _parameters;
  late List<RecipeStep> _steps;

  final List<String> _iconOptions = [
    'star',
    'chat',
    'play_circle_filled',
    'wifi',
    'alarm',
    'shopping_cart',
    'email',
    'navigation',
    'settings',
    'photo_camera',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.skillToEdit;
    _nameController = TextEditingController(text: s?.name ?? '');
    _descController = TextEditingController(text: s?.description ?? '');
    _categoryController = TextEditingController(text: s?.category ?? 'General');
    _keywordsController = TextEditingController(
      text: s?.triggerKeywords.join(', ') ?? '',
    );
    _selectedIcon = s?.icon ?? 'star';
    _parameters = s != null ? List.from(s.parameters) : [];
    _steps = s != null ? List.from(s.steps) : [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _categoryController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  void _saveSkill() async {
    if (!_formKey.currentState!.validate()) return;

    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one recipe step to this skill.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final keywords = _keywordsController.text
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    final skill = CustomSkill(
      id: widget.skillToEdit?.id ??
          'skill_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      category: _categoryController.text.trim(),
      icon: _selectedIcon,
      triggerKeywords: keywords,
      parameters: _parameters,
      steps: _steps,
      isEnabled: widget.skillToEdit?.isEnabled ?? true,
      isSystemTemplate: widget.skillToEdit?.isSystemTemplate ?? false,
      createdAt: widget.skillToEdit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _skillService.saveSkill(skill);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Skill "${skill.name}" saved successfully!'),
          backgroundColor: Colors.indigoAccent,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  void _addParameterDialog([SkillParameter? paramToEdit, int? editIndex]) {
    final nameCtrl = TextEditingController(text: paramToEdit?.name ?? '');
    final descCtrl = TextEditingController(text: paramToEdit?.description ?? '');
    String type = paramToEdit?.type ?? 'string';
    bool isReq = paramToEdit?.isRequired ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(paramToEdit == null ? 'Add Parameter' : 'Edit Parameter'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Parameter Variable Name',
                    hintText: 'e.g. recipient, amount',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Extraction Guidance / Description',
                    hintText: 'e.g. The person or contact to message',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'string', child: Text('Text (String)')),
                    DropdownMenuItem(value: 'number', child: Text('Number')),
                    DropdownMenuItem(value: 'boolean', child: Text('Boolean')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => type = val);
                  },
                ),
                SwitchListTile(
                  title: const Text('Mandatory / Required'),
                  value: isReq,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setDialogState(() => isReq = val),
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
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                final newParam = SkillParameter(
                  name: nameCtrl.text.trim().replaceAll(' ', '_'),
                  description: descCtrl.text.trim(),
                  type: type,
                  isRequired: isReq,
                );
                setState(() {
                  if (editIndex != null) {
                    _parameters[editIndex] = newParam;
                  } else {
                    _parameters.add(newParam);
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save Parameter'),
            ),
          ],
        ),
      ),
    );
  }

  void _addStepDialog([RecipeStep? stepToEdit, int? editIndex]) {
    final instructCtrl = TextEditingController(text: stepToEdit?.instruction ?? '');
    final pkgCtrl = TextEditingController(text: stepToEdit?.targetAppPackage ?? '');
    final hintCtrl = TextEditingController(text: stepToEdit?.expectedElementHint ?? '');
    final confirmMsgCtrl = TextEditingController(text: stepToEdit?.confirmationMessage ?? '');
    bool reqConfirm = stepToEdit?.requiresConfirmation ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(stepToEdit == null ? 'Add Recipe Step' : 'Edit Recipe Step'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: instructCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Step Instruction (SOP)',
                    hintText: 'e.g. Type "{recipient}" in the search field',
                  ),
                ),
                if (_parameters.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: _parameters
                        .map((p) => ActionChip(
                              label: Text('{${p.name}}', style: const TextStyle(fontSize: 10)),
                              onPressed: () {
                                instructCtrl.text += ' {${p.name}}';
                              },
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: hintCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target Element / Text Hint (Optional)',
                    hintText: 'e.g. Search, Send, Confirm',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pkgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'App Package Name (Optional)',
                    hintText: 'e.g. com.whatsapp',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Require User Confirmation Checkpoint'),
                  subtitle: const Text('Pauses execution and asks user before clicking/typing'),
                  value: reqConfirm,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setDialogState(() => reqConfirm = val),
                ),
                if (reqConfirm) ...[
                  TextField(
                    controller: confirmMsgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Confirmation Prompt Message',
                      hintText: 'e.g. Confirm sending message to {recipient}?',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (instructCtrl.text.trim().isEmpty) return;
                final newStep = RecipeStep(
                  stepNumber: editIndex != null ? editIndex + 1 : _steps.length + 1,
                  instruction: instructCtrl.text.trim(),
                  targetAppPackage: pkgCtrl.text.trim().isNotEmpty ? pkgCtrl.text.trim() : null,
                  expectedElementHint: hintCtrl.text.trim().isNotEmpty ? hintCtrl.text.trim() : null,
                  requiresConfirmation: reqConfirm,
                  confirmationMessage: confirmMsgCtrl.text.trim().isNotEmpty ? confirmMsgCtrl.text.trim() : null,
                );
                setState(() {
                  if (editIndex != null) {
                    _steps[editIndex] = newStep;
                  } else {
                    _steps.add(newStep);
                  }
                });
                Navigator.pop(ctx);
              },
              child: const Text('Save Step'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTeachMode() {
    final teach = TeachModeService();
    if (teach.isRecording) {
      final recorded = teach.stopRecording();
      setState(() {
        for (final step in recorded) {
          _steps.add(step.copyWith(stepNumber: _steps.length + 1));
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${recorded.length} steps from your demonstration!'),
          backgroundColor: Colors.indigoAccent,
        ),
      );
    } else {
      teach.startRecording();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teach Mode active! Tap/navigate on phone, then return and tap "Stop & Insert".'),
          duration: Duration(seconds: 4),
          backgroundColor: Colors.deepOrangeAccent,
        ),
      );
    }
  }

  IconData _getIconData(String iconKey) {
    switch (iconKey) {
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
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
      case 'settings':
        return Icons.settings_rounded;
      case 'photo_camera':
        return Icons.camera_alt_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.skillToEdit == null ? 'Create Custom Skill' : 'Edit Skill'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save Skill',
            onPressed: _saveSkill,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Skill Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Skill Name *',
                        hintText: 'e.g. Order Food from Swiggy',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Describe what this skill accomplishes for intent matching',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'Description is required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _categoryController,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              hintText: 'e.g. Messaging, Food, Finance',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _selectedIcon,
                          items: _iconOptions
                              .map((icon) => DropdownMenuItem(
                                    value: icon,
                                    child: Icon(_getIconData(icon)),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedIcon = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _keywordsController,
                      decoration: const InputDecoration(
                        labelText: 'Trigger Keywords (comma separated)',
                        hintText: 'e.g. swiggy, order food, lunch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Parameters
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Skill Parameters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: () => _addParameterDialog(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Variable'),
                        ),
                      ],
                    ),
                    const Text(
                      'Variables automatically extracted from user commands and injected into recipe steps (e.g. {recipient}).',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    if (_parameters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No parameters defined. (This skill takes no variable inputs)', style: TextStyle(fontStyle: FontStyle.italic)),
                      )
                    else
                      ..._parameters.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final param = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Chip(label: Text('{${param.name}}', style: const TextStyle(fontWeight: FontWeight.bold))),
                          title: Text(param.description),
                          subtitle: Text('Type: ${param.type} | ${param.isRequired ? "Required" : "Optional"}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _addParameterDialog(param, idx),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                                onPressed: () => setState(() => _parameters.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recipe Steps
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recipe SOP Steps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _toggleTeachMode,
                              icon: Icon(
                                TeachModeService().isRecording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                                size: 16,
                                color: TeachModeService().isRecording ? Colors.red : Colors.orange,
                              ),
                              label: Text(
                                TeachModeService().isRecording ? 'Stop & Insert' : 'Demonstrate',
                                style: TextStyle(
                                  color: TeachModeService().isRecording ? Colors.red : Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _addStepDialog(),
                              icon: const Icon(Icons.add_task_rounded, size: 18),
                              label: const Text('Add Step'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Text(
                      'Sequential constraints that guide the automation agent step-by-step.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    if (_steps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No steps defined yet. Tap "Add Step" above.', style: TextStyle(fontStyle: FontStyle.italic)),
                      )
                    else
                      ..._steps.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final step = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: Theme.of(context).primaryColor,
                                child: Text('${idx + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(step.instruction, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                    if (step.requiresConfirmation) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.shield_rounded, size: 12, color: Colors.amber),
                                            SizedBox(width: 4),
                                            Text('Confirmation Checkpoint', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 16),
                                onPressed: () => _addStepDialog(step, idx),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 16, color: Colors.redAccent),
                                onPressed: () => setState(() => _steps.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _saveSkill,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Skill Recipe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
