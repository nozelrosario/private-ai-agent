import 'dart:async';
import 'package:flutter/services.dart';
import '../models/custom_skill.dart';

class TeachModeService {
  static final TeachModeService _instance = TeachModeService._internal();
  factory TeachModeService() => _instance;
  TeachModeService._internal();

  static const _eventChannel = EventChannel('com.privateagent/accessibility_events');
  StreamSubscription? _subscription;

  bool _isRecording = false;
  final List<RecipeStep> _recordedSteps = [];

  bool get isRecording => _isRecording;
  List<RecipeStep> get currentSteps => List.unmodifiable(_recordedSteps);

  void startRecording() {
    _recordedSteps.clear();
    _isRecording = true;

    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!_isRecording || event is! Map) return;
        final type = event['type'] as String? ?? '';

        if (type == 'click') {
          final text = event['text'] as String? ?? '';
          final x = event['x'];
          final y = event['y'];

          final instruction = text.isNotEmpty
              ? 'Click "$text"'
              : 'Tap at coordinates ($x, $y)';

          _recordedSteps.add(
            RecipeStep(
              stepNumber: _recordedSteps.length + 1,
              instruction: instruction,
              expectedElementHint: text.isNotEmpty ? text : null,
              actionTypeHint: text.isNotEmpty ? 'click_text' : 'click_at',
            ),
          );
        } else if (type == 'scroll') {
          // Avoid recording consecutive duplicate scrolls
          if (_recordedSteps.isNotEmpty && _recordedSteps.last.actionTypeHint == 'scroll') {
            return;
          }
          _recordedSteps.add(
            RecipeStep(
              stepNumber: _recordedSteps.length + 1,
              instruction: 'Scroll down to find next element',
              actionTypeHint: 'scroll',
            ),
          );
        }
      },
      onError: (err) {
        _isRecording = false;
      },
    );
  }

  List<RecipeStep> stopRecording() {
    _isRecording = false;
    _subscription?.cancel();
    _subscription = null;
    return List.from(_recordedSteps);
  }
}
