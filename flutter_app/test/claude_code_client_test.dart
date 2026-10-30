/// Claude via the subscription (headless Claude Code) with a fake process:
/// argument shape, stdin prompt, JSON parsing, error mapping, environment.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/services/ai_types.dart';
import 'package:lingua_trace/services/claude_code_client.dart';

class _FakeProcess implements Process {
  final String out;
  final int code = 0;
  final stdinCtrl = StreamController<List<int>>();
  late final IOSink _stdin = IOSink(stdinCtrl.sink);
  _FakeProcess(this.out);

  @override
  Stream<List<int>> get stdout => Stream.value(utf8.encode(out));
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => _stdin;
  @override
  Future<int> get exitCode async => code;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  late Directory tmp;
  late File fakeExe;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lt_cc');
    fakeExe = File('${tmp.path}/claude.exe')..writeAsStringSync('');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ClaudeCodeClient client(
    String stdoutJson, {
    void Function(String exe, List<String> args, Map<String, String>? env)? seen,
    void Function(String stdin)? onStdin,
  }) =>
      ClaudeCodeClient(
        pathOverride: () => fakeExe.path,
        workDir: () => '${tmp.path}/cwd',
        start: (exe, args,
            {workingDirectory, environment, includeParentEnvironment = true}) async {
          seen?.call(exe, args, environment);
          final p = _FakeProcess(stdoutJson);
          p.stdinCtrl.stream
              .transform(utf8.decoder)
              .join()
              .then((s) => onStdin?.call(s));
          return p;
        },
      );

  test('pure completion: no tools, no session, safe mode, prompt via stdin',
      () async {
    late List<String> args;
    String? stdin;
    final c = client(
      jsonEncode({
        'type': 'result',
        'is_error': false,
        'result': 'Hola',
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 10, 'output_tokens': 3},
        'modelUsage': {'claude-sonnet-5': {}},
      }),
      seen: (_, a, __) => args = a,
      onStdin: (s) => stdin = s,
    );

    final r = await c.complete(
        system: 'SYSTEM', user: 'traduce: привет', model: 'claude-sonnet-5');

    expect(r.text, 'Hola');
    expect(r.provider, 'claude_code');
    expect(r.backend, 'Claude Sonnet 5 · подписка');
    expect(r.costUsd, 0, reason: 'covered by the subscription');
    expect(args, containsAllInOrder(['-p', '--output-format', 'json']));
    expect(args[args.indexOf('--tools') + 1], '');
    expect(args, contains('--no-session-persistence'));
    expect(args, contains('--safe-mode'));
    expect(args[args.indexOf('--model') + 1], 'claude-sonnet-5');
    expect(args, contains('--system-prompt-file'));
    await Future<void>.delayed(Duration.zero);
    expect(stdin, 'traduce: привет');
  });

  test('structured output is returned as json', () async {
    late List<String> args;
    final c = client(
      jsonEncode({
        'is_error': false,
        'result': '',
        'structured_output': {'corrected': 'no me atrevo a molestar'},
        'usage': {},
      }),
      seen: (_, a, __) => args = a,
    );
    final r = await c.complete(
      system: 's',
      user: 'u',
      model: 'claude-opus-5',
      jsonSchema: {'type': 'object'},
    );
    expect(r.json, {'corrected': 'no me atrevo a molestar'});
    expect(args, contains('--json-schema'));
  });

  test('Haiku gets no --effort flag', () async {
    late List<String> args;
    final c = client(jsonEncode({'is_error': false, 'result': 'ok'}),
        seen: (_, a, __) => args = a);
    await c.complete(system: 's', user: 'u', model: 'claude-haiku-4-5');
    expect(args, isNot(contains('--effort')));
  });

  test('"Not logged in" becomes the sign-in instruction', () async {
    final c = client(jsonEncode({
      'is_error': true,
      'result': 'Not logged in · Please run /login',
    }));
    await expectLater(
      c.complete(system: 's', user: 'u', model: 'claude-opus-5'),
      throwsA(isA<AiException>()
          .having((e) => e.message, 'message', contains('Войти в Claude Code'))
          .having((e) => e.message, 'message', contains('claude auth login'))),
    );
  });

  test('an expired login says so and quotes what the CLI answered', () async {
    final c = client(jsonEncode({
      'is_error': true,
      'result': 'OAuth token has expired. Please obtain a new token or '
          'refresh your existing token.',
    }));
    await expectLater(
      c.complete(system: 's', user: 'u', model: 'claude-opus-5'),
      throwsA(isA<AiException>()
          .having((e) => e.message, 'message', contains('истёк'))
          .having((e) => e.message, 'message',
              contains('OAuth token has expired'))
          .having((e) => e.message, 'message',
              contains('Создать токен подписки'))),
    );
  });

  group('subscription token (claude setup-token)', () {
    ClaudeCodeClient withToken(String token,
            {required Map<String, String> Function(List<String>) answer,
            void Function(Map<String, String>?)? env}) =>
        ClaudeCodeClient(
          pathOverride: () => fakeExe.path,
          workDir: () => '${tmp.path}/cwd',
          oauthToken: () => token,
          start: (exe, args,
              {workingDirectory,
              environment,
              includeParentEnvironment = true}) async {
            env?.call(environment);
            final p = _FakeProcess(answer(args)['out']!);
            p.stdinCtrl.stream.drain<void>(); // stdin is closed by the client
            return p;
          },
        );

    test('the token reaches the CLI; an inherited one never does', () {
      final c = withToken('sk-ant-oat01-mine', answer: (_) => {'out': ''});
      expect(
          c.childEnvironment({
            'PATH': 'x',
            'CLAUDE_CODE_OAUTH_TOKEN': 'sk-ant-oat01-host-session',
          })['CLAUDE_CODE_OAUTH_TOKEN'],
          'sk-ant-oat01-mine');
      final none = withToken('', answer: (_) => {'out': ''});
      expect(
          none
              .childEnvironment({'CLAUDE_CODE_OAUTH_TOKEN': 'host'})
              .containsKey('CLAUDE_CODE_OAUTH_TOKEN'),
          isFalse);
    });

    test('with a token the tile is ready even if the CLI login is gone',
        () async {
      final c = withToken('sk-ant-oat01-mine',
          answer: (a) => {
                'out': a.first == '--version'
                    ? '2.1.283 (Claude Code)'
                    : jsonEncode({'loggedIn': false}),
              });
      final s = await c.status(refresh: true);
      expect(s.ready, isTrue);
      expect(s.tokenConfigured, isTrue);
      expect(s.error, isNull);
    });

    test('an old CLI without auth status is told to update, not "log in"',
        () async {
      final c = withToken('',
          answer: (a) => {
                'out': a.first == '--version'
                    ? '1.0.3 (Claude Code)'
                    : "error: unknown command 'auth'",
              });
      final s = await c.status(refresh: true);
      expect(s.ready, isFalse);
      expect(s.version, '1.0.3 (Claude Code)');
      expect(s.error, contains('claude update'));
      expect(s.error, contains("unknown command 'auth'"));
    });
  });

  test('environment: host-session and API-key variables are stripped', () {
    final env = ClaudeCodeClient.cleanEnvironment({
      'PATH': 'x',
      'ANTHROPIC_API_KEY': 'sk-ant-api03-secret',
      'ANTHROPIC_BASE_URL': 'http://proxy',
      'CLAUDECODE': '1',
      'CLAUDE_CODE_ENTRYPOINT': 'desktop',
      'CLAUDE_CONFIG_DIR': 'keep-me',
    });
    expect(env.keys, containsAll(['PATH', 'CLAUDE_CONFIG_DIR']));
    expect(env.keys, isNot(contains('ANTHROPIC_API_KEY')),
        reason: 'an inherited API key would silently switch billing to the API');
    expect(env.keys, isNot(contains('CLAUDECODE')));
    expect(env.keys, isNot(contains('CLAUDE_CODE_ENTRYPOINT')));
  });

  test('the sign-in console script survives spaces and Cyrillic', () async {
    if (!Platform.isWindows) return;
    final dir = Directory('${tmp.path}/Пользователь с пробелом')
      ..createSync(recursive: true);
    final fake = File('${dir.path}/claude.cmd')
      ..writeAsStringSync('@echo ARGS: %*\r\n');
    final script = File('${tmp.path}/login.cmd')
      ..writeAsStringSync(ClaudeCodeClient.consoleScript(
          fake.path, ['auth', 'login'], ['Вход в Claude Code (подписка)'],
          pause: false));
    final r = await Process.run('cmd.exe', ['/c', script.path],
        stdoutEncoding: utf8);
    final out = r.stdout as String;
    expect(out, contains('Вход в Claude Code (подписка)'));
    expect(out, contains('ARGS: auth login'));
    expect(out, contains('ARGS: auth status --text'),
        reason: 'call returns: the status is shown after the sign-in');
  });

  test('missing executable → install hint, not a crash', () async {
    final c = ClaudeCodeClient(
      pathOverride: () => '${tmp.path}/nope/claude.exe',
      workDir: () => tmp.path,
    );
    expect(c.locate(), isNull);
    await expectLater(
      c.complete(system: 's', user: 'u', model: 'claude-opus-5'),
      throwsA(isA<AiException>()
          .having((e) => e.message, 'message', contains('не найден'))),
    );
  });
}
