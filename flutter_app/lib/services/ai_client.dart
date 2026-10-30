/// Cloud LLM client: Claude via the user's subscription (Claude Code CLI),
/// Claude via the API, ChatGPT, and any OpenAI-compatible service.
///
/// Dart has no official Anthropic SDK, so the API path speaks raw HTTP to
/// `POST /v1/messages`. Selection is strict: an explicitly chosen provider
/// is the only one used — no silent fallback to another account.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/database.dart';
import 'ai_types.dart';
import 'claude_code_client.dart';
import 'relay_server.dart' show RelayRequest;

class AiClient {
  final ConfigService _config;
  final http.Client _http;
  final String _anthropicBase;
  final ClaudeCodeClient? _claudeCode;
  final DatabaseService? _usageLog;

  AiClient(
    this._config, {
    http.Client? httpClient,
    String anthropicBaseUrl = 'https://api.anthropic.com',
    ClaudeCodeClient? claudeCode,
    DatabaseService? usageLog,
  })  : _http = httpClient ?? http.Client(),
        _anthropicBase = anthropicBaseUrl.replaceAll(RegExp(r'/+$'), ''),
        _claudeCode = claudeCode,
        _usageLog = usageLog;

  ClaudeCodeClient? get claudeCode => _claudeCode;

  bool get isConfigured => _providerOrder().isNotEmpty;

  String get providerName {
    final order = _providerOrder();
    if (order.isEmpty) return 'ИИ не настроен';
    return _labelFor(order.first);
  }

  String get _customLabel =>
      _config.customModel.isNotEmpty ? _config.customModel : 'Свой сервис';

  String _labelFor(String provider) => switch (provider) {
        'claude_code' =>
          'Claude ${claudeModelLabel(_config.anthropicModel)} · подписка',
        'pc_relay' => 'Claude через компьютер',
        'claude' => 'Claude ${claudeModelLabel(_config.anthropicModel)} · API',
        'chatgpt' => 'ChatGPT',
        _ => _customLabel,
      };

  bool get _customConfigured =>
      _config.customApiBaseUrl.isNotEmpty && _config.customModel.isNotEmpty;

  bool get _claudeCodeAvailable => _claudeCode?.locate() != null;

  bool get _relayConfigured =>
      _config.relayUrl.trim().isNotEmpty &&
      _config.relayClientCode.trim().isNotEmpty;

  /// STRICT: a specific provider means only that provider. 'auto' tries
  /// whatever is configured, the subscription first (it costs nothing extra).
  List<String> _providerOrder() {
    final claudeKey = _config.anthropicApiKey.isNotEmpty;
    final chatgpt = _config.openaiApiKey.isNotEmpty;
    switch (_config.aiProvider) {
      case 'claude_code':
        return [if (_claudeCodeAvailable) 'claude_code'];
      case 'pc_relay':
        return [if (_relayConfigured) 'pc_relay'];
      case 'claude':
        return [if (claudeKey) 'claude'];
      case 'chatgpt':
        return [if (chatgpt) 'chatgpt'];
      case 'custom':
        return [if (_customConfigured) 'custom'];
      default: // 'auto'
        return [
          if (_claudeCodeAvailable) 'claude_code',
          if (_relayConfigured) 'pc_relay',
          if (claudeKey) 'claude',
          if (chatgpt) 'chatgpt',
          if (_customConfigured) 'custom',
        ];
    }
  }

  /// Why [isConfigured] is false, in words the user can act on.
  String notConfiguredReason() {
    switch (_config.aiProvider) {
      case 'claude_code':
        return 'Выбран Claude по подписке, но Claude Code не найден на этом '
            'компьютере. Установите его (claude.com/claude-code) и войдите '
            '(`claude` → /login), либо выберите другой ИИ.';
      case 'pc_relay':
        return 'Выбран Claude через компьютер, но не указаны адрес компьютера '
            'и код подключения. Их показывает LinguaTrace на ПК: Настройки → '
            'ИИ-помощник → «Claude для телефона».';
      case 'claude':
        return 'Выбран Claude по API-ключу, но ключ не задан. Нужен ключ '
            'sk-ant-api03-… из console.anthropic.com (подписка claude.ai '
            'не оплачивает API).';
      case 'chatgpt':
        return 'Выбран ChatGPT, но его ключ не задан.';
      case 'custom':
        return 'Свой сервис выбран, но не настроен — укажите адрес API и '
            'название модели.';
      default:
        return 'ИИ не настроен: выберите Claude (подписка или ключ), ChatGPT '
            'или свой сервис в Настройках.';
    }
  }

  /// Backwards-compatible text completion.
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 8000,
    String effort = 'medium',
    Duration timeout = const Duration(minutes: 5),
    String feature = '',
  }) async =>
      (await completeResult(
        system: system,
        user: user,
        maxTokens: maxTokens,
        effort: effort,
        timeout: timeout,
        feature: feature,
      ))
          .text;

  /// Full completion with provenance and usage. [jsonSchema] requests
  /// structured output where the backend supports it.
  Future<AiResult> completeResult({
    required String system,
    required String user,
    int maxTokens = 8000,
    String effort = 'medium',
    Map<String, dynamic>? jsonSchema,
    Duration timeout = const Duration(minutes: 5),
    String feature = '',
    /// 'fast' — interactive answers on [ConfigService.fastModel]; 'main' —
    /// long texts on [ConfigService.anthropicModel].
    String tier = 'main',
    /// Let Claude search the web (API: the web search tool; subscription:
    /// Claude Code's WebSearch/WebFetch). Other providers ignore it.
    bool webSearch = false,
    /// PDFs for Claude: API document blocks, or Claude Code's Read tool.
    List<AiDocument> documents = const [],
  }) async {
    var order = _providerOrder();
    if (order.isEmpty) throw AiException(notConfiguredReason());
    if (documents.isNotEmpty) {
      order = order.where((p) => p == 'claude' || p == 'claude_code').toList();
      if (order.isEmpty) {
        throw const AiException('PDF читает только Claude (подписка на ПК или '
            'API-ключ) — выберите его в Настройках или вставьте текст.');
      }
    }
    final claudeModel =
        tier == 'fast' ? _config.fastModel : _config.anthropicModel;

    AiException? lastError;
    for (final provider in order) {
      final sw = Stopwatch()..start();
      try {
        final r = switch (provider) {
          'claude_code' => await _claudeCode!.complete(
              system: system,
              user: user,
              model: claudeModel,
              webTools: webSearch,
              documents: documents,
              effort: effort,
              jsonSchema: jsonSchema,
              timeout: timeout,
            ),
          'claude' => await _anthropic(system, user, maxTokens, effort,
              jsonSchema, timeout,
              model: claudeModel, webSearch: webSearch, documents: documents),
          'pc_relay' => await _relay(RelayRequest(
              system: system,
              user: user,
              maxTokens: maxTokens,
              effort: effort,
              jsonSchema: jsonSchema,
              feature: feature,
              timeout: timeout,
              tier: tier,
              web: webSearch,
            )),
          'custom' => await _openAiCompatible(
              baseUrl: _config.customApiBaseUrl,
              apiKey: _config.customApiKey,
              model: _config.customModel,
              label: _customLabel,
              provider: 'custom',
              system: system,
              user: user,
              maxTokens: maxTokens,
              jsonSchema: jsonSchema,
              timeout: timeout,
            ),
          _ => await _openAiCompatible(
              baseUrl: 'https://api.openai.com/v1',
              apiKey: _config.openaiApiKey,
              model: _config.openaiModel,
              label: 'ChatGPT',
              provider: 'chatgpt',
              system: system,
              user: user,
              maxTokens: maxTokens,
              jsonSchema: jsonSchema,
              timeout: timeout,
            ),
        };
        await _log(feature, r, ok: true);
        return r;
      } on AiException catch (e) {
        lastError = e;
        await _logFailure(feature, provider, e, sw.elapsedMilliseconds);
      } catch (e) {
        lastError = AiException('Ошибка ИИ: $e', detail: e.toString());
        await _logFailure(feature, provider, lastError, sw.elapsedMilliseconds);
      }
    }
    throw lastError!;
  }

  Future<void> _log(String feature, AiResult r, {required bool ok}) async {
    try {
      await _usageLog?.logAiUsage(
        feature: feature,
        provider: r.provider,
        model: r.model,
        inputTokens: r.inputTokens,
        outputTokens: r.outputTokens,
        costUsd: r.costUsd,
        durationMs: r.durationMs,
        ok: ok,
      );
    } catch (_) {/* logging must never break a feature */}
  }

  Future<void> _logFailure(
      String feature, String provider, AiException e, int ms) async {
    try {
      await _usageLog?.logAiUsage(
        feature: feature,
        provider: provider,
        model: provider.startsWith('claude') ? _config.anthropicModel : '',
        durationMs: ms,
        ok: false,
        error: e.detail ?? e.message,
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────── Anthropic API

  Future<AiResult> _anthropic(
    String system,
    String user,
    int maxTokens,
    String effort,
    Map<String, dynamic>? jsonSchema,
    Duration timeout, {
    required String model,
    bool webSearch = false,
    List<AiDocument> documents = const [],
  }) async {
    var budget = maxTokens;
    final sw = Stopwatch()..start();
    // Web search runs a server-side loop; a long one comes back as
    // "pause_turn" and is resumed by sending the turn back unchanged.
    // Documents go before the text of the request.
    final Object userContent = documents.isEmpty
        ? user
        : [
            for (final d in documents)
              {
                'type': 'document',
                'source': {
                  'type': 'base64',
                  'media_type': d.mediaType,
                  'data': base64Encode(d.bytes),
                },
              },
            {'type': 'text', 'text': user},
          ];
    final messages = <Map<String, Object?>>[
      {'role': 'user', 'content': userContent},
    ];
    final tools = webSearch
        ? [
            {
              'type': webSearchToolType(model),
              'name': 'web_search',
              'max_uses': 5,
            }
          ]
        : const <Map<String, Object>>[];
    final collected = <Map<String, Object?>>[];
    var continuations = 0;
    var inTotal = 0, outTotal = 0;

    for (var attempt = 0;; attempt++) {
      final outputConfig = <String, dynamic>{
        if (claudeSupportsEffort(model)) 'effort': effort,
        if (jsonSchema != null)
          'format': {'type': 'json_schema', 'schema': jsonSchema},
      };
      final http.Response resp;
      try {
        resp = await _http
            .post(
              Uri.parse('$_anthropicBase/v1/messages'),
              headers: {
                'content-type': 'application/json',
                'x-api-key': _config.anthropicApiKey.trim(),
                'anthropic-version': '2023-06-01',
              },
              body: jsonEncode({
                'model': model,
                'max_tokens': budget,
                'system': system,
                // `thinking` omitted on purpose: Opus/Sonnet 5 think
                // adaptively by default; effort controls depth and cost.
                if (outputConfig.isNotEmpty) 'output_config': outputConfig,
                if (tools.isNotEmpty) 'tools': tools,
                'messages': messages,
              }),
            )
            .timeout(timeout);
      } on TimeoutException {
        throw AiException(
            'Claude не ответил за ${timeout.inSeconds} с. Попробуйте ещё раз.',
            retryable: true);
      }

      if (resp.statusCode != 200) {
        final err = _mapAnthropicError(resp);
        if (err.retryable && attempt < 2) {
          await Future<void>.delayed(_retryDelay(resp, attempt));
          continue;
        }
        throw err;
      }

      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final stop = data['stop_reason']?.toString() ?? '';
      // Safety classifiers decline with HTTP 200 + stop_reason "refusal".
      if (stop == 'refusal') {
        throw const AiException('Claude отказался отвечать на этот запрос.');
      }
      final content = [
        for (final b in (data['content'] as List? ?? const []))
          if (b is Map) b.cast<String, Object?>(),
      ];
      final u0 = (data['usage'] as Map?) ?? const {};
      inTotal += (u0['input_tokens'] as num?)?.toInt() ?? 0;
      outTotal += (u0['output_tokens'] as num?)?.toInt() ?? 0;
      if (stop == 'pause_turn' && continuations < 3) {
        continuations++;
        collected.addAll(content);
        messages
          ..clear()
          ..add({'role': 'user', 'content': userContent})
          ..add({'role': 'assistant', 'content': [...collected]});
        continue;
      }
      collected.addAll(content);
      final buf = StringBuffer();
      for (final block in content) {
        // Thinking blocks come back with empty text by default — skip them.
        if (block['type'] == 'text') buf.write(block['text']);
      }
      final text = buf.toString().trim();

      if (stop == 'max_tokens') {
        // Thinking + answer ran into the cap: one retry with a bigger cap.
        if (budget < 32000 && attempt < 2) {
          budget = (budget * 2).clamp(0, 32000);
          continue;
        }
        throw AiException(
            'Ответ Claude обрезан по лимиту длины — попробуйте ещё раз.',
            detail: text);
      }
      if (text.isEmpty) throw const AiException('Claude вернул пустой ответ');

      final inTok = inTotal;
      final outTok = outTotal;
      final searches = collected
          .where((b) => b['type'] == 'server_tool_use' && b['name'] == 'web_search')
          .length;
      final r = AiResult(
        text: text,
        backend: 'Claude ${claudeModelLabel(model)} · API',
        provider: 'claude',
        model: data['model']?.toString() ?? model,
        stopReason: stop,
        inputTokens: inTok,
        outputTokens: outTok,
        // $10 per 1,000 searches on top of the tokens.
        costUsd: estimateClaudeCost(model, inTok, outTok) + searches * 0.01,
        durationMs: sw.elapsedMilliseconds,
        sources: webSearch ? webSourcesOf(collected) : const [],
        searchedWeb: webSearch,
      );
      return jsonSchema == null ? r : r.withJson(extractJsonObject(text));
    }
  }

  /// The web search tool version a model supports: the dynamic-filtering
  /// variant on Opus/Sonnet 4.6 and later, the basic one on Haiku.
  static String webSearchToolType(String model) =>
      model.contains('haiku') ? 'web_search_20250305' : 'web_search_20260209';

  /// Pages an answer relied on: cited ones first, then the other results.
  static List<WebSource> webSourcesOf(List<Map<String, Object?>> content) {
    final out = <WebSource>[];
    final seen = <String>{};
    void add(Object? title, Object? url) {
      final u = (url ?? '').toString();
      if (u.isEmpty || !seen.add(u)) return;
      out.add(WebSource((title ?? '').toString(), u));
    }

    for (final b in content) {
      if (b['type'] != 'text') continue;
      for (final c in (b['citations'] is List ? b['citations'] as List : const [])) {
        if (c is Map) add(c['title'], c['url']);
      }
    }
    for (final b in content) {
      if (b['type'] != 'web_search_tool_result') continue;
      // A failed search carries one error object instead of a list.
      final results = b['content'];
      if (results is! List) continue;
      for (final r in results) {
        if (r is Map && r['type'] == 'web_search_result') add(r['title'], r['url']);
      }
    }
    return out;
  }

  static Duration _retryDelay(http.Response resp, int attempt) {
    final ra = int.tryParse(resp.headers['retry-after'] ?? '');
    if (ra != null && ra >= 0 && ra <= 60) return Duration(seconds: ra);
    return Duration(seconds: attempt == 0 ? 2 : 6);
  }

  /// HTTP error → message the user can act on. Never shows raw JSON.
  static AiException _mapAnthropicError(http.Response resp) {
    final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
    String apiMsg = '';
    String apiType = '';
    try {
      final e = (jsonDecode(body) as Map)['error'] as Map?;
      apiMsg = e?['message']?.toString() ?? '';
      apiType = e?['type']?.toString() ?? '';
    } catch (_) {}
    final lower = apiMsg.toLowerCase();
    switch (resp.statusCode) {
      case 401:
        return AiException(
            'Ключ Claude не принят. Нужен API-ключ вида sk-ant-api03-… из '
            'console.anthropic.com → API Keys. Подписка Claude Pro/Max сюда '
            'не подходит — для неё выберите «Claude · подписка».',
            detail: body);
      case 400 when lower.contains('credit balance'):
      case 402:
        return AiException(
            'На API-счёте Anthropic нет денег: console.anthropic.com → '
            'Billing. Подписка claude.ai не оплачивает API — на компьютере '
            'можно выбрать «Claude · подписка».',
            detail: body);
      case 403:
        return AiException('У ключа нет доступа к этой модели или '
            'рабочему пространству.', detail: body);
      case 404:
        return AiException('Модель недоступна для этого ключа — выберите '
            'другую модель Claude.', detail: body);
      case 429:
        return AiException('Слишком много запросов к Claude — повторяю…',
            detail: body, retryable: true);
      case 529:
        return AiException('Claude перегружен — повторяю…',
            detail: body, retryable: true);
    }
    if (resp.statusCode >= 500) {
      return AiException('Сбой на стороне Claude (${resp.statusCode}).',
          detail: body, retryable: true);
    }
    return AiException(
        'Claude вернул ошибку ${resp.statusCode}'
        '${apiType.isNotEmpty ? ' ($apiType)' : ''}'
        '${apiMsg.isNotEmpty ? ': $apiMsg' : ''}',
        detail: body);
  }

  // ─────────────────────────────────────────── Claude через компьютер

  /// "192.168.1.23", "192.168.1.23:8765", "http://pc.tail1234.ts.net:8765"
  /// → a base URL (port 8765 unless given).
  static String relayBaseUrl(String address) {
    var a = address.trim().replaceAll(RegExp(r'/+$'), '');
    if (!a.contains('://')) a = 'http://$a';
    final u = Uri.tryParse(a);
    if (u == null || u.host.isEmpty) return a;
    return u.hasPort ? '${u.scheme}://${u.host}:${u.port}'
        : '${u.scheme}://${u.host}:8765';
  }

  /// The phone's request answered by the PC's own Claude (see
  /// RelayServer): the subscription, no key on the phone.
  Future<AiResult> _relay(RelayRequest req) async {
    final base = relayBaseUrl(_config.relayUrl);
    final http.Response resp;
    try {
      resp = await _http
          .post(
            Uri.parse('$base/v1/complete'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer ${_config.relayClientCode.trim()}',
            },
            body: jsonEncode(req.toJson()),
          )
          // The PC's Claude has its own timeout; allow for the network.
          .timeout(req.timeout + const Duration(seconds: 30));
    } on TimeoutException {
      throw AiException(
          'Компьютер не ответил за ${req.timeout.inSeconds + 30} с.',
          retryable: true);
    } catch (e) {
      throw AiException(
          'Компьютер ($base) не отвечает. Проверьте: LinguaTrace запущен на '
          'ПК, там включено «Claude для телефона», телефон и ПК в одной сети '
          'Wi‑Fi (или оба в Tailscale).',
          detail: '$e',
          retryable: true);
    }
    Map<String, dynamic> body;
    try {
      body = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      body = const {};
    }
    final err = (body['error'] ?? '').toString();
    switch (resp.statusCode) {
      case 200:
        break;
      case 401:
        throw const AiException(
            'Код подключения не подошёл. Возьмите его на ПК: Настройки → '
            'ИИ-помощник → «Claude для телефона».');
      case 429:
        throw AiException(err.isNotEmpty ? err : 'Компьютер просит подождать.',
            retryable: true);
      default:
        throw AiException(
            err.isNotEmpty ? 'Компьютер: $err' : 'Компьютер вернул ошибку '
                '${resp.statusCode}.',
            detail: utf8.decode(resp.bodyBytes, allowMalformed: true),
            retryable: body['retryable'] == true);
    }
    final text = (body['text'] ?? '').toString();
    if (text.trim().isEmpty) throw const AiException('Компьютер вернул пустой ответ');
    final r = AiResult(
      text: text,
      json: body['json'] is Map
          ? (body['json'] as Map).cast<String, dynamic>()
          : null,
      backend: '${body['backend'] ?? 'Claude'} · через компьютер',
      // The provider and model that really answered on the PC: trust rules
      // (e.g. corrections are recorded only from strong models) follow them.
      provider: (body['provider'] ?? 'pc_relay').toString(),
      model: (body['model'] ?? '').toString(),
      stopReason: (body['stop_reason'] ?? '').toString(),
      inputTokens: (body['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (body['output_tokens'] as num?)?.toInt() ?? 0,
      durationMs: (body['duration_ms'] as num?)?.toInt() ?? 0,
      localEndpoint: body['local_endpoint'] == true,
      sources: [
        for (final s in (body['sources'] is List ? body['sources'] as List : const []))
          if (s is Map) WebSource.fromJson(s.cast<String, dynamic>()),
      ],
      searchedWeb: body['searched_web'] == true,
    );
    return req.jsonSchema != null && r.json == null
        ? r.withJson(extractJsonObject(text))
        : r;
  }

  // ─────────────────────────────────────────── OpenAI-compatible

  /// One path for OpenAI and every compatible service: Gemini free tier,
  /// Groq, OpenRouter, LM Studio, llama.cpp server.
  Future<AiResult> _openAiCompatible({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String label,
    required String provider,
    required String system,
    required String user,
    required int maxTokens,
    Map<String, dynamic>? jsonSchema,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    final sys = jsonSchema == null
        ? system
        : '$system\n\nReturn ONLY one JSON object matching this JSON Schema, '
            'no prose, no code fences:\n${jsonEncode(jsonSchema)}';
    final http.Response resp;
    try {
      resp = await _http
          .post(
            Uri.parse(_chatCompletionsUrl(baseUrl)),
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'system', 'content': sys},
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiException('$label не ответил за ${timeout.inSeconds} с.',
          retryable: true);
    }

    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final hint = switch (resp.statusCode) {
        401 || 403 => 'ключ не принят',
        404 => 'неверный адрес или модель',
        429 => 'превышен лимит бесплатного тарифа',
        _ => 'ошибка ${resp.statusCode}',
      };
      throw AiException('$label: $hint', detail: body);
    }
    final data =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final text = ((data['choices'] as List?)?.first?['message']?['content']
                as String?)
            ?.trim() ??
        '';
    if (text.isEmpty) throw AiException('$label вернул пустой ответ');
    final usage = (data['usage'] as Map?) ?? const {};
    final r = AiResult(
      text: text,
      backend: label,
      provider: provider,
      model: model,
      stopReason: (data['choices'] as List?)?.first?['finish_reason']
              ?.toString() ??
          '',
      inputTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
      durationMs: sw.elapsedMilliseconds,
      localEndpoint: isLocalUrl(baseUrl),
    );
    return jsonSchema == null ? r : r.withJson(extractJsonObject(text));
  }

  /// Accept whatever the user pasted: a bare base URL, one with a trailing
  /// slash, or the full `.../chat/completions` endpoint.
  String _chatCompletionsUrl(String baseUrl) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }
}
