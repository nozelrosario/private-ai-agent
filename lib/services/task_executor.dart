import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'ai_service.dart';
import 'screen_automation_service.dart';
import 'app_launcher_service.dart';
import 'notification_service.dart';
import 'task_history_logger.dart';
import 'shizuku_service.dart';
import 'skill_memory_service.dart';
import 'recovery_engine.dart';
import 'skill_router_service.dart';
import '../models/saved_skill.dart';
import '../models/custom_skill.dart';
import '../models/autonomous_routine.dart';
import 'persona_service.dart';
import 'routine_ledger_service.dart';
import 'custom_skill_service.dart';

/// Executes multi-step UI automation tasks using LLM-guided screen reading.
///
/// Flow: User gives high-level goal → LLM reads screen → decides next action →
/// executes → reads screen again → repeats until goal is complete.
class TaskExecutor {
  final AiService _aiService;
  final ScreenAutomationService _screenService;
  final AppLauncherService _appLauncher;
  final ShizukuService _shizukuService;
  final NotificationService _notificationService = NotificationService();
  final SkillMemoryService _skillMemory = SkillMemoryService();
  final RecoveryEngine _recoveryEngine = RecoveryEngine();

  /// Callback to report progress messages to the UI
  final void Function(String message)? onProgress;

  /// Callback to request user confirmation at sensitive checkpoints
  final Future<bool> Function(String prompt)? onConfirmationRequired;

  /// Set to true to cancel the running task
  bool _cancelled = false;
  Completer<void>? _cancelCompleter;

  TaskExecutor({
    required AiService aiService,
    required ScreenAutomationService screenService,
    required AppLauncherService appLauncher,
    required ShizukuService shizukuService,
    this.onProgress,
    this.onConfirmationRequired,
  }) : _aiService = aiService,
       _screenService = screenService,
       _appLauncher = appLauncher,
       _shizukuService = shizukuService;

  /// Cancel the currently running task — takes effect immediately
  void cancel() {
    _cancelled = true;
    if (_cancelCompleter != null && !_cancelCompleter!.isCompleted) {
      _cancelCompleter!.complete();
    }
  }

  static const String _taskSystemPrompt = '''
You are a phone automation agent. You are given a TASK and the current SCREEN content.
You must decide what single action to take next to accomplish the task.

Respond with ONLY a JSON object (no markdown, no code fences):
{
  "action": "action_name",
  "params": {"key": "value"},
  "reasoning": "why you chose this action",
  "is_complete": false
}

Available actions:
- click_text: {"text": "exact text to click"} - Click an element by its visible text
- click_at: {"x": 540, "y": 960} - Click at screen coordinates (use bounds from screen dump)
- type_text: {"text": "hello", "field_hint": "optional hint"} - Type into the focused/first edit field
- press_enter: {} - Press the Enter/Search key on the keyboard to submit a search/form
- scroll: {"direction": "down"} - Scroll down/up on the current view
- swipe: {"startX": 540, "startY": 2000, "endX": 540, "endY": 500} - Swipe from start to end coordinates (e.g. open app drawer, navigate carousels)
- press_back: {} - Press the back button
- press_home: {} - Press the home button
- open_app: {"app_name": "WhatsApp"} - Open an app
- lock_screen: {} - Lock the phone screen (ONLY use when the user deliberately asks to lock the phone)
- wait: {} - Wait a moment for content to load
- done: {} - Task is complete

Rules:
- You will receive a TEXT DUMP of the accessibility tree containing exact text strings and center coordinates.
- ALWAYS use the text dump to decide your next action.
- If you need to click something, prefer using `click_text`. If the element does not have text, use `click_at` with the coordinates provided in the text dump.
- When typing in a search box, you MUST click it first, wait a step, and THEN type.
- After typing a search query, use `press_enter` once. If the screen does not change, click the exact visible suggestion text. Do not repeat the same submit action more than twice.
- Never scroll or swipe more than three times in a row. After three scrolls, choose the best visible result or take a different action instead of continuing to browse indefinitely.
- Set is_complete=true ONLY when the task is fully done.
- If you need to find something by scrolling, scroll and then check the screen again.
- If you need to open an app (like Wikipedia, Spotify, etc.) and you cannot find it after a couple of scrolls, ASSUME it is not installed. Immediately open Chrome or Google to search for the info on the web instead.
- If stuck after 3 attempts, set is_complete=true and explain in reasoning.
- Keep reasoning very brief (1 sentence)
''';

  /// Extract JSON safely even if wrapped in markdown or conversational text
  String _extractJson(String text) {
    // 1. Try to find a markdown json code block
    final codeBlockRegex = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
    final match = codeBlockRegex.firstMatch(text);
    if (match != null) {
      return match.group(1)!;
    }

    // 2. Fallback: find the first { and the last }
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');
    if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
      return text.substring(startIndex, endIndex + 1);
    }

    return text.trim();
  }

  /// Execute a multi-step task with LLM guidance
  Future<String> executeTask(String userGoal) async {
    await _screenService.setTaskKeepAwake(true, owner: 'task_executor');
    try {
      return await _executeTaskInternal(userGoal);
    } finally {
      await _screenService.setTaskKeepAwake(false, owner: 'task_executor');
    }
  }

  Future<String> _executeTaskInternal(String userGoal) async {
    await ScreenAutomationService.logToNative(
      "[TaskExecutor] executeTask() CALLED with goal: $userGoal",
    );
    _cancelled = false;

    await ScreenAutomationService.logToNative(
      "[TaskExecutor] Checking if accessibility service is running...",
    );
    final isRunning = await _screenService.isServiceRunning();
    await ScreenAutomationService.logToNative(
      "[TaskExecutor] Accessibility service isRunning = $isRunning",
    );
    if (!isRunning) {
      await ScreenAutomationService.logToNative(
        "[TaskExecutor] Accessibility service not running, returning early.",
      );
      return 'Accessibility service is not enabled. Go to Settings \u2192 Accessibility \u2192 PrivateAgent Screen Control and enable it.';
    }

    final results = <String>[];
    final executionTrace = <dynamic>[];
    results.add('Starting task: $userGoal');
    executionTrace.add({
      'info': 'Starting task: $userGoal',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _report('Starting task: $userGoal');

    // Wake and dismiss keyguard if device is currently locked or asleep
    final isInteractiveInitially = await _screenService.isScreenInteractive();
    final isLockedInitially = await _screenService.isKeyguardLocked();
    if (!isInteractiveInitially || isLockedInitially) {
      _report('Device is asleep/locked. Waking and requesting keyguard dismissal...');
      await _screenService.wakeScreen();
      await _screenService.dismissKeyguard();
      await Future.delayed(const Duration(milliseconds: 400));
      if (await _screenService.isKeyguardLocked()) {
        await _screenService.setShowWhenLocked(false);
        await Future.delayed(const Duration(milliseconds: 400));
        await _screenService.swipe(540, 1800, 540, 400);
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    // Check skill memory first
    final savedSkill = await _skillMemory.findSkill(userGoal);
    if (savedSkill != null && savedSkill.isReliable) {
      _report(
        'Found saved skill! Replaying ${savedSkill.steps.length} steps...',
      );
      final replaySuccess = await _replaySkill(savedSkill, results, executionTrace);
      if (replaySuccess) {
        results.add('Task complete via skill memory.');
        _report('Task complete (via skill memory).');
        await _notificationService.showTaskCompleteNotification(
          'Task Completed',
          'Agent finished its goal using memory.',
        );
        await TaskHistoryLogger.logTask(
          userGoal,
          'Success',
          0,
          savedSkill.steps.length,
          executionTrace.isNotEmpty ? executionTrace : results,
        );
        await _screenService.showToast('Task Complete! (Memory)');
        return 'Done.';
      } else {
        _report('Replay failed, falling back to AI...');
        await _skillMemory.recordFailure(savedSkill.id);
      }
    }

    // Check Custom Skill Recipes (Hybrid Workflow SOPs)
    SkillMatchResult? matchedSkillResult;
    try {
      final router = SkillRouterService(_aiService);
      matchedSkillResult = await router
          .routeTask(userGoal)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
    } catch (e) {
      developer.log('Skill routing check skipped: $e', name: 'PrivateAgent');
    }

    final CustomSkill? activeRecipe = matchedSkillResult?.skill;
    int recipeStepIndex = 0;

    if (activeRecipe != null && activeRecipe.steps.isNotEmpty) {
      results.add('Matched Custom Skill: ${activeRecipe.name}');
      _report('Executing Skill Recipe: "${activeRecipe.name}" (${activeRecipe.steps.length} steps)...');
    }

    // Smart pre-launch shortcuts: execute common sequences without LLM
    final shortcut = _getNavigationShortcut(userGoal);
    String lastAction = '';
    int sameActionCount = 0;
    int consecutiveFailures = 0;
    String lastFailedAction = '';
    int totalTokens = 0;
    final List<ActionStep> executedSteps = [];

    if (shortcut != null && shortcut.isNotEmpty) {
      results.add('Using navigation shortcut: ${shortcut.length} steps');
      _report('Using navigation shortcut...');
      for (final step in shortcut) {
        if (_cancelled) break;

        bool success = false;
        if (step.action == 'open_app') {
          final appName = step.params['app_name'] as String? ?? '';
          final res = await _appLauncher.openApp(appName);
          success = res.startsWith('Opened');
          await Future.delayed(const Duration(milliseconds: 3000));
        } else if (step.action == 'click_text') {
          final text = step.params['text'] as String? ?? '';
          success = await _screenService.clickByText(text);
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        if (success) {
          executedSteps.add(step);
          lastAction = step.action;
        } else {
          break; // Fall back to AI if shortcut step fails
        }
      }
    }

    // Ensure we are NOT still sitting inside PrivateAgent app before entering
    // the screen-reading loop (AgentAccessibilityService filters our own window).
    final currentPkgAfterShortcut = await _screenService.getCurrentPackage();
    if (currentPkgAfterShortcut == 'com.orailnoor.privateagent' ||
        currentPkgAfterShortcut == 'com.orailnoor.privateagent.beta') {
      _report('Moving to background...');
      await _screenService.pressHome();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    for (int step = 0; step < _aiService.maxSteps; step++) {
      // Check for cancellation
      if (_cancelled) {
        results.add('Task cancelled by user.');
        _report('Task cancelled.');
        await _notificationService.showTaskCompleteNotification(
          'Task Cancelled',
          'Task was stopped by the user.',
        );
        await TaskHistoryLogger.logTask(
          userGoal,
          'Cancelled',
          totalTokens,
          step,
          executionTrace.isNotEmpty ? executionTrace : results,
        );
        await _screenService.showToast('Task Cancelled');
        return 'Task cancelled.';
      }

      // Verify screen is still active & unlocked mid-execution
      final isInteractive = await _screenService.isScreenInteractive();
      final isLocked = await _screenService.isKeyguardLocked();
      if (!isInteractive || isLocked) {
        _report('Screen sleep/lock detected mid-execution. Restoring screen...');
        await _screenService.wakeScreen();
        await _screenService.dismissKeyguard();
        await Future.delayed(const Duration(milliseconds: 400));
        if (await _screenService.isKeyguardLocked()) {
          await _screenService.swipe(540, 1800, 540, 400);
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }

      // Adaptive delay: give Android apps time to transition screens, load data, or open keyboards
      int delay = 1200; // Default 1.2s delay for most actions
      if (lastAction == 'open_app') {
        delay = 3000; // Apps need ~3 seconds to fully cold-start and render
      } else if (lastAction == 'type_text') {
        delay =
            2000; // Typing involves keyboards and often triggers heavy network requests (search)
      } else if (lastAction == 'click_text' || lastAction == 'click_at') {
        delay = 1500; // Clicking usually triggers a screen transition
      } else if (lastAction == 'scroll') {
        delay = 1000; // Scrolling is relatively fast
      }
      await Future.delayed(Duration(milliseconds: delay));

      // 1. Read the current screen text
      final screenContent = _aiService.useScreenCompression
          ? await _screenService.getCompressedScreenDescription(userGoal)
          : await _screenService.getScreenDescription();
      developer.log(
        '=== SCREEN DUMP (Step ${step + 1}) ===\n$screenContent',
        name: 'PrivateAgent',
      );

      // Determine previous result string
      final prevResultStr = step > 0 && results.isNotEmpty
          ? '\nPREVIOUS ACTION RESULT: ${results.last}\n'
          : '';

      // Build failure hint if agent is stuck in a loop
      String failureHint = '';
      if (consecutiveFailures >= 3) {
        failureHint =
            '\n\nWARNING: You have failed $consecutiveFailures times in a row with the same approach. You MUST try a completely different action. If open_app failed, try press_home and look for the app icon on the home screen instead. If click_text failed, use click_at with coordinates. Do NOT repeat the same failed action.';
      }

      // Check recipe step and confirmation checkpoint
      String recipeDirective = '';
      if (activeRecipe != null && recipeStepIndex < activeRecipe.steps.length) {
        final currentRecipeStep = activeRecipe.steps[recipeStepIndex];
        final instruction = matchedSkillResult!.applyParameters(currentRecipeStep.instruction);

        // Check if this step requires confirmation checkpoint
        if (currentRecipeStep.requiresConfirmation && onConfirmationRequired != null) {
          final confirmPrompt = currentRecipeStep.confirmationMessage != null
              ? matchedSkillResult.applyParameters(currentRecipeStep.confirmationMessage!)
              : 'The agent is ready to execute: "$instruction". Proceed?';
          _report('Waiting for confirmation: $confirmPrompt');
          final confirmed = await onConfirmationRequired!(confirmPrompt);
          if (!confirmed || _cancelled) {
            results.add('Task cancelled by user at confirmation checkpoint.');
            _report('Task cancelled by user.');
            await _screenService.showToast('Task Cancelled');
            return 'Task cancelled at confirmation checkpoint.';
          }
        }

        recipeDirective = '''
ACTIVE SKILL RECIPE: "${activeRecipe.name}"
RECIPE TARGET STEP (${recipeStepIndex + 1}/${activeRecipe.steps.length}): $instruction
${currentRecipeStep.expectedElementHint != null ? 'HINT ELEMENT: "${matchedSkillResult.applyParameters(currentRecipeStep.expectedElementHint!)}"' : ''}
${currentRecipeStep.actionTypeHint != null ? 'SUGGESTED ACTION TYPE: ${currentRecipeStep.actionTypeHint}' : ''}
Focus on accomplishing Step ${recipeStepIndex + 1}. Once this step is achieved on the current screen, you will move to the next.
''';
      }

      // 2. Build the prompt (system prompt is sent separately via sendTaskMessage)
      final prompt =
          '''TASK: $userGoal
$recipeDirective
CURRENT SCREEN TEXT DUMP:
$screenContent$prevResultStr$failureHint
Step ${step + 1}/${_aiService.maxSteps}. Look at the text dump and coordinates. What is the next action?''';

      developer.log('=== AI PROMPT ===\n$prompt', name: 'PrivateAgent');

      // 3. Get AI response — races against cancel signal so Stop works immediately
      String response;
      try {
        _cancelCompleter = Completer<void>();
        final aiFuture = _aiService.sendTaskMessage(_taskSystemPrompt, prompt);

        // Race: whichever finishes first wins
        final result = await Future.any([
          aiFuture.then((r) => r),
          _cancelCompleter!.future.then((_) => null),
        ]);

        if (result == null || _cancelled) {
          results.add('Task cancelled by user.');
          _report('Task cancelled.');
          await _notificationService.showTaskCompleteNotification(
            'Task Cancelled',
            'Task was stopped by the user.',
          );
          await TaskHistoryLogger.logTask(
            userGoal,
            'Cancelled',
            totalTokens,
            step,
            executionTrace.isNotEmpty ? executionTrace : results,
          );
          await _screenService.showToast('Task Cancelled');
          return 'Task cancelled.';
        }

        final aiResponse = result as AiResponse;
        response = aiResponse.content;
        totalTokens += aiResponse.totalTokens;

        developer.log(
          '=== RAW AI RESPONSE ===\n$response',
          name: 'PrivateAgent',
        );
      } catch (e) {
        if (_cancelled) {
          results.add('Task cancelled by user.');
          _report('Task cancelled.');
          await _notificationService.showTaskCompleteNotification(
            'Task Cancelled',
            'Task was stopped by the user.',
          );
          await TaskHistoryLogger.logTask(
            userGoal,
            'Cancelled',
            totalTokens,
            step,
            executionTrace.isNotEmpty ? executionTrace : results,
          );
          await _screenService.showToast('Task Cancelled');
          await Future.delayed(const Duration(seconds: 2));
          return 'Task cancelled.';
        }
        results.add('AI error: $e');
        _report('Error: $e');
        await _notificationService.showTaskCompleteNotification(
          'Task Error',
          'AI encountered an error.',
        );
        await TaskHistoryLogger.logTask(
          userGoal,
          'Failed',
          totalTokens,
          step,
          executionTrace.isNotEmpty ? executionTrace : results,
        );
        await _screenService.showToast('AI Error: $e');
        await Future.delayed(const Duration(seconds: 3));
        return 'I could not complete the task because the AI service failed.';
      }

      // Check for cancellation after AI response
      if (_cancelled) {
        results.add('Task cancelled by user.');
        _report('Task cancelled.');
        await _notificationService.showTaskCompleteNotification(
          'Task Cancelled',
          'Task was stopped by the user.',
        );
        await TaskHistoryLogger.logTask(
          userGoal,
          'Cancelled',
          totalTokens,
          step,
          executionTrace.isNotEmpty ? executionTrace : results,
        );
        await _screenService.showToast('Task Cancelled');
        await Future.delayed(const Duration(seconds: 2));
        return 'Task cancelled.';
      }

      // 4. Parse the action (with one retry on failure)
      Map<String, dynamic>? actionJson;
      String? parsedJsonStr;
      try {
        String jsonStr = _extractJson(response);

        actionJson = jsonDecode(jsonStr) as Map<String, dynamic>;
        parsedJsonStr = jsonStr;
      } catch (firstError) {
        // First attempt failed — retry once
        developer.log(
          '=== JSON PARSE FAILED, RETRYING ===\nError: $firstError\nRaw: $response',
          name: 'PrivateAgent',
        );
        _report('Retrying step ${step + 1}...\n(Failed to parse: $firstError)');
        // Wait 2 seconds before retrying to prevent rate-limit spam
        await Future.delayed(const Duration(seconds: 2));
        try {
          final retryResponse = await _aiService.sendTaskMessage(
            _taskSystemPrompt,
            prompt,
          );
          totalTokens += retryResponse.totalTokens;
          developer.log(
            '=== RETRY AI RESPONSE ===\n${retryResponse.content}',
            name: 'PrivateAgent',
          );

          String jsonStr = _extractJson(retryResponse.content);
          actionJson = jsonDecode(jsonStr) as Map<String, dynamic>;
          parsedJsonStr = jsonStr;
        } catch (e) {
          results.add('Step ${step + 1}: Error after retry: $e');

          String debugInfo = 'Error: $e';
          _report('AI Error: $debugInfo\n\nRaw output:\n${response}');

          await _notificationService.showTaskCompleteNotification(
            'Task Error',
            'AI formatting error.',
          );
          await TaskHistoryLogger.logTask(
            userGoal,
            'Failed',
            totalTokens,
            step,
            executionTrace.isNotEmpty ? executionTrace : results,
          );
          await _screenService.showToast('Agent Error: $e');
          await Future.delayed(const Duration(seconds: 3));
          return 'I could not understand the AI response. Please try again.';
        }
      }

      final action = actionJson['action'] as String? ?? 'done';
      final params = actionJson['params'] as Map<String, dynamic>? ?? {};
      final reasoning = actionJson['reasoning'] as String? ?? '';
      final isComplete = actionJson['is_complete'] == true;

      developer.log(
        '=== PARSED ACTION ===\nAction: $action\nParams: $params\nReasoning: $reasoning\nIs Complete: $isComplete',
        name: 'PrivateAgent',
      );

      _report('Step ${step + 1}: $reasoning');

      sameActionCount = action == lastAction ? sameActionCount + 1 : 1;
      final repeatLimit = action == 'press_enter'
          ? 2
          : (action == 'scroll' || action == 'swipe' ? 3 : 1000);
      if (sameActionCount > repeatLimit) {
        final blockedResult =
            'Blocked repeated $action action. Use a different action on the visible screen.';
        results.add(blockedResult);
        _report(blockedResult);
        consecutiveFailures = 3;
        lastFailedAction = action;
        lastAction = action;
        continue;
      }
      lastAction = action; // Track for adaptive delay

      // 5. Execute the action
      bool success = false;
      String actionResult = '';

      switch (action) {
        case 'click_text':
          final text = params['text'] as String? ?? '';
          success = await _screenService.clickByText(text);
          actionResult = success
              ? 'Clicked "$text"'
              : 'Could not find "$text" to click';
          break;

        case 'click_at':
          final x = (params['x'] as num?)?.toDouble() ?? 0;
          final y = (params['y'] as num?)?.toDouble() ?? 0;
          success = await _screenService.clickAt(x, y);
          actionResult = success ? 'Clicked at ($x, $y)' : 'Click failed';
          break;

        case 'type_text':
          final text = params['text'] as String? ?? '';
          final hint = params['field_hint'] as String?;
          success = await _screenService.typeText(text, fieldHint: hint);
          actionResult = success ? 'Typed "$text"' : 'Could not type text';
          break;

        case 'press_enter':
          success = await _submitKeyboardAction();
          actionResult = success
              ? 'Submitted the focused search/form field'
              : 'Could not submit the focused field';
          break;

        case 'swipe':
          final startX = (params['startX'] as num?)?.toDouble() ?? 540;
          final startY = (params['startY'] as num?)?.toDouble() ?? 2000;
          final endX = (params['endX'] as num?)?.toDouble() ?? 540;
          final endY = (params['endY'] as num?)?.toDouble() ?? 500;

          success = await _performSwipe(startX, startY, endX, endY);
          actionResult = 'Swiped from ($startX,$startY) to ($endX,$endY)';
          break;

        case 'scroll':
          final direction = params['direction'] as String? ?? 'down';
          success = await _performScroll(direction);
          actionResult = success
              ? 'Scrolled $direction'
              : 'Could not scroll $direction';
          break;

        case 'press_back':
          success = await _screenService.pressBack();
          actionResult = 'Pressed back';
          break;

        case 'press_home':
          success = await _screenService.pressHome();
          actionResult = 'Pressed home';
          break;

        case 'open_app':
          final appName = params['app_name'] as String? ?? '';
          actionResult = await _appLauncher.openApp(appName);
          success = actionResult.startsWith('Opened');
          break;

        case 'lock_screen':
          _report('Locking screen as requested...');
          await _screenService.setTaskKeepAwake(false, owner: 'task_executor');
          await _screenService.setKeepScreenOn(false);
          await _screenService.stopExecutionMode(returnToListener: true);
          await Future.delayed(const Duration(milliseconds: 150));
          success = await _screenService.lockScreen();
          actionResult = success ? 'Screen locked' : 'Failed to lock screen';
          if (success) {
            executionTrace.add({
              'step': step + 1,
              'action': action,
              'params': params,
              'reasoning': reasoning,
              'result': actionResult,
              'status': 'success',
              'timestamp': DateTime.now().toIso8601String(),
            });
            results.add('Step ${step + 1}: $actionResult ($reasoning)');
            await TaskHistoryLogger.logTask(
              userGoal,
              'Success',
              totalTokens,
              step + 1,
              executionTrace.isNotEmpty ? executionTrace : results,
            );
            return reasoning.trim().isEmpty
                ? 'Screen locked.'
                : reasoning.trim();
          }
          break;

        case 'wait':
          await Future.delayed(const Duration(seconds: 1));
          actionResult = 'Waited';
          success = true;
          break;

        case 'done':
          results.add('Task complete: $reasoning');
          _report('Task complete: $reasoning');
          await _notificationService.showTaskCompleteNotification(
            'Task Completed',
            reasoning.trim().isEmpty ? 'Agent finished its goal.' : reasoning,
          );
          await _screenService.showToast('Task completed');
          return reasoning.trim().isEmpty ? 'Done.' : reasoning.trim();

        default:
          actionResult = 'Unknown action: $action';
      }

      developer.log(
        '=== NATIVE EXECUTION RESULT ===\n$actionResult',
        name: 'PrivateAgent',
      );

      // Track consecutive failures to detect stuck loops
      if (!success) {
        if (action == lastFailedAction) {
          consecutiveFailures++;
        } else {
          consecutiveFailures = 1;
          lastFailedAction = action;
        }

        // If stuck for 5+ consecutive failures, give up on this task
        if (consecutiveFailures >= 5) {
          results.add(
            'Agent is stuck. Stopping task after $consecutiveFailures consecutive failures.',
          );
          _report('Agent stuck — stopping task.');
          await _notificationService.showTaskCompleteNotification(
            'Task Stuck',
            'Agent could not complete the task after repeated failures.',
          );
          await TaskHistoryLogger.logTask(
            userGoal,
            'Failed',
            totalTokens,
            step,
            executionTrace.isNotEmpty ? executionTrace : results,
          );
          await _screenService.showToast('Agent stuck. Task stopped.');
          await Future.delayed(const Duration(seconds: 4));
          return 'I could not complete the task. Please try again.';
        }

        final recovery = await _recoveryEngine.diagnose(action, screenContent);
        _report('Recovering: ${recovery.description}');

        if (recovery.action == 'wait') {
          await Future.delayed(const Duration(seconds: 2));
        } else if (recovery.action == 'press_back') {
          await _screenService.pressBack();
        } else if (recovery.action == 'scroll') {
          final dir = recovery.params['direction'] ?? 'down';
          if (dir == 'down') {
            await _shizukuService.runCommand(
              'input swipe 540 1800 540 600 600',
            );
          } else {
            await _shizukuService.runCommand(
              'input swipe 540 600 540 1800 600',
            );
          }
        } else if (recovery.action == 'press_home') {
          await _screenService.pressHome();
        }

        results.add('Recovery step: ${recovery.description}');
        continue;
      } else {
        consecutiveFailures = 0;
        lastFailedAction = '';
        executedSteps.add(ActionStep(action: action, params: params));

        if (activeRecipe != null && recipeStepIndex < activeRecipe.steps.length) {
          recipeStepIndex++;
          if (recipeStepIndex >= activeRecipe.steps.length) {
            _report('Skill recipe finished all planned steps.');
          }
        }
      }

      results.add('Step ${step + 1}: $actionResult ($reasoning)');
      executionTrace.add({
        'step': step + 1,
        'action': action,
        'params': params,
        'reasoning': reasoning,
        'result': actionResult,
        'status': success ? 'success' : 'failed',
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Provide progress feedback
      if (!isComplete && (step + 1) % 3 == 0) {
        await _screenService.showToast('Working... (Step ${step + 1})');
      }

      if (isComplete) {
        results.add('Task complete.');
        _report('Task complete.');
        await _notificationService.showTaskCompleteNotification(
          'Task Completed',
          'Agent finished its goal.',
        );
        await TaskHistoryLogger.logTask(
          userGoal,
          'Success',
          totalTokens,
          step + 1,
          executionTrace.isNotEmpty ? executionTrace : results,
        );

        // Save to skill memory
        await _skillMemory.saveSkill(userGoal, executedSteps);

        await _screenService.showToast('Task Complete!');
        // Wait 4 seconds so the user can see the result before jumping back
        await Future.delayed(const Duration(seconds: 4));
        return reasoning.trim().isEmpty ? 'Done.' : reasoning.trim();
      }
    }

    results.add(
      'Reached maximum steps (${_aiService.maxSteps}). Task may be incomplete.',
    );
    executionTrace.add({
      'info': 'Reached maximum steps (${_aiService.maxSteps}). Task may be incomplete.',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _report('Reached maximum steps.');
    await _notificationService.showTaskCompleteNotification(
      'Task Stopped',
      'Reached maximum steps (${_aiService.maxSteps}).',
    );
    await TaskHistoryLogger.logTask(
      userGoal,
      'Failed',
      totalTokens,
      _aiService.maxSteps,
      executionTrace.isNotEmpty ? executionTrace : results,
    );
    await _screenService.showToast('Reached maximum steps.');
    await Future.delayed(const Duration(seconds: 4));

    return 'I could not complete the task within the allowed steps.';
  }

  void _report(String message) {
    onProgress?.call(message);
  }

  Future<bool> _submitKeyboardAction() async {
    if (await _screenService.pressEnter()) return true;

    final shizukuAvailable = await _shizukuService.checkAvailability();
    if (!shizukuAvailable) return false;

    final result = await _shizukuService.runCommand('input keyevent 66');
    final normalized = result.toLowerCase();
    return !normalized.contains('not running') &&
        !normalized.contains('permission denied') &&
        !normalized.startsWith('error');
  }

  Future<bool> _performScroll(String direction) async {
    if (await _screenService.scroll(direction)) return true;

    final isDown = direction.toLowerCase() == 'down';
    return _performSwipe(540, isDown ? 1800 : 600, 540, isDown ? 600 : 1800);
  }

  Future<bool> _performSwipe(
    double startX,
    double startY,
    double endX,
    double endY,
  ) async {
    if (await _screenService.swipe(startX, startY, endX, endY)) return true;

    final shizukuAvailable = await _shizukuService.checkAvailability();
    if (!shizukuAvailable) return false;

    final result = await _shizukuService.runCommand(
      'input swipe ${startX.toInt()} ${startY.toInt()} '
      '${endX.toInt()} ${endY.toInt()} 600',
    );
    final normalized = result.toLowerCase();
    return !normalized.contains('not running') &&
        !normalized.contains('permission denied') &&
        !normalized.startsWith('error');
  }

  /// Replays a saved skill without using the LLM
  Future<bool> _replaySkill(SavedSkill skill, List<String> results, [List<dynamic>? trace]) async {
    for (int i = 0; i < skill.steps.length; i++) {
      if (_cancelled) return false;

      final step = skill.steps[i];
      _report('Replaying step ${i + 1}/${skill.steps.length}: ${step.action}');

      // Delay before executing each step
      int delay = 1200;
      if (step.action == 'open_app')
        delay = 3000;
      else if (step.action == 'type_text')
        delay = 2000;
      else if (step.action == 'click_text' || step.action == 'click_at')
        delay = 1500;
      else if (step.action == 'scroll')
        delay = 1000;

      await Future.delayed(Duration(milliseconds: delay));

      bool success = false;
      String actionResult = '';

      switch (step.action) {
        case 'click_text':
          final text = step.params['text'] as String? ?? '';
          success = await _screenService.clickByText(text);
          actionResult = success
              ? 'Clicked "$text"'
              : 'Could not find "$text" to click';
          break;
        case 'click_at':
          final x = (step.params['x'] as num?)?.toDouble() ?? 0;
          final y = (step.params['y'] as num?)?.toDouble() ?? 0;
          success = await _screenService.clickAt(x, y);
          actionResult = success ? 'Clicked at ($x, $y)' : 'Click failed';
          break;
        case 'type_text':
          final text = step.params['text'] as String? ?? '';
          final hint = step.params['field_hint'] as String?;
          success = await _screenService.typeText(text, fieldHint: hint);
          actionResult = success ? 'Typed "$text"' : 'Could not type text';
          break;
        case 'press_enter':
          success = await _submitKeyboardAction();
          actionResult = success
              ? 'Submitted the focused search/form field'
              : 'Could not submit the focused field';
          break;
        case 'swipe':
          final startX = (step.params['startX'] as num?)?.toDouble() ?? 540;
          final startY = (step.params['startY'] as num?)?.toDouble() ?? 2000;
          final endX = (step.params['endX'] as num?)?.toDouble() ?? 540;
          final endY = (step.params['endY'] as num?)?.toDouble() ?? 500;
          success = await _performSwipe(startX, startY, endX, endY);
          actionResult = 'Swiped from ($startX,$startY) to ($endX,$endY)';
          break;
        case 'scroll':
          final direction = step.params['direction'] as String? ?? 'down';
          success = await _performScroll(direction);
          actionResult = success
              ? 'Scrolled $direction'
              : 'Could not scroll $direction';
          break;
        case 'press_back':
          success = await _screenService.pressBack();
          actionResult = 'Pressed back';
          break;
        case 'press_home':
          success = await _screenService.pressHome();
          actionResult = 'Pressed home';
          break;
        case 'open_app':
          final appName = step.params['app_name'] as String? ?? '';
          actionResult = await _appLauncher.openApp(appName);
          success = actionResult.startsWith('Opened');
          break;
        case 'wait':
          await Future.delayed(const Duration(seconds: 1));
          actionResult = 'Waited';
          success = true;
          break;
        case 'done':
          success = true;
          actionResult = 'Done step reached';
          break;
        default:
          success = false;
          actionResult = 'Unknown action: ${step.action}';
      }

      results.add('Memory Replay Step ${i + 1}: $actionResult');
      trace?.add({
        'step': i + 1,
        'action': step.action,
        'params': step.params,
        'reasoning': 'Skill Memory Replay: ${skill.task}',
        'result': actionResult,
        'status': success ? 'success' : 'failed',
        'timestamp': DateTime.now().toIso8601String(),
      });
      developer.log(
        '=== MEMORY REPLAY RESULT ===\n$actionResult',
        name: 'PrivateAgent',
      );

      if (!success) {
        return false; // Break out of replay if a step fails
      }
    }

    return true; // All steps succeeded
  }

  /// Returns predefined navigation steps for common tasks
  List<ActionStep>? _getNavigationShortcut(String goal) {
    final lower = goal.toLowerCase();

    if (lower.contains('dark mode') || lower.contains('dark theme')) {
      return [
        ActionStep(action: 'open_app', params: {'app_name': 'Settings'}),
        ActionStep(action: 'click_text', params: {'text': 'Display'}),
      ];
    }
    if (lower.contains('wifi') || lower.contains('wi-fi')) {
      return [
        ActionStep(action: 'open_app', params: {'app_name': 'Settings'}),
        ActionStep(
          action: 'click_text',
          params: {'text': 'Network & internet'},
        ),
      ];
    }
    if (lower.contains('bluetooth')) {
      return [
        ActionStep(action: 'open_app', params: {'app_name': 'Settings'}),
        ActionStep(action: 'click_text', params: {'text': 'Connected devices'}),
      ];
    }

    final appPatterns = <String, List<String>>{
      'Settings': ['settings', 'brightness', 'display', 'notification'],
      'Play Store': [
        'play store',
        'playstore',
        'download',
        'install app',
        'google play',
      ],
      'YouTube': ['youtube'],
      'WhatsApp': ['whatsapp'],
      'Chrome': ['chrome', 'browse', 'search google'],
      'Camera': ['camera', 'take a photo', 'take photo', 'take a picture'],
      'Gallery': ['gallery', 'photos'],
      'Messages': ['message', 'sms', 'text to'],
      'Phone': ['call', 'dial'],
      'Gmail': ['gmail', 'email'],
      'Maps': ['maps', 'navigate to', 'directions'],
      'Clock': ['alarm', 'timer', 'stopwatch'],
      'Calculator': ['calculator', 'calculate', 'calc'],
    };

    for (final entry in appPatterns.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) {
          return [
            ActionStep(action: 'open_app', params: {'app_name': entry.key}),
          ];
        }
      }
    }

    // Generic fallback for "open X"
    final openMatch = RegExp(r'^open\s+([a-zA-Z0-9]+)').firstMatch(lower);
    if (openMatch != null) {
      String app = openMatch.group(1)!;
      app = app[0].toUpperCase() + app.substring(1);
      return [
        ActionStep(action: 'open_app', params: {'app_name': app}),
      ];
    }

    return null;
  }

  /// Evaluates whether the screen state satisfies the routine's success criteria
  Future<bool> _evaluateSuccessCriteria({
    required String goal,
    required String criteria,
    required String screenContent,
    required String lastAction,
  }) async {
    const evalSystemPrompt = '''
You are an autonomous agent task evaluation auditor.
You are given a TASK GOAL, the SUCCESS CRITERIA, the LAST ACTION executed, and the CURRENT SCREEN DUMP.
Evaluate whether the success criteria has been completely fulfilled.

Respond with ONLY a JSON object:
{
  "criteria_met": true,
  "reasoning": "brief 1-sentence evaluation"
}
''';

    final prompt = '''
TASK GOAL: $goal
SUCCESS CRITERIA: $criteria
LAST ACTION TAKEN: $lastAction

CURRENT SCREEN:
$screenContent

Has the success criteria been completely met?
''';

    try {
      final res = await _aiService.sendTaskMessage(evalSystemPrompt, prompt);
      final jsonStr = _extractJson(res.content);
      final decoded = jsonDecode(jsonStr);
      return decoded['criteria_met'] == true;
    } catch (e) {
      developer.log('Success criteria evaluation error: $e',
          name: 'PrivateAgent');
      return false;
    }
  }

  /// Executes an AutonomousRoutine with iterative screen evaluation, bounded guardrails,
  /// ledger deduplication, and optional supervised confirmation.
  Future<String> executeAutonomousRoutine(
    AutonomousRoutine routine, {
    bool wasLockedInitially = false,
  }) async {
    await _screenService.setTaskKeepAwake(true, owner: 'routine_executor');
    try {
      return await _executeAutonomousRoutineInternal(
        routine,
        wasLockedInitially: wasLockedInitially,
      );
    } finally {
      await _screenService.setTaskKeepAwake(false, owner: 'routine_executor');
    }
  }

  Future<String> _executeAutonomousRoutineInternal(
    AutonomousRoutine routine, {
    bool wasLockedInitially = false,
  }) async {
    _cancelled = false;
    final List<String> results = [];
    final List<dynamic> executionTrace = [];
    int totalTokens = 0;
    _report('Starting autonomous routine: "${routine.name}"...');
    executionTrace.add({
      'info': 'Starting routine "${routine.name}" (Mode: ${routine.executionMode.name}, Max Steps: ${routine.guardrails.maxStepsPerRun})',
      'timestamp': DateTime.now().toIso8601String(),
    });

    // 1. If screen was locked initially, attempt unlock routine
    if (wasLockedInitially) {
      _report('Screen was locked. Waking device and requesting keyguard dismissal...');
      await _screenService.wakeScreen();
      await _screenService.dismissKeyguard();
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _screenService.isKeyguardLocked()) {
        // Temporarily uncover system lockscreen underneath MainActivity so swipe/PIN reaches OS lockscreen
        await _screenService.setShowWhenLocked(false);
        await Future.delayed(const Duration(milliseconds: 400));
        await _screenService.swipe(540, 1800, 540, 400);
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      if (routine.unlockSkillId != null) {
        _report('Attempting unlock skill: ${routine.unlockSkillId}...');
        final unlockSkill =
            CustomSkillService().getSkillById(routine.unlockSkillId!);
        if (unlockSkill != null && unlockSkill.steps.isNotEmpty) {
          for (final step in unlockSkill.steps) {
            if (_cancelled) break;
            if (step.actionTypeHint == 'click_text' &&
                step.expectedElementHint != null) {
              await _screenService.clickByText(step.expectedElementHint!);
            } else if (step.actionTypeHint == 'swipe') {
              await _screenService.swipe(540, 1800, 540, 400);
            }
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 1500));
      final stillLocked = await _screenService.isKeyguardLocked();
      if (stillLocked) {
        await _screenService.setShowWhenLocked(true);
        final msg =
            'Failed: Screen remained locked after unlock skill execution.';
        _report(msg);
        return msg;
      }
    }

    // 2. Resolve Persona system prompt modifier
    final allPersonas = PersonaService().getAllPersonas();
    final persona = allPersonas.firstWhere(
      (p) => p.id == routine.personaId,
      orElse: () => PersonaService().getActivePersona(),
    );
    final personaModifier = persona.systemPromptModifier.isNotEmpty
        ? '\nPERSONA INSTRUCTIONS (${persona.name}):\n${persona.systemPromptModifier}\n'
        : '';

    // 3. Resolve recent ledger context for anti-looping / deduplication
    final ledgerEntries = RoutineLedgerService().getRecentEntries(
      routineId: routine.id,
      limit: 10,
    );
    String ledgerContext = '';
    if (ledgerEntries.isNotEmpty) {
      final buffer = StringBuffer();
      buffer.writeln('\nRECENTLY REPLIED CONTACTS (DO NOT SEND DUPLICATES):');
      for (final entry in ledgerEntries) {
        buffer.writeln(
            '- ${entry.senderIdentifier}: "${entry.messageSnippet}" -> Replied: "${entry.agentReply}" [${entry.status}]');
      }
      ledgerContext = buffer.toString();
    }

    final maxSteps = routine.guardrails.maxStepsPerRun;
    String lastAction = '';
    int sameActionCount = 0;
    int consecutiveFailures = 0;

    // If currently inside PrivateAgent app, navigate to home first
    final currentPkg = await _screenService.getCurrentPackage();
    if (currentPkg == 'com.orailnoor.privateagent' ||
        currentPkg == 'com.orailnoor.privateagent.beta') {
      _report('Moving to background...');
      await _screenService.pressHome();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    for (int step = 0; step < maxSteps; step++) {
      if (_cancelled) {
        _report('Routine cancelled by user.');
        results.add('Routine cancelled by user.');
        executionTrace.add({
          'info': 'Routine cancelled by user.',
          'timestamp': DateTime.now().toIso8601String(),
        });
        await TaskHistoryLogger.logTask(
          routine.goalPrompt,
          'Cancelled',
          totalTokens,
          step,
          executionTrace,
        );
        return 'Routine cancelled.';
      }

      // Verify screen is still active & unlocked mid-routine
      final isInteractive = await _screenService.isScreenInteractive();
      final isLocked = await _screenService.isKeyguardLocked();
      if (!isInteractive || isLocked) {
        _report('Screen sleep/lock detected mid-routine. Restoring screen...');
        await _screenService.wakeScreen();
        await _screenService.dismissKeyguard();
        await Future.delayed(const Duration(milliseconds: 400));
        if (await _screenService.isKeyguardLocked()) {
          await _screenService.swipe(540, 1800, 540, 400);
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }

      int delay = 1200;
      if (lastAction == 'open_app') {
        delay = 3000;
      } else if (lastAction == 'type_text') {
        delay = 2000;
      } else if (lastAction == 'click_text' || lastAction == 'click_at') {
        delay = 1500;
      } else if (lastAction == 'scroll') {
        delay = 1000;
      }
      await Future.delayed(Duration(milliseconds: delay));

      // Read screen
      final screenContent = await _screenService.getScreenDescription();

      // Check success criteria evaluation after step 1
      if (step > 0 && lastAction.isNotEmpty) {
        _report('Evaluating screen against success criteria...');
        final criteriaMet = await _evaluateSuccessCriteria(
          goal: routine.goalPrompt,
          criteria: routine.successCriteria,
          screenContent: screenContent,
          lastAction: lastAction,
        );

        if (criteriaMet) {
          _report('Success criteria met! Routine complete.');
          results.add('Success criteria verified by evaluator.');
          executionTrace.add({
            'step': step + 1,
            'action': 'evaluator_check',
            'intent': 'Evaluate screen against success criteria',
            'reasoning': 'Evaluator verified success criteria met: "${routine.successCriteria}"',
            'result': 'Success criteria satisfied',
            'status': 'success',
            'timestamp': DateTime.now().toIso8601String(),
          });
          await _notificationService.showTaskCompleteNotification(
            'Routine Complete',
            'Routine "${routine.name}" finished successfully.',
          );
          await TaskHistoryLogger.logTask(
            routine.goalPrompt,
            'Success',
            totalTokens,
            step + 1,
            executionTrace,
          );
          return 'Done.';
        }
      }

      final prevResultStr = step > 0 && results.isNotEmpty
          ? '\nPREVIOUS ACTION RESULT: ${results.last}\n'
          : '';

      String failureHint = '';
      if (consecutiveFailures >= 3) {
        failureHint =
            '\n\nWARNING: You have failed $consecutiveFailures times in a row. Try a different approach.';
      }

      final prompt = '''
ROUTINE GOAL: ${routine.goalPrompt}
SUCCESS CRITERIA: ${routine.successCriteria}
$personaModifier$ledgerContext
CURRENT SCREEN TEXT DUMP:
$screenContent$prevResultStr$failureHint
Step ${step + 1}/$maxSteps. Look at the text dump. What is the single next action to make progress toward the success criteria?
''';

      String response;
      try {
        _cancelCompleter = Completer<void>();
        final aiFuture = _aiService.sendTaskMessage(_taskSystemPrompt, prompt);
        final result = await Future.any([
          aiFuture.then((r) => r),
          _cancelCompleter!.future.then((_) => null),
        ]);

        if (result == null || _cancelled) {
          return 'Routine cancelled.';
        }

        final aiResponse = result as AiResponse;
        response = aiResponse.content;
        totalTokens += aiResponse.totalTokens;
      } catch (e) {
        if (_cancelled) return 'Routine cancelled.';
        results.add('LLM Error: $e');
        consecutiveFailures++;
        continue;
      }

      Map<String, dynamic>? actionJson;
      try {
        final jsonStr = _extractJson(response);
        actionJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        results.add('Failed to parse AI action: $e');
        consecutiveFailures++;
        continue;
      }

      final action = actionJson['action'] as String? ?? '';
      final params = (actionJson['params'] as Map<String, dynamic>?) ?? {};
      final isComplete = actionJson['is_complete'] as bool? ?? false;
      final reasoning = actionJson['reasoning'] as String? ?? '';

      if (action == 'done' || isComplete) {
        _report('Routine signaled done.');
        results.add('Routine completed.');
        executionTrace.add({
          'step': step + 1,
          'action': 'done',
          'intent': reasoning.isNotEmpty ? reasoning : 'Routine completed',
          'reasoning': reasoning,
          'result': 'Routine finished successfully',
          'status': 'success',
          'timestamp': DateTime.now().toIso8601String(),
        });
        await TaskHistoryLogger.logTask(
          routine.goalPrompt,
          'Success',
          totalTokens,
          step + 1,
          executionTrace,
        );
        return 'Done.';
      }

      // Check Supervised approval gate if typing text / sending message
      if (action == 'type_text') {
        final textToType = params['text'] as String? ?? '';
        if (routine.executionMode == RoutineExecutionMode.supervised &&
            onConfirmationRequired != null) {
          _report('Supervised approval requested: "$textToType"');
          final approved = await onConfirmationRequired!(
              'Approve sending message: "$textToType"?');
          if (!approved || _cancelled) {
            results.add('Action rejected by user during supervised checkpoint.');
            executionTrace.add({
              'step': step + 1,
              'action': 'supervised_checkpoint',
              'params': {'text': textToType},
              'reasoning': 'Action requires supervised user confirmation',
              'result': 'Rejected by user during supervised checkpoint',
              'status': 'rejected',
              'timestamp': DateTime.now().toIso8601String(),
            });
            _report('Message skipped (rejected by user).');
            continue;
          }
        }
      }

      // Execute action
      _report('Action (${step + 1}/$maxSteps): $action $params');
      final success = await _executeActionCommand(action, params);
      final actionDesc = _formatActionDescription(action, params);

      executionTrace.add({
        'step': step + 1,
        'action': action,
        'params': params,
        'reasoning': reasoning,
        'result': success ? '$actionDesc succeeded' : '$actionDesc failed',
        'status': success ? 'success' : 'failed',
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (action == 'lock_screen' && success) {
        results.add('Screen locked as requested.');
        await TaskHistoryLogger.logTask(
          routine.goalPrompt,
          'Success',
          totalTokens,
          step + 1,
          executionTrace,
        );
        return 'Screen locked.';
      }

      if (success) {
        results.add('$action: success');
        consecutiveFailures = 0;

        // Record message in ledger if typing text
        if (action == 'type_text') {
          final sentText = params['text'] as String? ?? '';
          if (sentText.isNotEmpty) {
            unawaited(RoutineLedgerService().recordEntry(
              routineId: routine.id,
              targetAppPackage: currentPkg ?? 'unknown',
              senderIdentifier: 'WhatsApp Contact',
              messageSnippet: routine.goalPrompt,
              agentReply: sentText,
              status: 'sent',
            ));
          }
        }
      } else {
        results.add('$action: failed');
        consecutiveFailures++;
      }

      if (action == lastAction) {
        sameActionCount++;
        if (sameActionCount >= 3) {
          results.add('Loop detected: repeated $action 3 times.');
          executionTrace.add({
            'info': 'Loop detected: repeated $action 3 times. Pressed Back.',
            'timestamp': DateTime.now().toIso8601String(),
          });
          await _screenService.pressBack();
          sameActionCount = 0;
        }
      } else {
        sameActionCount = 1;
        lastAction = action;
      }
    }

    results.add(
        'Reached maximum step limit ($maxSteps) without fulfilling success criteria.');
    executionTrace.add({
      'info': 'Reached maximum step limit ($maxSteps) without fulfilling success criteria.',
      'timestamp': DateTime.now().toIso8601String(),
    });
    await TaskHistoryLogger.logTask(
      routine.goalPrompt,
      'Timeout',
      totalTokens,
      maxSteps,
      executionTrace,
    );
    return 'Max steps reached.';
  }

  Future<bool> _executeActionCommand(
    String action,
    Map<String, dynamic> params,
  ) async {
    switch (action) {
      case 'click_text':
        final text = params['text'] as String? ?? '';
        return await _screenService.clickByText(text);

      case 'click_at':
        final x = (params['x'] as num?)?.toDouble() ?? 0;
        final y = (params['y'] as num?)?.toDouble() ?? 0;
        return await _screenService.clickAt(x, y);

      case 'type_text':
        final text = params['text'] as String? ?? '';
        final hint = params['field_hint'] as String?;
        return await _screenService.typeText(text, fieldHint: hint);

      case 'press_enter':
        return await _submitKeyboardAction();

      case 'swipe':
        final startX = (params['startX'] as num?)?.toDouble() ?? 540;
        final startY = (params['startY'] as num?)?.toDouble() ?? 2000;
        final endX = (params['endX'] as num?)?.toDouble() ?? 540;
        final endY = (params['endY'] as num?)?.toDouble() ?? 500;
        return await _performSwipe(startX, startY, endX, endY);

      case 'scroll':
        final direction = params['direction'] as String? ?? 'down';
        return await _performScroll(direction);

      case 'press_back':
        return await _screenService.pressBack();

      case 'press_home':
        return await _screenService.pressHome();

      case 'open_app':
        final appName = params['app_name'] as String? ?? '';
        final res = await _appLauncher.openApp(appName);
        return res.startsWith('Opened');

      case 'lock_screen':
        await _screenService.setTaskKeepAwake(false, owner: 'routine_executor');
        await _screenService.setKeepScreenOn(false);
        await _screenService.stopExecutionMode(returnToListener: true);
        await Future.delayed(const Duration(milliseconds: 150));
        return await _screenService.lockScreen();

      case 'wait':
        await Future.delayed(const Duration(seconds: 1));
        return true;

      default:
        return false;
    }
  }

  String _formatActionDescription(String action, Map<String, dynamic> params) {
    switch (action) {
      case 'click_text':
        return 'Click "${params['text'] ?? ''}"';
      case 'click_at':
        return 'Click at (${params['x']}, ${params['y']})';
      case 'type_text':
        return 'Type "${params['text'] ?? ''}"';
      case 'press_enter':
        return 'Press Enter';
      case 'scroll':
        return 'Scroll ${params['direction'] ?? 'down'}';
      case 'swipe':
        return 'Swipe (${params['startX']}, ${params['startY']}) -> (${params['endX']}, ${params['endY']})';
      case 'open_app':
        return 'Open app "${params['app_name'] ?? ''}"';
      case 'lock_screen':
        return 'Lock Screen';
      case 'press_back':
        return 'Press Back';
      case 'press_home':
        return 'Press Home';
      case 'wait':
        return 'Wait';
      case 'done':
        return 'Done';
      default:
        return '$action $params';
    }
  }
}
