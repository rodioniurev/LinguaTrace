/// Exercises the LLM backends against a local stub server: the
/// OpenAI-compatible client (used for OpenAI, Gemini, Groq, OpenRouter,
/// LM Studio) and the Ollama path of the free-first router.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/ai_types.dart';
import 'package:lingua_trace/services/llm_router.dart';

Future<HttpServer> _stub(
  Object Function(HttpRequest req) reply, {
  void Function(HttpRequest req)? onRequest,
  void Function(Map<String, dynamic> body)? onBody,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    onRequest?.call(req);
    if (onBody != null && req.method == 'POST') {
      final raw = await utf8.decoder.bind(req).join();
      onBody(jsonDecode(raw) as Map<String, dynamic>);
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(reply(req)));
    await req.response.close();
  });
  return server;
}

void main() {
  group('OpenAI-compatible provider', () {
    test('posts to <base>/chat/completions and reads the reply', () async {
      String? seenPath;
      String? seenAuth;
      final server = await _stub(
        (_) => {
          'choices': [
            {
              'message': {'content': 'культурный контекст'}
            }
          ]
        },
        onRequest: (req) {
          seenPath = req.uri.path;
          seenAuth = req.headers.value('authorization');
        },
      );

      final cfg = ConfigService()
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${server.port}/v1'
        ..customModel = 'gemini-2.0-flash'
        ..customApiKey = 'free-key';

      final out = await AiClient(cfg).complete(system: 's', user: 'u');

      expect(out, 'культурный контекст');
      expect(seenPath, '/v1/chat/completions');
      expect(seenAuth, 'Bearer free-key');
      await server.close();
    });

    test('accepts a base URL that already ends in /chat/completions',
        () async {
      String? seenPath;
      final server = await _stub(
        (_) => {
          'choices': [
            {
              'message': {'content': 'ok'}
            }
          ]
        },
        onRequest: (req) => seenPath = req.uri.path,
      );

      final cfg = ConfigService()
        ..aiProvider = 'custom'
        ..customApiBaseUrl =
            'http://127.0.0.1:${server.port}/v1/chat/completions'
        ..customModel = 'local-model';

      await AiClient(cfg).complete(system: 's', user: 'u');
      expect(seenPath, '/v1/chat/completions');
      await server.close();
    });

    test('a local server needs no key — no Authorization header sent',
        () async {
      String? seenAuth = 'unset';
      final server = await _stub(
        (_) => {
          'choices': [
            {
              'message': {'content': 'ok'}
            }
          ]
        },
        onRequest: (req) => seenAuth = req.headers.value('authorization'),
      );

      final cfg = ConfigService()
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${server.port}/v1'
        ..customModel = 'local-model';

      await AiClient(cfg).complete(system: 's', user: 'u');
      expect(seenAuth, isNull);
      await server.close();
    });
  });

  group('strict provider selection', () {
    test('picking Claude without its key never falls back to ChatGPT', () {
      final cfg = ConfigService()
        ..aiProvider = 'claude'
        ..openaiApiKey = 'sk-configured';

      expect(AiClient(cfg).isConfigured, isFalse);
      expect(
        () => AiClient(cfg).complete(system: 's', user: 'u'),
        throwsA(predicate((e) => e.toString().contains('Claude'))),
      );
    });

    test('auto uses whatever is configured', () {
      final cfg = ConfigService()
        ..aiProvider = 'auto'
        ..openaiApiKey = 'sk-configured';
      expect(AiClient(cfg).isConfigured, isTrue);
      expect(AiClient(cfg).providerName, 'ChatGPT');
    });
  });

  group('free-first router', () {
    test('uses Ollama when enabled, with no cloud key present', () async {
      String? seenPath;
      Map<String, dynamic>? body;
      final server = await _stub(
        (req) => req.uri.path == '/api/tags'
            ? {
                'models': [
                  {'name': 'qwen2.5:3b'}
                ]
              }
            : {
                'message': {'content': 'ответ от Ollama'}
              },
        onRequest: (req) {
          if (req.uri.path != '/api/tags') seenPath = req.uri.path;
        },
        onBody: (b) => body = b,
      );
      final cfg = ConfigService()
        // Trailing slash must not produce a double slash in the URL.
        ..ollamaEnabled = true
        ..ollamaUrl = 'http://127.0.0.1:${server.port}/'
        ..ollamaModel = 'qwen2.5:3b';

      final router = LlmRouter(cfg);
      expect(router.isAvailable, isTrue);
      expect(router.backendName, 'Ollama/qwen2.5:3b');

      final out = await router.complete(system: 's', user: 'u');
      expect(out, 'ответ от Ollama');
      expect(seenPath, '/api/chat');
      expect(body!['model'], 'qwen2.5:3b');
      expect(body!['stream'], isFalse);
      expect((body!['messages'] as List).first['role'], 'system');
      await server.close();
    });

    test('a model that was never pulled fails fast with the pull command',
        () async {
      final server = await _stub((req) => req.uri.path == '/api/tags'
          ? {'models': <Object>[]}
          : {
              'message': {'content': ''}
            });
      final cfg = ConfigService()
        ..ollamaEnabled = true
        ..ollamaUrl = 'http://127.0.0.1:${server.port}'
        ..ollamaModel = 'qwen2.5:3b';

      await expectLater(
        LlmRouter(cfg).complete(system: 's', user: 'u'),
        throwsA(predicate((e) => e.toString().contains('ollama pull'))),
      );
      await server.close();
    });

    test('falls through Ollama to the cloud when Ollama is down', () async {
      final cloud = await _stub((_) => {
            'choices': [
              {
                'message': {'content': 'из облака'}
              }
            ]
          });
      final cfg = ConfigService()
        ..ollamaEnabled = true
        // Nothing listening here — the router must move on, not give up.
        ..ollamaUrl = 'http://127.0.0.1:1'
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${cloud.port}/v1'
        ..customModel = 'gemini-2.0-flash';

      final out = await LlmRouter(cfg, ai: AiClient(cfg))
          .complete(system: 's', user: 'u');
      expect(out, 'из облака');
      await cloud.close();
    });

    test('a configured cloud answers FIRST even when Ollama works', () async {
      var ollamaCalls = 0;
      final ollama = await _stub((req) {
        if (req.uri.path == '/api/chat') ollamaCalls++;
        return req.uri.path == '/api/tags'
            ? {
                'models': [
                  {'name': 'qwen2.5:3b'}
                ]
              }
            : {
                'message': {'content': 'local'}
              };
      });
      final cloud = await _stub((_) => {
            'choices': [
              {
                'message': {'content': 'из облака'}
              }
            ]
          });
      final cfg = ConfigService()
        ..ollamaEnabled = true
        ..ollamaUrl = 'http://127.0.0.1:${ollama.port}'
        ..ollamaModel = 'qwen2.5:3b'
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${cloud.port}/v1'
        ..customModel = 'gemini-2.0-flash';

      final r = await LlmRouter(cfg, ai: AiClient(cfg))
          .completeResult(system: 's', user: 'u');
      expect(r.text, 'из облака');
      expect(r.provider, 'custom');
      expect(ollamaCalls, 0, reason: 'local backends are only a fallback');
      await ollama.close();
      await cloud.close();
    });

    test('offline mode puts local backends first', () async {
      final ollama = await _stub((req) => req.uri.path == '/api/tags'
          ? {
              'models': [
                {'name': 'qwen2.5:3b'}
              ]
            }
          : {
              'message': {'content': 'local'}
            });
      final cfg = ConfigService()
        ..offlineMode = true
        ..ollamaEnabled = true
        ..ollamaUrl = 'http://127.0.0.1:${ollama.port}'
        ..ollamaModel = 'qwen2.5:3b'
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:1/v1'
        ..customModel = 'x';
      final r = await LlmRouter(cfg, ai: AiClient(cfg))
          .completeResult(system: 's', user: 'u');
      expect(r.provider, 'ollama');
      expect(r.backend, 'Ollama/qwen2.5:3b');
      await ollama.close();
    });

    test("the chosen provider's error is shown, fallbacks only appended",
        () async {
      final ollama = await _stub((req) => req.uri.path == '/api/tags'
          ? {'models': <Object>[]}
          : {'message': {'content': ''}});
      final cfg = ConfigService()
        ..ollamaEnabled = true
        ..ollamaUrl = 'http://127.0.0.1:${ollama.port}'
        ..ollamaModel = 'qwen2.5:7b'
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:1/v1' // nothing listening
        ..customModel = 'gemini-2.0-flash';
      try {
        await LlmRouter(cfg, ai: AiClient(cfg))
            .completeResult(system: 's', user: 'u');
        fail('should throw');
      } catch (e) {
        final msg = e.toString();
        expect(msg.startsWith('Ошибка ИИ') || msg.contains('gemini'), isTrue,
            reason: 'primary error first: $msg');
        expect(msg, contains('Запасные варианты'));
        expect(msg, contains('ollama pull qwen2.5:7b'));
      }
      await ollama.close();
    });

    test('the connection test tries the chosen provider only', () async {
      var ollamaCalls = 0;
      final ollama = await _stub((req) {
        ollamaCalls++;
        return req.uri.path == '/api/tags'
            ? {
                'models': [
                  {'name': 'qwen2.5:7b'}
                ]
              }
            : {
                'message': {'content': 'ok'}
              };
      });
      final cfg = ConfigService()
        ..ollamaEnabled = true
        ..ollamaUrl = 'http://127.0.0.1:${ollama.port}'
        ..ollamaModel = 'qwen2.5:7b'
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:1/v1' // nothing listening
        ..customModel = 'gemini-2.0-flash';
      await expectLater(
          LlmRouter(cfg, ai: AiClient(cfg))
              .completeResult(system: 's', user: 'u', fallback: false),
          throwsA(isA<AiException>().having(
              (e) => e.message, 'message', isNot(contains('Запасные')))));
      expect(ollamaCalls, 0, reason: 'no minutes-long wait on a fallback');
      await ollama.close();
    });

    test('with nothing configured the error points at the free options', () {
      final router = LlmRouter(ConfigService());
      expect(router.isAvailable, isFalse);
      expect(
        () => router.complete(system: 's', user: 'u'),
        throwsA(predicate((e) => e.toString().contains('Ollama'))),
      );
    });
  });
}
