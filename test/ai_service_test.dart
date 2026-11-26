import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/ai_service.dart';

void main() {
  test('recognizes only the NVIDIA hosted API URL', () {
    expect(
      AiService.isNvidiaBaseUrl('https://integrate.api.nvidia.com/v1'),
      isTrue,
    );
    expect(AiService.isNvidiaBaseUrl('https://api.deepseek.com'), isFalse);
  });

  test('NVIDIA model picker keeps only verified free chat models', () {
    final models = AiService.filterNvidiaFreeModels([
      'paid/partner-model',
      'nvidia/nemotron-3-super-120b-a12b',
      'nvidia/embed-qa-4',
      'openai/gpt-oss-20b',
    ]);

    expect(models, ['nvidia/nemotron-3-super-120b-a12b', 'openai/gpt-oss-20b']);
  });

  test('GLM is the default NVIDIA model', () {
    expect(AiService.nvidiaDefaultModel, 'z-ai/glm-5.2');
    expect(AiService.nvidiaFreeChatModels.first, 'z-ai/glm-5.2');
  });

  test('parseAction extracts JSON actions cleanly including prose-prefixed fenced responses', () {
    final ai = AiService();

    final raw = ai.parseAction(
      '{"action": "execute_task", "params": {"goal": "open whatsapp"}, "response": "Opening WhatsApp"}',
    );
    expect(raw, isNotNull);
    expect(raw!.action, 'execute_task');
    expect(raw.params['goal'], 'open whatsapp');

    final prefixedFence = ai.parseAction(
      'Sure, running that now:\n```json\n{"action": "execute_task", "params": {"goal": "check whatsapp"}, "response": "Checking"}\n```',
    );
    expect(prefixedFence, isNotNull);
    expect(prefixedFence!.action, 'execute_task');
    expect(prefixedFence.params['goal'], 'check whatsapp');

    final plainChat = ai.parseAction('Hello! How can I help you today?');
    expect(plainChat, isNull);
  });
}
