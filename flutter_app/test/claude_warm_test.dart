/// Claude Code kept running between requests (stream-json): one process
/// serves consecutive requests, instructions travel inside the message, a
/// broken process falls back to one cold run, auth errors do not.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/services/ai_types.dart';
import 'package:lingua_trace/services/claude_code_client.dart';

/// Emulates `claude -p --input-format stream-json --output-format
/// stream-json`: one `result` event per user message line.
class _StreamProcess implements Process {
  _StreamProcess(this.reply, {this.dieAfter});

  final Map<String, dynamic> Function(String message, int n) reply;
  final int? dieAfter;
  final _in = StreamController<List<int>>();
  final _out = StreamController<List<int>>();
  final _exit = Completer<int>();
  final messages = <String>[];
  late final IOSink _stdin = IOSink(_in.sink);
  var _n = 0;
  bool _started = false;

  void _listen() {
    if (_started) return;
    _started = true;
    _in.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
      final ev = jsonDecode(line) as Map;
      final text = (ev['message'] as Map)['content'] as String;
      messages.add(text);
      _n++;
      if (dieAfter != null && _n > dieAfter!) {
        _out.close();
        if (!_exit.isCompleted) _exit.complete(1);
        return;
      }
      _out.add(utf8.encode('${jsonEncode({'type': 'system', 'subtype': 'x'})}\n'));
      _out.add(utf8.encode('${jsonEncode(reply(text, _n))}\n'));
    }, onDone: () {
      _out.close();
      if (!_exit.isCompleted) _exit.complete(0);
    });
  }

  @override
  Stream<List<int>> get stdout {
    _listen();
    return _out.stream;
  }

  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin {
    _listen();
    return _stdin;
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _out.close();
    if (!_exit.isCompleted) _exit.complete(-1);
    return true;
  }
}

/// A cold `claude -p --output-format json` run.
class _ColdProcess implements Process {
  _ColdProcess(this.out) {
    _in.stream.drain<void>();
  }
  final String out;
  final _in = StreamController<List<int>>();
  late final IOSink _stdin = IOSink(_in.sink);

  @override
  Stream<List<int>> get stdout => Stream.value(utf8.encode(out));
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode async => 0;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

Map<String, dynamic> _ok(String text) => {
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'result': text,
      'usage': {'input_tokens': 500, 'output_tokens': 20},
      'modelUsage': {'claude-sonnet-5': {}},
    };

void main() {
  late Directory tmp;
  late File fakeExe;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lt_warm');
    fakeExe = File('${tmp.path}/claude.exe')..writeAsStringSync('');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ClaudeCodeClient client(List<(List<String>, Process)> started,
          Process Function(List<String> args) make) =>
      ClaudeCodeClient(
        pathOverride: () => fakeExe.path,
        workDir: () => '${tmp.path}/cwd',
        warm: () => true,
        start: (exe, args,
            {workingDirectory,
            environment,
            includeParentEnvironment = true}) async {
          final p = make(args);
          started.add((args, p));
          return p;
        },
      );

  test('one running process answers consecutive requests', () async {
    final started = <(List<String>, Process)>[];
    final c = client(started, (_) => _StreamProcess((m, n) => _ok('ok $n')));
    final a = await c.complete(system: 'Say ok', user: 'ping', model: 'claude-sonnet-5');
    final b = await c.complete(system: 'Say ok', user: 'pong', model: 'claude-sonnet-5');
    expect((a.text, b.text), ('ok 1', 'ok 2'));
    expect(started, hasLength(1), reason: 'the start-up is paid once');
    final args = started.single.$1;
    expect(args, containsAll(['--input-format', 'stream-json', '--safe-mode']));
    final p = started.single.$2 as _StreamProcess;
    expect(p.messages.first, contains('<instructions>\nSay ok'));
    expect(p.messages.first, contains('<input>\nping'));
    c.shutdownWarm();
  });

  test('a schema travels in the message and the JSON is parsed', () async {
    final started = <(List<String>, Process)>[];
    final c = client(
        started, (_) => _StreamProcess((m, n) => _ok('{"answer": "a"}')));
    final r = await c.complete(
        system: 's',
        user: 'u',
        model: 'claude-sonnet-5',
        jsonSchema: {
          'type': 'object',
          'properties': {
            'answer': {'type': 'string'}
          }
        });
    expect(r.json, {'answer': 'a'});
    expect((started.single.$2 as _StreamProcess).messages.single,
        contains('JSON Schema'));
    c.shutdownWarm();
  });

  test('a JSON answer missing a required field is redone cold', () async {
    final started = <(List<String>, Process)>[];
    final c = client(started, (args) {
      if (args.contains('stream-json')) {
        return _StreamProcess((m, n) => _ok('{"why": "wrong key"}'));
      }
      return _ColdProcess(jsonEncode({
        ..._ok('{"why_ru": "ok"}'),
        'structured_output': {'why_ru': 'ok'},
      }));
    });
    final r = await c.complete(
        system: 's',
        user: 'u',
        model: 'claude-sonnet-5',
        jsonSchema: {
          'type': 'object',
          'required': ['why_ru'],
          'properties': {
            'why_ru': {'type': 'string'}
          }
        });
    expect(r.json, {'why_ru': 'ok'});
    expect(started.last.$1, contains('--json-schema'));
    c.shutdownWarm();
  });

  test('a process that dies falls back to one cold run', () async {
    final started = <(List<String>, Process)>[];
    final c = client(started, (args) {
      if (args.contains('stream-json')) {
        return _StreamProcess((m, n) => _ok('never'), dieAfter: 0);
      }
      return _ColdProcess(jsonEncode(_ok('cold ok')));
    });
    final r = await c.complete(system: 's', user: 'u', model: 'claude-sonnet-5');
    expect(r.text, 'cold ok');
    expect(started.last.$1, containsAll(['--output-format', 'json']));
    c.shutdownWarm();
  });

  test('a sign-in error is reported, not retried cold', () async {
    final started = <(List<String>, Process)>[];
    final c = client(
        started,
        (_) => _StreamProcess((m, n) => {
              'type': 'result',
              'is_error': true,
              'result': 'Not logged in · Please run /login',
            }));
    await expectLater(
        c.complete(system: 's', user: 'u', model: 'claude-sonnet-5'),
        throwsA(isA<AiException>()
            .having((e) => e.message, 'message', contains('Войти в Claude Code'))));
    expect(started, hasLength(1));
    c.shutdownWarm();
  });

  test('a long conversation is handed to a fresh process', () async {
    final started = <(List<String>, Process)>[];
    final c = client(started, (_) => _StreamProcess((m, n) => _ok('ok $n')));
    for (var i = 0; i < ClaudeCodeClient.warmMaxTurns + 1; i++) {
      await c.complete(system: 's', user: 'u$i', model: 'claude-sonnet-5');
    }
    expect(started.length, greaterThanOrEqualTo(2),
        reason: 'context grows with every turn; the pool starts over');
    c.shutdownWarm();
  });
}
