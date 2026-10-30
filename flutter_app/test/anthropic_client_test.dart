/// The Claude API path against a local stub of POST /v1/messages: request
/// shape, thinking blocks, truncation retry, error mapping, structured
/// output, usage. Before this file the Anthropic path had no test at all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/ai_types.dart';

class _Stub {
  final HttpServer server;
  final requests = <Map<String, dynamic>>[];
  final headers = <HttpHeaders>[];
  _Stub(this.server);
  String get base => 'http://127.0.0.1:${server.port}';
  Future<void> close() => server.close(force: true);
}

/// [replies] are served in order: (status, body, extraHeaders).
Future<_Stub> _stub(List<(int, Object, Map<String, String>)> replies) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final s = _Stub(server);
  var i = 0;
  server.listen((req) async {
    s.headers.add(req.headers);
    s.requests.add(jsonDecode(await utf8.decoder.bind(req).join())
        as Map<String, dynamic>);
    final (status, body, extra) = replies[i < replies.length ? i : replies.length - 1];
    i++;
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    extra.forEach(req.response.headers.set);
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
  return s;
}

Map<String, dynamic> _ok(String text,
        {String stop = 'end_turn', bool withThinking = true}) =>
    {
      'model': 'claude-opus-5',
      'stop_reason': stop,
      'content': [
        if (withThinking) {'type': 'thinking', 'thinking': ''},
        {'type': 'text', 'text': text},
      ],
      'usage': {'input_tokens': 1000, 'output_tokens': 200},
    };

ConfigService _cfg({String model = 'claude-opus-5'}) => ConfigService()
  ..aiProvider = 'claude'
  ..anthropicApiKey = ' sk-ant-api03-test '
  ..anthropicModel = model;

void main() {
  test('request shape: headers, model, effort, no thinking param', () async {
    final s = await _stub([(200, _ok('hola'), const {})]);
    final ai = AiClient(_cfg(), anthropicBaseUrl: s.base);

    final r = await ai.completeResult(
        system: 'sys', user: 'u', effort: 'low', maxTokens: 8000);

    expect(r.text, 'hola', reason: 'thinking blocks are skipped');
    expect(r.backend, 'Claude Opus 5 · API');
    expect(s.headers.single.value('x-api-key'), 'sk-ant-api03-test',
        reason: 'key is trimmed');
    expect(s.headers.single.value('anthropic-version'), '2023-06-01');
    final body = s.requests.single;
    expect(body['model'], 'claude-opus-5');
    expect(body['max_tokens'], 8000);
    expect(body['output_config'], {'effort': 'low'});
    expect(body.containsKey('thinking'), isFalse);
    expect(r.costUsd, closeTo(1000 / 1e6 * 5 + 200 / 1e6 * 25, 1e-9));
    await s.close();
  });

  test('Haiku 4.5 gets no effort (it would 400)', () async {
    final s = await _stub([(200, _ok('ok'), const {})]);
    await AiClient(_cfg(model: 'claude-haiku-4-5'), anthropicBaseUrl: s.base)
        .complete(system: 's', user: 'u');
    expect(s.requests.single.containsKey('output_config'), isFalse);
    await s.close();
  });

  test('Haiku 5.5 takes effort, and its price is its own', () async {
    final s = await _stub([(200, _ok('ok'), const {})]);
    final r = await AiClient(_cfg(model: 'claude-haiku-5-5'), anthropicBaseUrl: s.base)
        .completeResult(system: 's', user: 'u', effort: 'low');
    expect(s.requests.single['output_config'], {'effort': 'low'});
    expect(r.backend, 'Claude Haiku 5.5 · API');
    expect(r.costUsd, lessThan(0.001));
    await s.close();
  });

  test('stop_reason max_tokens → one retry with a doubled budget', () async {
    final s = await _stub([
      (200, _ok('обрезано', stop: 'max_tokens'), const {}),
      (200, _ok('целиком'), const {}),
    ]);
    final r = await AiClient(_cfg(), anthropicBaseUrl: s.base)
        .completeResult(system: 's', user: 'u', maxTokens: 4000);
    expect(r.text, 'целиком');
    expect(s.requests.map((b) => b['max_tokens']), [4000, 8000]);
    await s.close();
  });

  test('structured output: schema sent as output_config.format, JSON parsed',
      () async {
    final s = await _stub([(200, _ok('{"a": "b"}'), const {})]);
    final r = await AiClient(_cfg(), anthropicBaseUrl: s.base).completeResult(
      system: 's',
      user: 'u',
      jsonSchema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'string'}
        },
        'required': ['a'],
        'additionalProperties': false,
      },
    );
    expect(s.requests.single['output_config']['format']['type'], 'json_schema');
    expect(r.json, {'a': 'b'});
    await s.close();
  });

  test('401 → message about the key type, never raw JSON', () async {
    final s = await _stub([
      (401, {
        'type': 'error',
        'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'}
      }, const {})
    ]);
    await expectLater(
      AiClient(_cfg(), anthropicBaseUrl: s.base).complete(system: 's', user: 'u'),
      throwsA(isA<AiException>()
          .having((e) => e.message, 'message', contains('sk-ant-api03'))
          .having((e) => e.message, 'message', isNot(contains('{')))),
    );
    await s.close();
  });

  test('400 credit balance → explains that a subscription is not API credit',
      () async {
    final s = await _stub([
      (400, {
        'type': 'error',
        'error': {
          'type': 'invalid_request_error',
          'message': 'Your credit balance is too low to access the Anthropic API.'
        }
      }, const {})
    ]);
    await expectLater(
      AiClient(_cfg(), anthropicBaseUrl: s.base).complete(system: 's', user: 'u'),
      throwsA(isA<AiException>()
          .having((e) => e.message, 'message', contains('Billing'))),
    );
    await s.close();
  });

  test('529 overloaded is retried (honouring retry-after)', () async {
    final s = await _stub([
      (529, {
        'type': 'error',
        'error': {'type': 'overloaded_error', 'message': 'Overloaded'}
      }, const {'retry-after': '0'}),
      (200, _ok('после повтора'), const {}),
    ]);
    final out = await AiClient(_cfg(), anthropicBaseUrl: s.base)
        .complete(system: 's', user: 'u');
    expect(out, 'после повтора');
    expect(s.requests.length, 2);
    await s.close();
  });

  test('refusal is reported, not returned as text', () async {
    final s = await _stub([(200, _ok('', stop: 'refusal'), const {})]);
    await expectLater(
      AiClient(_cfg(), anthropicBaseUrl: s.base).complete(system: 's', user: 'u'),
      throwsA(isA<AiException>()
          .having((e) => e.message, 'message', contains('отказался'))),
    );
    await s.close();
  });
}
