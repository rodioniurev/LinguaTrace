/// «Claude для телефона»: the PC's relay answers the phone with its own
/// Claude; the pairing code is required and wrong codes are throttled.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/ai_types.dart';
import 'package:lingua_trace/services/relay_server.dart';

void main() {
  late RelayServer server;
  final seen = <RelayRequest>[];

  setUp(() async {
    seen.clear();
    server = RelayServer((req) async {
      seen.add(req);
      if (req.user == 'fail') {
        throw const AiException('Исчерпан лимит подписки Claude.');
      }
      return AiResult(
        text: req.jsonSchema != null ? '{"ok": true}' : 'Hola desde el PC',
        json: req.jsonSchema != null ? const {'ok': true} : null,
        backend: 'Claude Sonnet 5 · подписка',
        provider: 'claude_code',
        model: 'claude-sonnet-5',
        durationMs: 1200,
      );
    }, token: 'abcde-fghjk', port: 0);
    await server.start();
  });
  tearDown(() => server.stop());

  AiClient phone({String code = 'ABCDE fghjk'}) {
    final cfg = ConfigService()
      ..aiProvider = 'pc_relay'
      ..relayUrl = '127.0.0.1:${server.boundPort}'
      ..relayClientCode = code;
    return AiClient(cfg);
  }

  test('the phone gets the PC Claude answer, with provenance', () async {
    final r = await phone().completeResult(
        system: 'sys', user: 'hola', tier: 'fast', feature: 'correction');
    expect(r.text, 'Hola desde el PC');
    expect(r.backend, 'Claude Sonnet 5 · подписка · через компьютер');
    expect(r.provider, 'claude_code',
        reason: 'trust rules follow the model that really answered');
    expect(seen.single.tier, 'fast');
    expect(seen.single.feature, 'correction');
  });

  test('structured output survives the trip', () async {
    final r = await phone().completeResult(
        system: 's', user: 'u', jsonSchema: const {'type': 'object'});
    expect(r.json, {'ok': true});
    expect(seen.single.jsonSchema, {'type': 'object'});
  });

  test('a wrong code is refused with a clear message', () async {
    await expectLater(
        phone(code: 'wrong-code1').completeResult(system: 's', user: 'u'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('Код подключения'))));
    expect(seen, isEmpty);
  });

  test("the PC's own error reaches the phone", () async {
    await expectLater(
        phone().completeResult(system: 's', user: 'fail'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('Исчерпан лимит'))));
  });

  test('guessing codes gets throttled', () async {
    for (var i = 0; i < 10; i++) {
      try {
        await phone(code: 'wrong-${i}0000').completeResult(system: 's', user: 'u');
      } catch (_) {}
    }
    await expectLater(
        phone().completeResult(system: 's', user: 'u'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('подождите'))));
  });

  test('a PC that is off is explained, not a stack trace', () async {
    await server.stop();
    await expectLater(
        phone().completeResult(system: 's', user: 'u'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('не отвечает'))));
  });

  test('addresses: a bare IP gets the default port', () {
    expect(AiClient.relayBaseUrl('192.168.1.23'), 'http://192.168.1.23:8765');
    expect(AiClient.relayBaseUrl('192.168.1.23:9000/'), 'http://192.168.1.23:9000');
    expect(AiClient.relayBaseUrl('http://pc.tail.ts.net:8765'),
        'http://pc.tail.ts.net:8765');
    expect(RelayServer.normalizeCode(' ABCDE-fghjk '), 'abcdefghjk');
    expect(RelayServer.newCode(), matches(RegExp(r'^[a-z2-9]{5}-[a-z2-9]{5}$')));
  });
}
