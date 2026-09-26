import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

/// Manages the on-device Gemma 3 1B model lifecycle.
///
/// Single responsibility: load once, infer on demand.
/// The model is ~1GB — loaded lazily on first use to avoid
/// blocking app startup. All inference is fully on-device.
///
/// Usage:
///   final result = await LlmService.instance.infer(prompt);
class LlmService {
  LlmService._internal();
  static final LlmService instance = LlmService._internal();

  static const _modelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
      'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm';

  bool _initialized = false;
  bool _modelReady = false;
  bool _loading = false;

  /// Call once in main() before runApp — registers the inference engine.
  /// Does NOT download the model yet.
  static Future<void> initialize() async {
    await FlutterGemma.initialize(
      inferenceEngines: [LiteRtEngine()],
    );
  }

  /// True once the model has been downloaded and is ready to use.
  bool get isReady => _modelReady;

  /// True while the model is being downloaded.
  bool get isLoading => _loading;

  /// Downloads and loads the Gemma 3 1B model.
  /// Safe to call multiple times — no-ops if already loaded or loading.
  /// [onProgress] receives 0.0–1.0 download progress.
  Future<void> loadModel({void Function(double)? onProgress}) async {
    if (_modelReady || _loading) return;
    _loading = true;

    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(_modelUrl)
          .install(onProgress: onProgress != null
              ? (received, total) {
                  if (total > 0) onProgress(received / total);
                }
              : null);

      _modelReady = true;
    } finally {
      _loading = false;
    }
  }

  /// Runs a single inference.
  ///
  /// Returns empty string if the model isn't ready yet — callers
  /// must check [isReady] or catch the empty result and fall back
  /// to the rule-based path.
  Future<String> infer(String prompt, {int maxTokens = 256}) async {
    if (!_modelReady) return '';

    final model = await FlutterGemma.getActiveModel(maxTokens: maxTokens);
    final chat = await model.createChat();
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final response = await chat.generateChatResponse();
    return response?.text ?? '';
  }

  /// Classifies a task description into one of the given [categories].
  ///
  /// Returns the best-matching category, or null if uncertain.
  /// Falls back to null if model isn't ready.
  Future<String?> classifyTaskCategory(
    String taskDescription, {
    required List<String> categories,
  }) async {
    if (!_modelReady) return null;

    final categoryList = categories.join(', ');
    final prompt = '''
You are a task classifier. Given a task description, output ONLY the single best category from this list: $categoryList

Task: "$taskDescription"

Output only the category name, nothing else.''';

    final result = await infer(prompt, maxTokens: 16);
    final trimmed = result.trim();

    // Validate the response is actually one of our categories.
    for (final cat in categories) {
      if (trimmed.toLowerCase() == cat.toLowerCase()) return cat;
    }

    // Partial match fallback.
    for (final cat in categories) {
      if (trimmed.toLowerCase().contains(cat.toLowerCase())) return cat;
    }

    return null;
  }

  /// Extracts user preferences from a free-text task description.
  ///
  /// Returns a map of preference keys to values, e.g.:
  ///   {'lead_time_minutes': '10', 'voice_disabled': 'false'}
  ///
  /// Returns empty map if model isn't ready (caller uses rule-based fallback).
  Future<Map<String, String>> extractPreferences(
    String taskDescription,
    String category,
  ) async {
    if (!_modelReady) return {};

    final prompt = '''
You are a preference extractor. Read the task description and extract scheduling preferences.

Task category: $category
Task description: "$taskDescription"

Answer each question with a single value:
1. How many minutes before the task should the reminder fire? (0 if no preference, max 60) Answer with just the number.
2. Should voice reminders be disabled for this task? (yes/no)

Output format — two lines only:
lead_time: <number>
voice_disabled: <yes/no>''';

    final result = await infer(prompt, maxTokens: 32);
    final prefs = <String, String>{};

    for (final line in result.split('\n')) {
      final parts = line.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim().toLowerCase();
        final value = parts[1].trim().toLowerCase();
        if (key == 'lead_time') {
          final minutes = int.tryParse(value);
          if (minutes != null && minutes >= 0 && minutes <= 60) {
            prefs['lead_time_minutes'] = minutes.toString();
          }
        } else if (key == 'voice_disabled') {
          prefs['voice_disabled'] = (value == 'yes') ? 'true' : 'false';
        }
      }
    }

    return prefs;
  }

  /// Generates a plain-language explanation of a scheduling decision.
  ///
  /// Used by the Reasoning Trace Engine.
  /// Returns empty string if model isn't ready.
  Future<String> explainDecision({
    required String taskName,
    required String decisionType,
    required Map<String, dynamic> context,
  }) async {
    if (!_modelReady) return '';

    final contextLines = context.entries
        .map((e) => '  ${e.key}: ${e.value}')
        .join('\n');

    final prompt = '''
You are a helpful scheduling assistant. Explain this scheduling decision in 1–2 plain sentences that a non-technical user would understand.

Task: "$taskName"
Decision: $decisionType
Context:
$contextLines

Write your explanation in a friendly, direct tone. No jargon.''';

    return await infer(prompt, maxTokens: 96);
  }
}
