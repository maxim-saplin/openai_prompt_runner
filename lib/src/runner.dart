import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Directory where all logs created by prompt runners will be saved
String logsDirectory = 'logs';

/// Return role and prompt text
typedef PrepareAndSendPrompt = Prompt Function(
    int iteration,
    DateTime promtStartedAt,
    Future<PromptResult> promptResult,
    PromptRunner runner);

Uri getAzueOpenAiUri(String endpoint, String deployment) {
  return Uri.parse(
      'https://$endpoint/openai/deployments/$deployment/chat/completions?api-version=2023-03-15-preview');
}

/// Schedules the given number of prompts, runs them in parallel and can use/rotate multiple API keys
/// Each prompt iteration has three states: SENT, SUCEESS, ERROR -> each has a callback
class PromptRunner {
  /// A class for running an OpenAI prompt.
  PromptRunner({
    required this.prepareAndSendPrompt,
    required this.parallelWorkers,
    required this.apiUri,
    required this.apiKeys,
    required this.breakOnError,
    required this.onApiErrorRetries,
    required totalIterations,
    required this.startAtIteration,
    this.stopAtIteration,
  }) : totalIterations = stopAtIteration ?? totalIterations {
    if (apiKeys.isEmpty) {
      throw 'No API keys provided';
    }
    _currentIteration = startAtIteration;
  }

  final PrepareAndSendPrompt prepareAndSendPrompt;
  final int parallelWorkers;
  final UnmodifiableListView<String> apiKeys;
  final bool breakOnError;
  final int onApiErrorRetries;
  final int totalIterations;
  final int startAtIteration;
  final int? stopAtIteration;
  int _currentIteration = 0;
  int get currentIteration => _currentIteration;
  var _completeCounter = 0;
  int get completeCounter => _completeCounter;
  var _promptsScheduled = 0;
  final _runCompleter = Completer();
  final _sw = Stopwatch();
  bool _errorsHappened = false;
  final Uri apiUri;

  Duration get elapsed => _sw.elapsed;

  Future run() async {
    _sw.start();
    scheduleMorePromptsInParallel();
    return _runCompleter.future;
  }

  void scheduleMorePromptsInParallel() {
    //try {
    while (_promptsScheduled < parallelWorkers) {
      if (_currentIteration > totalIterations) {
        if (_promptsScheduled > 0) {
          // There're few more futures to be finilized
          return;
        }
        if (!_runCompleter.isCompleted) {
          if (_errorsHappened) {
            _runCompleter.completeError(
                "There were swallowed errors while doing the run");
          } else {
            _runCompleter.complete();
          }
          _sw.stop();
        }
        return;
      }
      _doNextPrompt();
      _currentIteration++;
      _promptsScheduled++;
    }
    // } catch (e) {
    //   logPrint('$e');
    //   if (breakOnError) {
    //     _runCompleter.completeError(e);
    //     _sw.stop();
    //   }
    // }
  }

  void _doNextPrompt() async {
    var promtStartedAt = DateTime.now();

    var promptCompleter = Completer<PromptResult>();
    var curIteration = _currentIteration;
    var prompt = prepareAndSendPrompt(
        curIteration, promtStartedAt, promptCompleter.future, this);

    var retriesLeft = onApiErrorRetries;

    while (retriesLeft > 0) {
      try {
        var value = await _openAICall(prompt);
        if (_runCompleter.isCompleted) {
          return;
        }

        _completeCounter++;
        _promptsScheduled--;
        if (!promptCompleter.isCompleted) {
          promptCompleter.complete(value);
        }
        scheduleMorePromptsInParallel();
      } catch (e) {
        _errorsHappened = true;
        if (_runCompleter.isCompleted) {
          return;
        }

        //logPrint('$e');
        retriesLeft--;

        if (breakOnError) {
          if (!promptCompleter.isCompleted) {
            promptCompleter.completeError(e);
          }
          if (!_runCompleter.isCompleted) {
            _runCompleter.completeError(e);
          }
          _completeCounter++;
          retriesLeft = 0;
        } else if (retriesLeft < 1) {
          _promptsScheduled--;
          _completeCounter++;

          if (!promptCompleter.isCompleted) {
            promptCompleter.completeError(e);
          }

          scheduleMorePromptsInParallel();
        } else {
          logPrint('\n#$curIteration error, retries left $retriesLeft\n$e\n');
        }
      }
    }
  }

  String getAPIKey() => apiKeys[_currentIteration % apiKeys.length];

  Future<PromptResult> _openAICall(Prompt prompt) async {
    // TODO, add timeouts on the client side
    final response = await http.post(
      apiUri,
      headers: {
        'Content-Type': 'application/json',
        'api-key': getAPIKey(),
      },
      body: jsonEncode({
        'temperature': prompt.temperature,
        'top_p': prompt.topp,
        'max_tokens': prompt.maxTokens,
        'messages': [
          {'role': 'system', 'content': prompt.role},
          {'role': 'user', 'content': prompt.prompt},
        ],
      }),
    );

    final String rawResponse = response.body;
    final data = jsonDecode(rawResponse);

    if (data is Map && data.containsKey('error')) {
      throw rawResponse;
    }

    final String result = data['choices'][0]['message']['content'];
    final int totalTokens = data['usage']['total_tokens'];
    final int promptTokens = data['usage']['prompt_tokens'];

    final PromptResult promptResult = PromptResult(
      rawResponse,
      result,
      totalTokens,
      promptTokens,
    );

    return promptResult;
  }

  /// This is essentialy an ID of the run as well as date/time of run creation
  final DateTime promptRunAt = DateTime.now();

  var _currentLogFilePath = '';
  var _currentRunLogDirectory = '';

  void logPrint(String message) {
    if (_currentLogFilePath.isEmpty) {
      _currentRunLogDirectory = '$logsDirectory/$promptRunAt';
      var file = File('$_currentRunLogDirectory/_log');
      if (!file.existsSync()) {
        file.createSync(recursive: true);
        _currentLogFilePath = file.path;
      }
    }

    File(_currentLogFilePath)
        .writeAsStringSync('$message\n', mode: FileMode.append);
    print(message);
  }

  void logPrompt(String tag, String rawBody) {
    var currentLogFilePath = '$_currentRunLogDirectory/$tag';

    File(currentLogFilePath).writeAsStringSync(rawBody, mode: FileMode.append);
  }

  /// Helper method adding propmpt completion general stats and run timmings
  void logWithPromptStats(String message, PromptResult result) {
    var secPerPropmt = (elapsed.inSeconds / (completeCounter));

    logPrint('$message, tokens (${result.promptTokens}|${result.totalTokens}), '
        'elapsed ${elapsed.inMinutes}m${elapsed.inSeconds % 60}s, propmpts complete ${completeCounter + startAtIteration + 1}/$totalIterations, '
        'avg sec/prompt ${secPerPropmt.toStringAsFixed(1)} '
        'remaining ${((totalIterations - startAtIteration - completeCounter) * secPerPropmt / 60).toStringAsFixed(1)}m');
  }
}

class Prompt {
  final String role;
  final String prompt;
  final double temperature;
  final double topp;
  final int maxTokens;

  const Prompt({
    required this.role,
    required this.prompt,
    this.temperature = 0.7,
    this.topp = 1.0,
    this.maxTokens = 800,
  });
}

class PromptResult {
  final String rawResponse;
  final String result;
  final int totalTokens;
  final int promptTokens;

  PromptResult(
    this.rawResponse,
    this.result,
    this.totalTokens,
    this.promptTokens,
  );
}

Map<String, String> getPairsFromPrompt(String result) {
  var pairs = <String, String>{};

  RegExp exp = RegExp(r'(.+)\|(.+)(\n|$)');
  Iterable<RegExpMatch> matchesIter = exp.allMatches(result);
  for (RegExpMatch match in matchesIter) {
    String? key = match.group(1);
    String? value = match.group(2);
    if (key != null && value != null) {
      pairs[key] = value;
    }
  }

  return pairs;
}
