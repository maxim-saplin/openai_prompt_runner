import 'dart:collection';

import 'package:openai_prompt_runner/openai_prompt_runner.dart';

void main() async {
  var runner = PromptRunner(
      prepareAndSendPrompt: prepareAndSendPrompt,
      parallelWorkers: 4,
      apiUri: getAzueOpenAiUri('openai.azure.com', 'gpt3'),
      apiKeys: UnmodifiableListView(['key1', 'key2']),
      breakOnError: false,
      apiErrorRetries: 5,
      totalIterations: 10,
      startAtIteration: 0);
  await runner.run();
}

Prompt prepareAndSendPrompt(int iteration, DateTime promtStartedAt,
    Future<PromptResult> promptResult, PromptRunner runner) {
  var role = 'AI assistant'; // aka System Message
  var prompt = 'What is ${iteration + 1} + ${iteration + 1}?';
  var sum = (iteration + 1) * 2;

  promptResult.then((value) {
    // Logs are saved to each run's folder, prompt timings are printed
    runner.logWithPromptStats(
        (value.result == sum.toString()).toString(), value);
  }, onError: (e) {
    runner.logPrint(e);
  });
  return Prompt(systemMessage: role, prompt: prompt);
}
