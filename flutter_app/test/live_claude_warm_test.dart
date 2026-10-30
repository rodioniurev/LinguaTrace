/// Real Claude Code, warm mode: the second request must be answered in a
/// few seconds. Skipped unless LT_LIVE=1 (it uses the subscription).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/services/claude_code_client.dart';

void main() {
  final live = Platform.environment['LT_LIVE'] == '1';
  test('warm Claude Code: first vs second request', () async {
    final tmp = Directory.systemTemp.createTempSync('lt_live_warm');
    final c = ClaudeCodeClient(
        pathOverride: () => '', workDir: () => tmp.path, warm: () => true);
    final sw = Stopwatch()..start();
    final a = await c.complete(
        system: 'Answer with exactly one word.',
        user: '¿Cómo se dice «дом» en español?',
        model: 'claude-sonnet-5',
        effort: 'low');
    final first = sw.elapsedMilliseconds;
    sw.reset();
    final b = await c.complete(
        system: 'Return JSON only.',
        user: 'Translate «привнести в проект» to Spanish.',
        model: 'claude-sonnet-5',
        effort: 'low',
        jsonSchema: {
          'type': 'object',
          'additionalProperties': false,
          'required': ['es'],
          'properties': {'es': {'type': 'string'}},
        });
    final second = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('first ${first}ms: ${a.text} | second ${second}ms: ${b.json}');
    expect(b.json?['es'], isNotNull);
    expect(second, lessThan(first));
    c.shutdownWarm();
    // The process leaves its working folder a moment after stdin closes.
    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }, skip: live ? false : 'LT_LIVE=1 to run against the real CLI',
      timeout: const Timeout(Duration(minutes: 4)));
}
