import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/autonomous_routine.dart';
import '../models/agent_persona.dart';
import '../models/custom_skill.dart';
import '../services/persona_service.dart';
import '../services/custom_skill_service.dart';
import '../services/routine_service.dart';
import '../services/routine_scheduler_service.dart';
import '../services/screen_automation_service.dart';

class RoutineEditorScreen extends StatefulWidget {
  final AutonomousRoutine? routineToEdit;

  const RoutineEditorScreen({super.key, this.routineToEdit});

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  final RoutineService _routineService = RoutineService();
  final PersonaService _personaService = PersonaService();
  final CustomSkillService _skillService = CustomSkillService();
  final RoutineSchedulerService _schedulerService = RoutineSchedulerService();

  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _goalController;
  late TextEditingController _criteriaController;
  late TextEditingController _jsonController;

  String _selectedPersonaId = 'personal_assistant';
  String? _selectedUnlockSkillId;
  RoutineExecutionMode _executionMode = RoutineExecutionMode.autonomous;
  ScheduleType _scheduleType = ScheduleType.interval;
  int _intervalMinutes = 30;
  int _dailyHour = 9;
  int _dailyMinute = 0;
  int _activeHourStart = 9;
  int _activeHourEnd = 21;
  bool _scheduleEnabled = true;
  int _maxSteps = 10;
  int _timeoutSeconds = 180;
  int _pauseOnFailures = 3;

  List<AgentPersona> _allPersonas = [];
  List<CustomSkill> _allSkills = [];
  String? _jsonError;

  final List<Map<String, dynamic>> _quickTemplates = [
    {
      'name': 'WhatsApp Auto-Responder',
      'desc': 'Periodically check WhatsApp and auto-reply to unread messages.',
      'goal':
          'Open WhatsApp. Look for chats with green unread badges. Open each unread chat, read the incoming message, and reply politely if appropriate. Return to chat list when done.',
      'criteria':
          'All unread chats checked and replied to or skipped, and WhatsApp returned to main chat list.',
      'personaId': 'personal_assistant',
      'mode': RoutineExecutionMode.autonomous,
      'interval': 30,
    },
    {
      'name': 'WhatsApp Supervised Monitor',
      'desc': 'Check unread messages and request approval before sending replies.',
      'goal':
          'Check WhatsApp for unread messages. Draft a response for pending messages and ask for confirmation before sending.',
      'criteria':
          'All pending incoming messages drafted and confirmed/handled.',
      'personaId': 'personal_assistant',
      'mode': RoutineExecutionMode.supervised,
      'interval': 15,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);

    final r = widget.routineToEdit;
    _nameController = TextEditingController(text: r?.name ?? '');
    _descController = TextEditingController(text: r?.description ?? '');
    _goalController = TextEditingController(text: r?.goalPrompt ?? '');
    _criteriaController = TextEditingController(text: r?.successCriteria ?? '');
    _jsonController = TextEditingController();

    if (r != null) {
      _selectedPersonaId = r.personaId;
      _selectedUnlockSkillId = r.unlockSkillId;
      _executionMode = r.executionMode;
      _scheduleType = r.schedule.type;
      _intervalMinutes = r.schedule.intervalMinutes;
      _dailyHour = r.schedule.dailyHour ?? 9;
      _dailyMinute = r.schedule.dailyMinute ?? 0;
      _activeHourStart = r.schedule.activeHourStart ?? 9;
      _activeHourEnd = r.schedule.activeHourEnd ?? 21;
      _scheduleEnabled = r.schedule.isEnabled;
      _maxSteps = r.guardrails.maxStepsPerRun;
      _timeoutSeconds = r.guardrails.maxDurationSeconds;
      _pauseOnFailures = r.guardrails.pauseOnConsecutiveFailures;
    }

    _loadDependencies();
  }

  Future<void> _loadDependencies() async {
    await _personaService.init();
    await _skillService.init();
    setState(() {
      _allPersonas = _personaService.getAllPersonas();
      _allSkills = _skillService.getAllSkills(includeDisabled: true);
      if (!_allPersonas.any((p) => p.id == _selectedPersonaId) &&
          _allPersonas.isNotEmpty) {
        _selectedPersonaId = _allPersonas.first.id;
      }
    });
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      _syncFormToJson();
    } else {
      _syncJsonToForm();
    }
  }

  void _syncFormToJson() {
    final routine = _buildRoutineFromForm();
    _jsonController.text = routine.toPrettyJson();
    setState(() => _jsonError = null);
  }

  void _syncJsonToForm() {
    try {
      final decoded = jsonDecode(_jsonController.text);
      if (decoded is Map<String, dynamic>) {
        final r = AutonomousRoutine.fromJson(decoded);
        setState(() {
          _nameController.text = r.name;
          _descController.text = r.description;
          _goalController.text = r.goalPrompt;
          _criteriaController.text = r.successCriteria;
          _selectedPersonaId = r.personaId;
          _selectedUnlockSkillId = r.unlockSkillId;
          _executionMode = r.executionMode;
          _scheduleType = r.schedule.type;
          _intervalMinutes = r.schedule.intervalMinutes;
          _dailyHour = r.schedule.dailyHour ?? 9;
          _dailyMinute = r.schedule.dailyMinute ?? 0;
          _activeHourStart = r.schedule.activeHourStart ?? 9;
          _activeHourEnd = r.schedule.activeHourEnd ?? 21;
          _scheduleEnabled = r.schedule.isEnabled;
          _maxSteps = r.guardrails.maxStepsPerRun;
          _timeoutSeconds = r.guardrails.maxDurationSeconds;
          _pauseOnFailures = r.guardrails.pauseOnConsecutiveFailures;
          _jsonError = null;
        });
      }
    } catch (e) {
      setState(() => _jsonError = e.toString());
    }
  }

  AutonomousRoutine _buildRoutineFromForm() {
    final existingId = widget.routineToEdit?.id;
    final id = existingId ??
        'routine_${DateTime.now().millisecondsSinceEpoch.toString()}';

    return AutonomousRoutine(
      id: id,
      name: _nameController.text.trim().isEmpty
          ? 'Autonomous Routine'
          : _nameController.text.trim(),
      description: _descController.text.trim(),
      personaId: _selectedPersonaId,
      unlockSkillId: _selectedUnlockSkillId,
      goalPrompt: _goalController.text.trim(),
      successCriteria: _criteriaController.text.trim(),
      executionMode: _executionMode,
      schedule: RoutineSchedule(
        type: _scheduleType,
        intervalMinutes: _intervalMinutes,
        dailyHour: _dailyHour,
        dailyMinute: _dailyMinute,
        activeHourStart: _activeHourStart,
        activeHourEnd: _activeHourEnd,
        isEnabled: _scheduleEnabled,
      ),
      guardrails: RoutineGuardrails(
        maxStepsPerRun: _maxSteps,
        maxDurationSeconds: _timeoutSeconds,
        pauseOnConsecutiveFailures: _pauseOnFailures,
      ),
      isEnabled: widget.routineToEdit?.isEnabled ?? true,
      lastRunTime: widget.routineToEdit?.lastRunTime,
      lastRunStatus: widget.routineToEdit?.lastRunStatus,
      consecutiveFailures: widget.routineToEdit?.consecutiveFailures ?? 0,
      lastFailureReason: widget.routineToEdit?.lastFailureReason,
    );
  }

  Future<void> _save() async {
    if (_tabController.index == 1) {
      _syncJsonToForm();
      if (_jsonError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid JSON: $_jsonError')),
        );
        return;
      }
    }

    if (!_formKey.currentState!.validate()) {
      _tabController.animateTo(0);
      return;
    }

    final routine = _buildRoutineFromForm();
    await _routineService.saveRoutine(routine);
    await _schedulerService.scheduleRoutine(routine);

    if (routine.isEnabled && routine.schedule.isEnabled) {
      final canAlarm = await ScreenAutomationService().canScheduleExactAlarms();
      if (!canAlarm && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Exact alarm permission needed for precision timing. Please grant in Settings.',
            ),
            action: SnackBarAction(
              label: 'Grant',
              onPressed: () =>
                  ScreenAutomationService().requestExactAlarmPermission(),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved routine "${routine.name}"')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _goalController.dispose();
    _criteriaController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routineToEdit == null
            ? 'New Autonomous Routine'
            : 'Edit Routine'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded), text: 'Visual Form'),
            Tab(icon: Icon(Icons.code_rounded), text: 'JSON Code'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Save Routine',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildVisualForm(),
          _buildJsonEditor(),
        ],
      ),
    );
  }

  Widget _buildVisualForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick Templates
          if (widget.routineToEdit == null) ...[
            const Text(
              'Quick Starter Templates',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickTemplates.map((tmpl) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(tmpl['name'] as String),
                      onPressed: () {
                        setState(() {
                          _nameController.text = tmpl['name'] as String;
                          _descController.text = tmpl['desc'] as String;
                          _goalController.text = tmpl['goal'] as String;
                          _criteriaController.text = tmpl['criteria'] as String;
                          _selectedPersonaId = tmpl['personaId'] as String;
                          _executionMode = tmpl['mode'] as RoutineExecutionMode;
                          _intervalMinutes = tmpl['interval'] as int;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Name & Description
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Routine Name *',
              hintText: 'e.g. WhatsApp Auto-Responder',
              prefixIcon: Icon(Icons.repeat_rounded),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _descController,
            decoration: const InputDecoration(
              labelText: 'Short Description',
              hintText: 'What does this routine accomplish?',
              prefixIcon: Icon(Icons.description_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Linked Persona & Unlock Skill
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Agent Identity & Pre-flight',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _allPersonas.any((p) => p.id == _selectedPersonaId)
                        ? _selectedPersonaId
                        : (_allPersonas.isNotEmpty
                            ? _allPersonas.first.id
                            : null),
                    decoration: const InputDecoration(
                      labelText: 'Linked Persona *',
                      helperText:
                          'Scopes instructions and allowed custom skills',
                      border: OutlineInputBorder(),
                    ),
                    items: _allPersonas.map((p) {
                      return DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.name} (${p.id})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedPersonaId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    value: _selectedUnlockSkillId,
                    decoration: const InputDecoration(
                      labelText: 'Pre-execution Unlock Skill (Optional)',
                      helperText:
                          'Replays if phone screen is locked before running',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (Screen must be unlocked)'),
                      ),
                      ..._allSkills.map((s) {
                        return DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text('Skill: ${s.name}'),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedUnlockSkillId = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Goal Prompt & Success Criteria
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Task Objectives & Success Criteria',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _goalController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Goal & Instructions *',
                      hintText:
                          'Check WhatsApp for unread messages. Open unread chats and reply appropriately...',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Goal prompt is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _criteriaController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Terminal Success Criteria *',
                      helperText:
                          'Evaluated by LLM on screen dump to determine completion',
                      hintText:
                          'All unread messages checked/replied and navigated back to chat list.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Success criteria is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const Text('Execution & Approval Mode:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<RoutineExecutionMode>(
                    segments: const [
                      ButtonSegment(
                        value: RoutineExecutionMode.autonomous,
                        label: Text('Full Auto'),
                        icon: Icon(Icons.bolt_rounded),
                      ),
                      ButtonSegment(
                        value: RoutineExecutionMode.supervised,
                        label: Text('Supervised'),
                        icon: Icon(Icons.verified_user_rounded),
                      ),
                    ],
                    selected: {_executionMode},
                    onSelectionChanged: (val) {
                      setState(() => _executionMode = val.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Schedule Settings
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Recurrence Schedule',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Switch(
                        value: _scheduleEnabled,
                        onChanged: (v) => setState(() => _scheduleEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_scheduleEnabled) ...[
                    SegmentedButton<ScheduleType>(
                      segments: const [
                        ButtonSegment(
                          value: ScheduleType.interval,
                          label: Text('Periodic Interval'),
                          icon: Icon(Icons.timer_outlined),
                        ),
                        ButtonSegment(
                          value: ScheduleType.dailyTime,
                          label: Text('Daily Specific Time'),
                          icon: Icon(Icons.schedule_rounded),
                        ),
                      ],
                      selected: {_scheduleType},
                      onSelectionChanged: (val) {
                        setState(() => _scheduleType = val.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_scheduleType == ScheduleType.interval) ...[
                      Text('Run Every: $_intervalMinutes minutes',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Slider(
                        value: _intervalMinutes.toDouble(),
                        min: 10,
                        max: 120,
                        divisions: 11,
                        label: '$_intervalMinutes min',
                        onChanged: (v) =>
                            setState(() => _intervalMinutes = v.round()),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          'Active Hours Window: ${_activeHourStart.toString().padLeft(2, '0')}:00 - ${_activeHourEnd.toString().padLeft(2, '0')}:00',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      RangeSlider(
                        values: RangeValues(_activeHourStart.toDouble(),
                            _activeHourEnd.toDouble()),
                        min: 0,
                        max: 24,
                        divisions: 24,
                        labels: RangeLabels(
                            '${_activeHourStart}h', '${_activeHourEnd}h'),
                        onChanged: (vals) {
                          setState(() {
                            _activeHourStart = vals.start.round();
                            _activeHourEnd = vals.end.round();
                          });
                        },
                      ),
                    ] else ...[
                      ListTile(
                        leading: const Icon(Icons.alarm_rounded),
                        title: Text(
                            'Daily Trigger Time: ${_dailyHour.toString().padLeft(2, '0')}:${_dailyMinute.toString().padLeft(2, '0')}'),
                        trailing: OutlinedButton(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                  hour: _dailyHour, minute: _dailyMinute),
                            );
                            if (time != null) {
                              setState(() {
                                _dailyHour = time.hour;
                                _dailyMinute = time.minute;
                              });
                            }
                          },
                          child: const Text('Change Time'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Guardrails & Safety Caps
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Guardrails & Hard Limits',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  Text('Max Steps per Run: $_maxSteps steps'),
                  Slider(
                    value: _maxSteps.toDouble(),
                    min: 5,
                    max: 25,
                    divisions: 20,
                    label: '$_maxSteps steps',
                    onChanged: (v) => setState(() => _maxSteps = v.round()),
                  ),
                  const SizedBox(height: 8),
                  Text('Timeout: $_timeoutSeconds seconds'),
                  Slider(
                    value: _timeoutSeconds.toDouble(),
                    min: 60,
                    max: 300,
                    divisions: 8,
                    label: '${_timeoutSeconds}s',
                    onChanged: (v) =>
                        setState(() => _timeoutSeconds = v.round()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildJsonEditor() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Raw Routine JSON',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'Copy JSON',
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _jsonController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Copied JSON to clipboard')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_align_left_rounded, size: 20),
                    tooltip: 'Format JSON',
                    onPressed: _syncFormToJson,
                  ),
                ],
              ),
            ],
          ),
          if (_jsonError != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Text(
                'JSON Error: $_jsonError',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _jsonController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{\n  "name": "..."\n}',
              ),
              onChanged: (_) {
                try {
                  jsonDecode(_jsonController.text);
                  setState(() => _jsonError = null);
                } catch (e) {
                  setState(() => _jsonError = e.toString());
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
