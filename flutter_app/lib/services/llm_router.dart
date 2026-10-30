/// One entry point for every feature that needs an LLM.
///
/// Order:
///   * a configured cloud AI (Claude subscription/API, ChatGPT, custom)
///     answers FIRST — before, the router asked the on-device model and
///     Ollama first, so connecting Claude visibly changed nothing;
///   * Ollama and the on-device model are the fallback when the cloud is
///     not configured, unreachable, or the user switched on offline mode.
///
/// The on-device model (0.5–1.5B, 1024-token window) is only used for tasks
/// that allow it: it cannot hold a training/feed prompt, and small models
/// must never write into the error memory.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'ai_client.dart';
import 'ai_types.dart';
import 'local_llm_service.dart';

class LlmRouter {
  final ConfigService _config;
  final LocalLlmService? _local;
  final AiClient? _ai;
  final http.Client _http;

  LlmRouter(this._config,
      {LocalLlmService? local, AiClient? ai, http.Client? httpClient})
      : _local = local,
        _ai = ai,
        _http = httpClient ?? http.Client();

  static const _fallbackCap = Duration(seconds: 60);

  bool get _hasLocal => _local != null && _local!.isUsable;
  bool get _hasOllama => _config.ollamaEnabled && _config.ollamaUrl.isNotEmpty;
  bool get _hasCloud => _ai != null && _ai!.isConfigured;

  /// True iff at least one backend could be tried. Cheap, synchronous.
  bool get isAvailable => _hasLocal || _hasOllama || _hasCloud;

  /// True iff a backend good enough for long, learner-facing text exists.
  bool get hasQualityBackend => _hasCloud || _hasOllama;

  List<String> _order({required bool allowOnDevice}) {
    final cloudFirst = _hasCloud && !_config.offlineMode;
    return [
      if (cloudFirst) 'cloud',
      if (_hasOllama) 'ollama',
      if (_hasLocal && allowOnDevice) 'local',
      if (_hasCloud && !cloudFirst) 'cloud',
    ];
  }

  /// Name of the backend that will be tried first.
  String get backendName {
    final order = _order(allowOnDevice: true);
    if (order.isEmpty) return 'ИИ не настроен';
    return switch (order.first) {
      'cloud' => _ai!.providerName,
      'ollama' => 'Ollama/${_config.ollamaModel}',
      _ => _config.localLlmModelName,
    };
  }

  /// Why nothing is available, in actionable words.
  String get unavailableReason {
    if (_ai != null && !_ai!.isConfigured && _config.aiProvider != 'auto') {
      return _ai!.notConfiguredReason();
    }
    return 'ИИ не настроен. На компьютере проще всего выбрать «Claude · '
        'подписка» (нужен установленный и залогиненный Claude Code). '
        'Бесплатно: Ollama с моделью или бесплатный совместимый сервис '
        '(Gemini, Groq) в Настройках.';
  }

  /// Backwards-compatible text completion.
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 8000,
    String effort = 'medium',
    Duration timeout = const Duration(minutes: 3),
    bool allowOnDevice = true,
    String feature = '',
  }) async =>
      (await completeResult(
        system: system,
        user: user,
        maxTokens: maxTokens,
        effort: effort,
        timeout: timeout,
        allowOnDevice: allowOnDevice,
        feature: feature,
      ))
          .text;

  /// Run [system] + [user] through the first working backend and report
  /// which one answered.
  Future<AiResult> completeResult({
    required String system,
    required String user,
    int maxTokens = 8000,
    String effort = 'medium',
    Map<String, dynamic>? jsonSchema,
    Duration timeout = const Duration(minutes: 3),
    bool allowOnDevice = true,
    String feature = '',
    /// false: only the first backend — «Проверить подключение» tests the
    /// chosen provider and must not wait minutes for a slow Ollama.
    bool fallback = true,
    /// 'fast' for interactive answers, 'main' for long texts (the feed).
    String tier = 'main',
    /// Let the cloud model search the web (ignored by Ollama/on-device).
    bool webSearch = false,
    /// Files for the model (PDFs): only the cloud can read them.
    List<AiDocument> documents = const [],
  }) async {
    var order = _order(allowOnDevice: allowOnDevice);
    if (order.isEmpty) throw AiException(unavailableReason);
    if (!fallback) order = order.take(1).toList();
    if (documents.isNotEmpty) {
      order = order.where((b) => b == 'cloud').toList();
      if (order.isEmpty) {
        throw const AiException('PDF читает только Claude (подписка на ПК или '
            'API-ключ) — подключите его в Настройках или вставьте текст.');
      }
    }

    // The FIRST backend's error is the one that matters (it is the provider
    // the user chose); fallbacks failing too are appended, never swapped in.
    final errors = <(String, Object)>[];
    for (final backend in order) {
      try {
        switch (backend) {
          case 'cloud':
            return await _ai!.completeResult(
              system: system,
              user: user,
              maxTokens: maxTokens,
              effort: effort,
              jsonSchema: jsonSchema,
              timeout: timeout,
              feature: feature,
              tier: tier,
              webSearch: webSearch,
              documents: documents,
            );
          case 'ollama':
            // As a fallback, a slow CPU model must not hold the user for the
            // cloud's full timeout (it was 120 s and more).
            return await _ollama(system, user, maxTokens, jsonSchema,
                backend == order.first || timeout < _fallbackCap
                    ? timeout
                    : _fallbackCap);
          case 'local':
            final sw = Stopwatch()..start();
            final out = await _local!.generate(jsonSchema == null
                ? '$system\n\n---\n\n$user'
                : '$system\n\nReturn only JSON.\n\n---\n\n$user');
            if (out.trim().isEmpty) {
              throw const AiException('Локальная модель вернула пустой ответ');
            }
            final r = AiResult(
              text: out.trim(),
              backend: _config.localLlmModelName,
              provider: 'local',
              model: _config.localLlmModelName,
              durationMs: sw.elapsedMilliseconds,
              localEndpoint: true,
            );
            return jsonSchema == null
                ? r
                : r.withJson(extractJsonObject(out));
        }
      } catch (e) {
        errors.add((backend, e));
      }
    }
    final (firstBackend, first) = errors.first;
    final primary = first is AiException ? first.message : '$first';
    final rest = errors.skip(1).map((e) {
      final name = switch (e.$1) {
        'cloud' => _ai?.providerName ?? 'облако',
        'ollama' => 'Ollama',
        _ => 'локальная модель',
      };
      final msg = e.$2 is AiException ? (e.$2 as AiException).message : '${e.$2}';
      return '$name: $msg';
    }).toList();
    throw AiException(
      rest.isEmpty ? primary : '$primary\n\nЗапасные варианты тоже не сработали — ${rest.join('; ')}',
      detail: [
        for (final e in errors)
          '${e.$1}: ${e.$2 is AiException ? ((e.$2 as AiException).detail ?? (e.$2 as AiException).message) : e.$2}'
      ].join('\n'),
      retryable: first is AiException && first.retryable && firstBackend == 'cloud',
    );
  }

  // ─────────────────────────────────────────── Ollama

  DateTime? _tagsAt;
  Set<String> _tags = const {};

  /// Checks /api/tags (cached 2 min) so a model that was never pulled fails
  /// fast with the exact fix instead of a raw 404 from /api/chat.
  Future<void> _ensureOllamaModel(String base) async {
    final now = DateTime.now();
    if (_tagsAt == null || now.difference(_tagsAt!) > const Duration(minutes: 2)) {
      try {
        final resp = await _http
            .get(Uri.parse('$base/api/tags'))
            .timeout(const Duration(seconds: 4));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _tags = ((data['models'] as List?) ?? const [])
            .map((m) => (m as Map)['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toSet();
        _tagsAt = now;
      } catch (_) {
        throw AiException('Ollama не запущена по адресу $base');
      }
    }
    final model = _config.ollamaModel;
    final has = _tags.any((n) => n == model || n == '$model:latest' ||
        (!model.contains(':') && n.startsWith('$model:')));
    if (!has) {
      throw AiException('В Ollama нет модели «$model». Выполните в '
          'терминале: ollama pull $model — или выключите Ollama в Настройках.');
    }
  }

  Future<AiResult> _ollama(String system, String user, int maxTokens,
      Map<String, dynamic>? jsonSchema, Duration timeout) async {
    final base = _config.ollamaUrl.trim().replaceAll(RegExp(r'/+$'), '');
    await _ensureOllamaModel(base);
    final sw = Stopwatch()..start();
    final http.Response resp;
    try {
      resp = await _http
          .post(
            Uri.parse('$base/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': _config.ollamaModel,
              'stream': false,
              if (jsonSchema != null) 'format': jsonSchema,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
              'options': {'temperature': 0.3, 'num_predict': maxTokens},
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException('Ollama не ответила за ${timeout.inSeconds} с '
          '(на процессоре большие модели работают медленно).');
    }

    if (resp.statusCode != 200) {
      throw AiException('Ollama: ошибка ${resp.statusCode}',
          detail: resp.body);
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final text = (data['message']?['content'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw AiException('Ollama вернула пустой ответ — проверьте, что модель '
          '«${_config.ollamaModel}» скачана (ollama pull ${_config.ollamaModel})');
    }
    final r = AiResult(
      text: text,
      backend: 'Ollama/${_config.ollamaModel}',
      provider: 'ollama',
      model: _config.ollamaModel,
      inputTokens: (data['prompt_eval_count'] as num?)?.toInt() ?? 0,
      outputTokens: (data['eval_count'] as num?)?.toInt() ?? 0,
      durationMs: sw.elapsedMilliseconds,
      localEndpoint: true,
    );
    return jsonSchema == null ? r : r.withJson(extractJsonObject(text));
  }
}
