import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/custom_skill.dart';
import '../services/custom_skill_service.dart';
import '../services/teach_mode_service.dart';

class SkillEditorScreen extends StatefulWidget {
  final CustomSkill? skillToEdit;

  const SkillEditorScreen({super.key, this.skillToEdit});

  @override
  State<SkillEditorScreen> createState() => _SkillEditorScreenState();
}

class _SkillEditorScreenState extends State<SkillEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final CustomSkillService _skillService = CustomSkillService();

  // Visual Form Controllers
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _categoryController;
  late TextEditingController _keywordsController;
  late TextEditingController _jsonController;

  String _selectedIcon = 'star';
  late List<SkillParameter> _parameters;
  late List<RecipeStep> _steps;
  bool _isEnabled = true;
  String? _jsonError;

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
    'account_balance',
    'work',
  ];

  final List<String> _categoryPresets = [
    'General',
    'Messaging',
    'Media',
    'Finance',
    'System',
    'Social',
    'Utility',
  ];

  final List<Map<String, String>> _popularApps = [
    {'name': 'WhatsApp', 'pkg': 'com.whatsapp'},
    {'name': 'YouTube', 'pkg': 'com.google.android.youtube'},
    {'name': 'Chrome', 'pkg': 'com.android.chrome'},
    {'name': 'Settings', 'pkg': 'com.android.settings'},
    {'name': 'Gmail', 'pkg': 'com.google.android.gm'},
    {'name': 'Maps', 'pkg': 'com.google.android.apps.maps'},
    {'name': 'Spotify', 'pkg': 'com.spotify.music'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);

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
    _isEnabled = s?.isEnabled ?? true;

    _jsonController = TextEditingController();
    _syncVisualToJson();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _categoryController.dispose();
    _keywordsController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      _syncVisualToJson();
    } else {
      _syncJsonToVisual();
    }
  }

  CustomSkill _buildSkillFromForm() {
    final keywords = _keywordsController.text
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    return CustomSkill(
      id: widget.skillToEdit?.id ??
          'skill_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim().isEmpty ? 'Untitled Skill' : _nameController.text.trim(),
      description: _descController.text.trim(),
      category: _categoryController.text.trim().isEmpty ? 'General' : _categoryController.text.trim(),
      icon: _selectedIcon,
      triggerKeywords: keywords,
      parameters: _parameters,
      steps: _steps,
      isEnabled: _isEnabled,
      isSystemTemplate: widget.skillToEdit?.isSystemTemplate ?? false,
      createdAt: widget.skillToEdit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _syncVisualToJson() {
    final skill = _buildSkillFromForm();
    const encoder = JsonEncoder.withIndent('  ');
    _jsonController.text = encoder.convert(skill.toJson());
    setState(() {
      _jsonError = null;
    });
  }

  bool _syncJsonToVisual() {
    final raw = _jsonController.text.trim();
    if (raw.isEmpty) return true;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = CustomSkill.fromJson(decoded);

      setState(() {
        _nameController.text = parsed.name;
        _descController.text = parsed.description;
        _categoryController.text = parsed.category;
        _keywordsController.text = parsed.triggerKeywords.join(', ');
        _selectedIcon = parsed.icon;
        _parameters = List.from(parsed.parameters);
        _steps = List.from(parsed.steps);
        _isEnabled = parsed.isEnabled;
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

  Future<void> _saveSkill() async {
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

    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one recipe step to this skill.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final skill = _buildSkillFromForm();
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
      case 'account_balance':
        return Icons.account_balance_rounded;
      case 'work':
        return Icons.work_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  Color _getActionColor(String? actionType) {
    switch (actionType) {
      case 'launch_app':
        return Colors.purpleAccent;
      case 'tap_element':
      case 'click':
        return Colors.blueAccent;
      case 'tap_coordinate':
        return Colors.cyan;
      case 'input_text':
      case 'type':
        return Colors.green;
      case 'wait':
        return Colors.orange;
      case 'scroll':
        return Colors.teal;
      case 'press_key':
        return Colors.deepOrange;
      default:
        return Colors.indigoAccent;
    }
  }

  IconData _getActionIcon(String? actionType) {
    switch (actionType) {
      case 'launch_app':
        return Icons.rocket_launch_rounded;
      case 'tap_element':
      case 'click':
        return Icons.touch_app_rounded;
      case 'tap_coordinate':
        return Icons.ads_click_rounded;
      case 'input_text':
      case 'type':
        return Icons.keyboard_rounded;
      case 'wait':
        return Icons.timer_outlined;
      case 'scroll':
        return Icons.swap_vert_rounded;
      case 'press_key':
        return Icons.smart_button_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  // --- PARAMETER DIALOG ---
  void _addParameterDialog([SkillParameter? paramToEdit, int? editIndex]) {
    final nameCtrl = TextEditingController(text: paramToEdit?.name ?? '');
    final descCtrl = TextEditingController(text: paramToEdit?.description ?? '');
    final defaultCtrl = TextEditingController(text: paramToEdit?.defaultValue ?? '');
    String type = paramToEdit?.type ?? 'string';
    bool isReq = paramToEdit?.isRequired ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(paramToEdit == null ? 'Add Variable Parameter' : 'Edit Parameter'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Variable Name *',
                    hintText: 'e.g. recipient, amount, query',
                    helperText: 'Referenced in steps as {variable_name}',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Extraction Guidance / Description *',
                    hintText: 'e.g. Contact name or phone number to message',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: type,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'string', child: Text('Text (String)')),
                          DropdownMenuItem(value: 'number', child: Text('Number')),
                          DropdownMenuItem(value: 'boolean', child: Text('Boolean')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => type = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: defaultCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Default Value',
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Mandatory Parameter', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Must be provided in user request'),
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
                  defaultValue: defaultCtrl.text.trim().isNotEmpty ? defaultCtrl.text.trim() : null,
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

  // --- VISUAL STEP COMPOSER MODAL ---
  void _openStepComposerDialog([RecipeStep? stepToEdit, int? editIndex]) {
    String actionType = stepToEdit?.actionTypeHint ?? 'tap_element';
    final instructCtrl = TextEditingController(text: stepToEdit?.instruction ?? '');
    final pkgCtrl = TextEditingController(text: stepToEdit?.targetAppPackage ?? '');
    final targetHintCtrl = TextEditingController(text: stepToEdit?.expectedElementHint ?? '');
    final textInputCtrl = TextEditingController();
    final delayCtrl = TextEditingController(text: '2');
    String scrollDirection = 'Down';
    String keyChoice = 'Back';
    final confirmMsgCtrl = TextEditingController(text: stepToEdit?.confirmationMessage ?? '');
    bool reqConfirm = stepToEdit?.requiresConfirmation ?? false;

    // Pre-populate specific fields if editing
    if (stepToEdit != null) {
      if (actionType == 'input_text' && stepToEdit.expectedElementHint != null) {
        textInputCtrl.text = stepToEdit.expectedElementHint!;
      }
    }

    void updateGeneratedInstruction() {
      switch (actionType) {
        case 'launch_app':
          final pkg = pkgCtrl.text.trim();
          instructCtrl.text = pkg.isNotEmpty ? 'Launch app $pkg' : 'Launch target application';
          break;
        case 'tap_element':
          final hint = targetHintCtrl.text.trim();
          instructCtrl.text = hint.isNotEmpty ? 'Tap element "$hint"' : 'Tap target element';
          break;
        case 'input_text':
          final val = textInputCtrl.text.trim();
          final field = targetHintCtrl.text.trim();
          if (field.isNotEmpty) {
            instructCtrl.text = 'Type "$val" into $field';
          } else {
            instructCtrl.text = 'Type "$val"';
          }
          break;
        case 'wait':
          final dur = delayCtrl.text.trim();
          instructCtrl.text = 'Wait $dur seconds for page to load';
          break;
        case 'scroll':
          instructCtrl.text = 'Scroll $scrollDirection to find content';
          break;
        case 'press_key':
          instructCtrl.text = 'Press $keyChoice button';
          break;
        case 'custom':
          // Keep user instruction
          break;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(_getActionIcon(actionType), color: _getActionColor(actionType)),
              const SizedBox(width: 8),
              Text(stepToEdit == null ? 'Compose Action Step' : 'Edit Action Step'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action Type Selector
                  const Text('Select Action Type:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: actionType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'tap_element',
                        child: Row(children: [Icon(Icons.touch_app_rounded, color: Colors.blueAccent, size: 18), SizedBox(width: 8), Text('Tap Element')]),
                      ),
                      DropdownMenuItem(
                        value: 'input_text',
                        child: Row(children: [Icon(Icons.keyboard_rounded, color: Colors.green, size: 18), SizedBox(width: 8), Text('Type Text')]),
                      ),
                      DropdownMenuItem(
                        value: 'launch_app',
                        child: Row(children: [Icon(Icons.rocket_launch_rounded, color: Colors.purpleAccent, size: 18), SizedBox(width: 8), Text('Launch App')]),
                      ),
                      DropdownMenuItem(
                        value: 'wait',
                        child: Row(children: [Icon(Icons.timer_outlined, color: Colors.orange, size: 18), SizedBox(width: 8), Text('Wait / Delay')]),
                      ),
                      DropdownMenuItem(
                        value: 'scroll',
                        child: Row(children: [Icon(Icons.swap_vert_rounded, color: Colors.teal, size: 18), SizedBox(width: 8), Text('Scroll Screen')]),
                      ),
                      DropdownMenuItem(
                        value: 'press_key',
                        child: Row(children: [Icon(Icons.smart_button_rounded, color: Colors.deepOrange, size: 18), SizedBox(width: 8), Text('Press Key')]),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Row(children: [Icon(Icons.auto_awesome_rounded, color: Colors.indigoAccent, size: 18), SizedBox(width: 8), Text('Custom SOP Instruction')]),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          actionType = val;
                          updateGeneratedInstruction();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Dynamic contextual form fields
                  if (actionType == 'launch_app') ...[
                    TextField(
                      controller: pkgCtrl,
                      onChanged: (_) => setDialogState(updateGeneratedInstruction),
                      decoration: const InputDecoration(
                        labelText: 'App Package Name *',
                        hintText: 'e.g. com.whatsapp',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Popular App Presets:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _popularApps.map((app) {
                        return ActionChip(
                          label: Text(app['name']!, style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            setDialogState(() {
                              pkgCtrl.text = app['pkg']!;
                              updateGeneratedInstruction();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ] else if (actionType == 'tap_element') ...[
                    TextField(
                      controller: targetHintCtrl,
                      onChanged: (_) => setDialogState(updateGeneratedInstruction),
                      decoration: const InputDecoration(
                        labelText: 'Element Text / Button Label *',
                        hintText: 'e.g. Search, Send, Confirm, or {contact}',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else if (actionType == 'input_text') ...[
                    TextField(
                      controller: textInputCtrl,
                      onChanged: (_) => setDialogState(updateGeneratedInstruction),
                      decoration: const InputDecoration(
                        labelText: 'Text to Type *',
                        hintText: 'e.g. Hello {recipient}, your order is ready',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: targetHintCtrl,
                      onChanged: (_) => setDialogState(updateGeneratedInstruction),
                      decoration: const InputDecoration(
                        labelText: 'Target Input Field Hint (Optional)',
                        hintText: 'e.g. Search bar, Message box',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else if (actionType == 'wait') ...[
                    TextField(
                      controller: delayCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setDialogState(updateGeneratedInstruction),
                      decoration: const InputDecoration(
                        labelText: 'Duration in Seconds',
                        hintText: '2',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else if (actionType == 'scroll') ...[
                    DropdownButtonFormField<String>(
                      value: scrollDirection,
                      decoration: const InputDecoration(labelText: 'Scroll Direction', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Down', child: Text('Down')),
                        DropdownMenuItem(value: 'Up', child: Text('Up')),
                        DropdownMenuItem(value: 'Left', child: Text('Left')),
                        DropdownMenuItem(value: 'Right', child: Text('Right')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            scrollDirection = val;
                            updateGeneratedInstruction();
                          });
                        }
                      },
                    ),
                  ] else if (actionType == 'press_key') ...[
                    DropdownButtonFormField<String>(
                      value: keyChoice,
                      decoration: const InputDecoration(labelText: 'Key to Press', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Back', child: Text('Back Button')),
                        DropdownMenuItem(value: 'Home', child: Text('Home Button')),
                        DropdownMenuItem(value: 'Enter', child: Text('Enter Key')),
                        DropdownMenuItem(value: 'Recent Apps', child: Text('Recent Apps')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            keyChoice = val;
                            updateGeneratedInstruction();
                          });
                        }
                      },
                    ),
                  ],

                  // Variable Quick Insertion Toolbar
                  if (_parameters.isNotEmpty && (actionType == 'input_text' || actionType == 'tap_element' || actionType == 'custom')) ...[
                    const SizedBox(height: 10),
                    const Text('Insert Variable:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _parameters.map((p) {
                        return ActionChip(
                          avatar: const Icon(Icons.data_array_rounded, size: 12),
                          label: Text('{${p.name}}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            setDialogState(() {
                              if (actionType == 'input_text') {
                                textInputCtrl.text += '{${p.name}}';
                              } else if (actionType == 'tap_element') {
                                targetHintCtrl.text += '{${p.name}}';
                              } else {
                                instructCtrl.text += ' {${p.name}}';
                              }
                              updateGeneratedInstruction();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 12),
                  // Instruction preview / manual override
                  TextField(
                    controller: instructCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Standard Operating Procedure (Instruction)',
                      hintText: 'Step instruction executed by the agent',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),
                  // Checkpoint Switch
                  Container(
                    decoration: BoxDecoration(
                      color: reqConfirm ? Colors.amber.withOpacity(0.12) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SwitchListTile(
                      title: const Text('Confirmation Checkpoint', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Agent halts and prompts user before clicking or executing'),
                      secondary: Icon(Icons.shield_rounded, color: reqConfirm ? Colors.amber : Colors.grey),
                      value: reqConfirm,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      onChanged: (val) => setDialogState(() => reqConfirm = val),
                    ),
                  ),

                  if (reqConfirm) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: confirmMsgCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Confirmation Prompt Message',
                        hintText: 'e.g. Confirm sending message to {recipient}?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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
              onPressed: () {
                if (instructCtrl.text.trim().isEmpty) return;
                final newStep = RecipeStep(
                  stepNumber: editIndex != null ? editIndex + 1 : _steps.length + 1,
                  instruction: instructCtrl.text.trim(),
                  targetAppPackage: pkgCtrl.text.trim().isNotEmpty ? pkgCtrl.text.trim() : null,
                  expectedElementHint: targetHintCtrl.text.trim().isNotEmpty ? targetHintCtrl.text.trim() : null,
                  actionTypeHint: actionType,
                  requiresConfirmation: reqConfirm,
                  confirmationMessage: confirmMsgCtrl.text.trim().isNotEmpty ? confirmMsgCtrl.text.trim() : null,
                );

                setState(() {
                  if (editIndex != null) {
                    _steps[editIndex] = newStep;
                  } else {
                    _steps.add(newStep);
                  }
                  // Normalize step numbers
                  for (int i = 0; i < _steps.length; i++) {
                    _steps[i] = _steps[i].copyWith(stepNumber: i + 1);
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

  void _duplicateStep(int index) {
    setState(() {
      final source = _steps[index];
      final duplicated = source.copyWith(
        stepNumber: _steps.length + 1,
        instruction: '${source.instruction} (Copy)',
      );
      _steps.insert(index + 1, duplicated);
      for (int i = 0; i < _steps.length; i++) {
        _steps[i] = _steps[i].copyWith(stepNumber: i + 1);
      }
    });
  }

  void _moveStep(int fromIndex, int toIndex) {
    if (toIndex < 0 || toIndex >= _steps.length) return;
    setState(() {
      final step = _steps.removeAt(fromIndex);
      _steps.insert(toIndex, step);
      for (int i = 0; i < _steps.length; i++) {
        _steps[i] = _steps[i].copyWith(stepNumber: i + 1);
      }
    });
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
          content: Text('Teach Mode active! Tap/navigate on your screen, then return and tap "Stop & Insert".'),
          duration: Duration(seconds: 4),
          backgroundColor: Colors.deepOrangeAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.skillToEdit == null ? 'Create Custom Skill' : 'Edit Skill Recipe',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.auto_fix_high_rounded), text: 'Visual Composer'),
            Tab(icon: Icon(Icons.data_object_rounded), text: 'JSON Editor'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save Skill',
            onPressed: _saveSkill,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisualComposerTab(isDark),
          _buildJsonEditorTab(isDark),
        ],
      ),
    );
  }

  // --- TAB 1: VISUAL COMPOSER ---
  Widget _buildVisualComposerTab(bool isDark) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Skill Metadata Card
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
                        radius: 20,
                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.15),
                        child: Icon(_getIconData(_selectedIcon), color: Theme.of(context).primaryColor),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Skill Definition', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('Metadata for LLM intent routing', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isEnabled,
                        onChanged: (val) => setState(() => _isEnabled = val),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Skill Name *',
                      hintText: 'e.g. Send WhatsApp Message',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Goal & Capabilities Description *',
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
                            hintText: 'e.g. Messaging, Media, System',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedIcon,
                        items: _iconOptions.map((icon) {
                          return DropdownMenuItem(
                            value: icon,
                            child: Icon(_getIconData(icon)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedIcon = val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: _categoryPresets.map((cat) {
                      return ActionChip(
                        label: Text(cat, style: const TextStyle(fontSize: 10)),
                        onPressed: () => setState(() => _categoryController.text = cat),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _keywordsController,
                    decoration: const InputDecoration(
                      labelText: 'Trigger Phrases / Keywords (comma-separated)',
                      hintText: 'e.g. send message, text whatsapp, chat',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Parameters Card
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
                          Icon(Icons.data_array_rounded, color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          const Text('Dynamic Variables', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () => _addParameterDialog(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Variable'),
                      ),
                    ],
                  ),
                  const Text(
                    'Variables extracted from user commands and injected into recipe steps (e.g. {recipient}).',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),

                  if (_parameters.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No variables defined. (This skill runs fixed parameters)', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                    )
                  else
                    ..._parameters.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final param = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              constraints: const BoxConstraints(maxWidth: 120),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '{${param.name}}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(param.description, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                  Text(
                                    'Type: ${param.type} • ${param.isRequired ? "Required" : "Optional"}${param.defaultValue != null ? " • Default: ${param.defaultValue}" : ""}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                iconSize: 18,
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit Variable',
                                onPressed: () => _addParameterDialog(param, idx),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                iconSize: 18,
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                tooltip: 'Delete Variable',
                                onPressed: () => setState(() => _parameters.removeAt(idx)),
                              ),
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

          // 3. Action Sequence Builder Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.format_list_numbered_rounded, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Action Sequence',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
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
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            onPressed: () => _openStepComposerDialog(),
                            icon: const Icon(Icons.add_task_rounded, size: 16),
                            label: const Text('Add Step', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Text(
                    'Step-by-step action sequence that guides the automation agent deterministically.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  if (_steps.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2), style: BorderStyle.solid),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.touch_app_outlined, size: 36, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text('No action steps defined yet.', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          const Text('Tap "Add Step" to compose actions visually, or "Demonstrate" to record live touches.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    )
                  else
                    ..._steps.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final step = entry.value;
                      final actionColor = _getActionColor(step.actionTypeHint);
                      final actionIcon = _getActionIcon(step.actionTypeHint);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: step.requiresConfirmation
                                ? Colors.amber.withOpacity(0.6)
                                : Colors.grey.withOpacity(0.2),
                            width: step.requiresConfirmation ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 11,
                                        backgroundColor: actionColor,
                                        child: Text(
                                          '${idx + 1}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: actionColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(actionIcon, size: 12, color: actionColor),
                                            const SizedBox(width: 4),
                                            Text(
                                              step.actionTypeHint?.toUpperCase() ?? 'ACTION',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: actionColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (step.targetAppPackage != null && step.targetAppPackage!.trim().isNotEmpty)
                                        Container(
                                          constraints: const BoxConstraints(maxWidth: 130),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            step.targetAppPackage!,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              color: Colors.grey,
                                              fontFamily: 'monospace',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 16,
                                        icon: const Icon(Icons.arrow_upward_rounded),
                                        tooltip: 'Move Up',
                                        onPressed: idx > 0 ? () => _moveStep(idx, idx - 1) : null,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 16,
                                        icon: const Icon(Icons.arrow_downward_rounded),
                                        tooltip: 'Move Down',
                                        onPressed: idx < _steps.length - 1 ? () => _moveStep(idx, idx + 1) : null,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 16,
                                        icon: const Icon(Icons.copy_rounded),
                                        tooltip: 'Duplicate',
                                        onPressed: () => _duplicateStep(idx),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 16,
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: 'Edit Step',
                                        onPressed: () => _openStepComposerDialog(step, idx),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 16,
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                        tooltip: 'Delete',
                                        onPressed: () {
                                          setState(() {
                                            _steps.removeAt(idx);
                                            for (int i = 0; i < _steps.length; i++) {
                                              _steps[i] = _steps[i].copyWith(stepNumber: i + 1);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              step.instruction,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                            ),
                            if (step.requiresConfirmation) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.shield_rounded, size: 14, color: Colors.amber),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        step.confirmationMessage != null && step.confirmationMessage!.isNotEmpty
                                            ? 'Prompt: "${step.confirmationMessage}"'
                                            : 'Confirmation Checkpoint: Pauses and asks user before clicking/typing.',
                                        style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
            label: Text(
              'Save Skill Recipe (${_steps.length} steps)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
  Widget _buildJsonEditorTab(bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              const Icon(Icons.code_rounded, size: 18),
              const SizedBox(width: 8),
              const Text('Skill JSON Schema', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                    const SnackBar(content: Text('Skill JSON copied to clipboard!')),
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
