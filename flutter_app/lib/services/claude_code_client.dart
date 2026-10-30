/// Claude through the user's own subscription (Pro/Max), via the locally
/// installed Claude Code CLI in headless mode (`claude -p`).
///
/// The Anthropic API is billed separately from a claude.ai subscription, so
/// a Max user with no API credit got nothing but errors. Headless Claude
/// Code runs on the subscription's usage limits instead (Anthropic support
/// article 15036540: "`claude -p` … still draw[s] from your subscription's
/// usage limits" — a planned change was paused on 2026-06-15, so this may
/// change). Desktop only; the CLI must be logged in once (`claude` → /login).
///
/// Every call is a pure completion: no tools (`--tools ""`), no session on
/// disk, no hooks/plugins/CLAUDE.md (`--safe-mode`), run from a private
/// working directory, with Claude-related environment variables stripped so
/// an inherited API key can't silently switch billing to the API.
///
/// Two ways to be signed in: the CLI's own login (`claude auth login`;
/// its access token is refreshed by the CLI and can still expire, e.g. when
/// the login is old), or a long-lived subscription token from
/// `claude setup-token` (valid for a year, still the subscription — not an
/// API key), which the app passes as CLAUDE_CODE_OAUTH_TOKEN.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai_types.dart';

class ClaudeCodeStatus {
  final String? path;
  final String? version;
  final bool loggedIn;
  final String? subscription; // max | pro | …
  final String? email;
  final String? authMethod; // claude.ai | oauth_token | …
  /// A subscription token (`claude setup-token`) is set in Settings.
  final bool tokenConfigured;
  final String? error;

  const ClaudeCodeStatus({
    this.path,
    this.version,
    this.loggedIn = false,
    this.subscription,
    this.email,
    this.authMethod,
    this.tokenConfigured = false,
    this.error,
  });

  bool get installed => path != null;
  bool get ready => installed && (loggedIn || tokenConfigured);
}

/// Runs a process; injectable for tests.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
});

class ClaudeCodeClient {
  /// Explicit executable path from Settings (empty = search PATH).
  final String Function() pathOverride;
  final String Function() workDir;
  /// Long-lived subscription token from `claude setup-token` ('' = none).
  final String Function() oauthToken;
  /// Keep Claude Code running between requests ([_WarmSession]).
  final bool Function() warm;
  final ProcessStarter _start;

  ClaudeCodeClient({
    required this.pathOverride,
    required this.workDir,
    String Function()? oauthToken,
    bool Function()? warm,
    ProcessStarter? start,
  })  : oauthToken = oauthToken ?? (() => ''),
        warm = warm ?? (() => false),
        _start = start ?? _defaultStart;

  static Future<Process> _defaultStart(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    final lower = executable.toLowerCase();
    if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
      // npm shim. Going through cmd.exe breaks as soon as the path has a
      // space and an argument needs quotes (e.g. `--tools ""`): cmd strips
      // the outer quotes and runs half a path. Start node + cli.js directly.
      final direct = _npmShimTarget(executable, environment);
      if (direct != null) {
        return Process.start(
          direct.$1,
          [direct.$2, ...arguments],
          workingDirectory: workingDirectory,
          environment: environment,
          includeParentEnvironment: includeParentEnvironment,
        );
      }
      return Process.start(executable, arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          includeParentEnvironment: includeParentEnvironment,
          runInShell: true);
    }
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
    );
  }

  /// (node.exe, cli.js) behind an npm `claude.cmd` shim, if resolvable.
  static (String, String)? _npmShimTarget(
      String shim, Map<String, String>? env) {
    final dir = p.dirname(shim);
    final cli = p.join(
        dir, 'node_modules', '@anthropic-ai', 'claude-code', 'cli.js');
    if (!File(cli).existsSync()) return null;
    final local = p.join(dir, 'node.exe');
    if (File(local).existsSync()) return (local, cli);
    final path = (env ?? Platform.environment)['PATH'] ??
        (env ?? Platform.environment)['Path'] ??
        '';
    for (final d in path.split(';')) {
      if (d.trim().isEmpty) continue;
      final n = p.join(d.trim(), 'node.exe');
      if (File(n).existsSync()) return (n, cli);
    }
    return null;
  }

  static bool get platformSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  String? _cachedPath;
  String? _cachedFor;

  /// Locate the `claude` executable. Cheap after the first call.
  String? locate() {
    if (!platformSupported) return null;
    final override = pathOverride().trim();
    if (_cachedFor == override && _cachedPath != null) return _cachedPath;
    _cachedFor = override;
    _cachedPath = _search(override);
    return _cachedPath;
  }

  static String? _search(String override) {
    if (override.isNotEmpty) {
      return File(override).existsSync() ? override : null;
    }
    final env = Platform.environment;
    final names = Platform.isWindows
        ? ['claude.exe', 'claude.cmd', 'claude.bat']
        : ['claude'];
    final sep = Platform.isWindows ? ';' : ':';
    for (final dir in (env['PATH'] ?? env['Path'] ?? '').split(sep)) {
      if (dir.trim().isEmpty) continue;
      for (final n in names) {
        final f = File(p.join(dir.trim(), n));
        if (f.existsSync()) return f.path;
      }
    }
    final home = env['USERPROFILE'] ?? env['HOME'] ?? '';
    final fallbacks = [
      if (home.isNotEmpty) p.join(home, '.local', 'bin', names.first),
      if (home.isNotEmpty && !Platform.isWindows)
        p.join(home, '.claude', 'local', 'claude'),
      if (env['APPDATA'] != null) p.join(env['APPDATA']!, 'npm', 'claude.cmd'),
    ];
    for (final f in fallbacks) {
      if (File(f).existsSync()) return f;
    }
    return null;
  }

  /// Environment for the child: everything except variables that would
  /// redirect auth/billing or make the CLI think it is nested in a session.
  static Map<String, String> cleanEnvironment(Map<String, String> parent) {
    final drop = RegExp(
        r'^(CLAUDECODE|CLAUDE_CODE_.*|ANTHROPIC_.*|CLAUDE_AGENT_SDK.*|'
        r'CLAUDE_PID|CLAUDE_EFFORT|CLAUDE_PREVIEW.*)$',
        caseSensitive: false);
    return {
      for (final e in parent.entries)
        if (!drop.hasMatch(e.key)) e.key: e.value,
    };
  }

  /// [cleanEnvironment] plus the user's own subscription token, if set.
  Map<String, String> childEnvironment(Map<String, String> parent) {
    final env = cleanEnvironment(parent);
    final token = oauthToken().trim();
    if (token.isNotEmpty) env['CLAUDE_CODE_OAUTH_TOKEN'] = token;
    return env;
  }

  bool get _tokenSet => oauthToken().trim().isNotEmpty;

  ClaudeCodeStatus? _status;
  DateTime? _statusAt;

  /// Installed? logged in? which plan? Cached for 10 minutes (two CLI
  /// starts cost seconds); «Обновить» forces a new check.
  Future<ClaudeCodeStatus> status({bool refresh = false}) async {
    final now = DateTime.now();
    if (!refresh &&
        _status != null &&
        _statusAt != null &&
        now.difference(_statusAt!) < const Duration(minutes: 10)) {
      return _status!;
    }
    final path = locate();
    if (path == null) {
      return _remember(const ClaudeCodeStatus(
          error: 'Claude Code не найден. Установите: '
              'https://claude.com/claude-code (или укажите путь в Настройках).'));
    }
    String? version;
    try {
      version =
          (await _run(path, ['--version'], timeout: const Duration(seconds: 30)))
              .$1
              .trim()
              .split('\n')
              .first;
      final (out, err, _) = await _run(path, ['auth', 'status', '--json'],
          timeout: const Duration(seconds: 30));
      final auth = extractJsonObject(out);
      final loggedIn = auth?['loggedIn'] == true;
      // An old CLI without `auth status --json` prints something else: show
      // it, instead of claiming the user is not logged in.
      final raw = '$out\n$err'
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      return _remember(ClaudeCodeStatus(
        path: path,
        version: version,
        loggedIn: loggedIn,
        subscription: auth?['subscriptionType']?.toString(),
        email: auth?['email']?.toString(),
        authMethod: auth?['authMethod']?.toString(),
        tokenConfigured: _tokenSet,
        error: loggedIn || _tokenSet
            ? null
            : (auth == null && raw.isNotEmpty
                ? 'Claude Code $version не сообщает статус входа («$raw»). '
                    'Обновите его: в терминале `claude update`. '
                    '$kNotLoggedInHint'
                : kNotLoggedInHint),
      ));
    } catch (e) {
      return _remember(ClaudeCodeStatus(
          path: path, version: version, tokenConfigured: _tokenSet,
          error: e.toString()));
    }
  }

  ClaudeCodeStatus _remember(ClaudeCodeStatus s) {
    _status = s;
    _statusAt = DateTime.now();
    return s;
  }

  static const kNotLoggedInHint =
      'Claude Code не вошёл в аккаунт. Нажмите «Войти в Claude Code» '
      '(Настройки → ИИ-помощник) и войдите аккаунтом с подпиской — или '
      'один раз создайте токен подписки на год: «Создать токен подписки». '
      'Вручную: в обычном терминале `claude auth login`.';

  /// Open a console window running `claude <args>` for the user: the
  /// sign-in flows need a real terminal and a browser. Windows only — the
  /// script goes through Explorer, so no quoting of paths through cmd.exe.
  static Future<void> openConsole(String claudePath, List<String> args,
      {required String dir, required List<String> intro}) async {
    Directory(dir).createSync(recursive: true);
    final script = File(p.join(dir, 'claude-${args.first}.cmd'));
    await script.writeAsString(consoleScript(claudePath, args, intro),
        flush: true);
    await Process.start('explorer.exe', [script.path]);
  }

  /// The batch file behind [openConsole]. Visible for tests.
  static String consoleScript(
      String claudePath, List<String> args, List<String> intro,
      {bool pause = true}) {
    String echo(String line) => line.isEmpty
        ? 'echo.'
        : 'echo ${line.replaceAll(RegExp(r'[&|<>^%]'), ' ')}';
    return [
      '@echo off',
      'chcp 65001 >nul',
      for (final l in intro) echo(l),
      'echo.',
      'call "$claudePath" ${args.join(' ')}',
      'echo.',
      'call "$claudePath" auth status --text',
      'echo.',
      if (pause) 'pause',
    ].join('\r\n');
  }

  /// One completion. [jsonSchema] turns on structured output; the parsed
  /// object is returned in [AiResult.json].
  ///
  /// Claude Code needs ~9–13 s to start on this kind of PC while the model
  /// itself answers in 1–3 s. So by default a request goes to a process
  /// that is already running ([_WarmSession]); a broken warm process falls
  /// back to one cold run (`claude -p`, with `--json-schema`).
  Future<AiResult> complete({
    required String system,
    required String user,
    required String model,
    String effort = 'medium',
    Map<String, dynamic>? jsonSchema,
    Duration timeout = const Duration(minutes: 5),
    /// Claude Code's own WebSearch/WebFetch (subscription). Always a cold
    /// run: the tool set is fixed per process.
    bool webTools = false,
    /// Files to read (PDFs): copied into the private working folder and
    /// read with the Read tool — the only tool enabled for such a run.
    List<AiDocument> documents = const [],
  }) async {
    final path = locate();
    if (path == null) {
      throw const AiException(
          'Claude Code не найден на этом компьютере. Установите его '
          '(claude.com/claude-code) или выберите другой ИИ в Настройках.');
    }
    if (documents.isNotEmpty) {
      final dir = Directory(workDir())..createSync(recursive: true);
      final files = <File>[];
      try {
        for (final d in documents) {
          final safe = d.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
          final f = File(p.join(dir.path,
              'doc_${DateTime.now().microsecondsSinceEpoch}_$safe'));
          await f.writeAsBytes(d.bytes, flush: true);
          files.add(f);
        }
        return await _completeCold(path,
            system: system,
            user: '$user\n\nRead these files with the Read tool:\n'
                '${files.map((f) => f.path).join('\n')}',
            model: model,
            effort: effort,
            jsonSchema: jsonSchema,
            timeout: timeout,
            tools: 'Read');
      } finally {
        for (final f in files) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    }
    if (webTools) {
      final r = await _completeCold(path,
          system: system,
          user: user,
          model: model,
          effort: effort,
          jsonSchema: jsonSchema,
          timeout: timeout,
          tools: 'WebSearch,WebFetch');
      return AiResult(
        text: r.text,
        json: r.json,
        backend: r.backend,
        provider: r.provider,
        model: r.model,
        stopReason: r.stopReason,
        inputTokens: r.inputTokens,
        outputTokens: r.outputTokens,
        durationMs: r.durationMs,
        // Claude Code returns only the final text: the links are in it.
        sources: [
          for (final l in _linksIn(r.text)) WebSource(l.$1, l.$2),
        ],
        searchedWeb: true,
      );
    }
    if (warm()) {
      try {
        return await _completeWarm(path,
            system: system,
            user: user,
            model: model,
            effort: effort,
            jsonSchema: jsonSchema,
            timeout: timeout);
      } on _WarmBroken {
        // fall through to one cold run
      }
    }
    return _completeCold(path,
        system: system,
        user: user,
        model: model,
        effort: effort,
        jsonSchema: jsonSchema,
        timeout: timeout);
  }

  Future<AiResult> _completeCold(
    String path, {
    required String system,
    required String user,
    required String model,
    required String effort,
    Map<String, dynamic>? jsonSchema,
    required Duration timeout,
    String tools = '',
  }) async {
    final dir = Directory(workDir())..createSync(recursive: true);
    // The system prompt goes through a file: long multi-line prompts as a
    // command-line argument hit quoting and length limits on Windows.
    final sysFile = File(p.join(dir.path,
        'system_${DateTime.now().microsecondsSinceEpoch}.txt'));
    await sysFile.writeAsString(system, flush: true);

    final args = <String>[
      '-p',
      '--output-format', 'json',
      '--tools', tools,
      // Allowed tools run without a permission prompt (there is nobody to
      // answer one in -p mode).
      if (tools.isNotEmpty) ...['--allowedTools', tools.replaceAll(',', ' ')],
      '--no-session-persistence',
      '--safe-mode',
      '--model', model,
      if (claudeSupportsEffort(model)) ...['--effort', effort],
      '--system-prompt-file', sysFile.path,
      if (jsonSchema != null) ...['--json-schema', jsonEncode(jsonSchema)],
    ];

    final sw = Stopwatch()..start();
    try {
      final (out, err, code) =
          await _run(path, args, stdin: user, timeout: timeout);
      final data = extractJsonObject(out);
      if (data == null) {
        final firstErr = err
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        if (err.toLowerCase().contains('unknown option')) {
          throw AiException(
              'Claude Code устарел и не знает нужных параметров. Обновите '
              'его: в терминале выполните `claude update`.',
              detail: err);
        }
        final authLike = _looksLikeAuthError('$out\n$err');
        final said = _clip('$out\n$err');
        throw AiException(
          authLike
              ? '$kNotLoggedInHint${said.isNotEmpty ? ' (ответ Claude Code: «$said»)' : ''}'
              : (code == 0
                  ? 'Claude Code вернул непонятный ответ'
                  : 'Claude Code завершился с ошибкой (код $code)'
                      '${firstErr.isNotEmpty ? ': $firstErr' : ''}'),
          detail: '${out.trim()}\n${err.trim()}'.trim(),
        );
      }
      return _toResult(data, model, wantJson: jsonSchema != null, ms: sw.elapsedMilliseconds);
    } finally {
      try {
        sysFile.deleteSync();
      } catch (_) {}
    }
  }

  static final _mdLink = RegExp(r'\[([^\]]{1,200})\]\((https?://[^)\s]+)\)');
  static final _bareLink = RegExp(r'(?<![(\[])https?://[^\s)\]>]+');

  /// (title, url) of the links in a Markdown answer, deduplicated.
  static List<(String, String)> _linksIn(String text) {
    final out = <(String, String)>[];
    final seen = <String>{};
    for (final m in _mdLink.allMatches(text)) {
      if (seen.add(m.group(2)!)) out.add((m.group(1)!, m.group(2)!));
    }
    for (final m in _bareLink.allMatches(text)) {
      final u = m.group(0)!.replaceAll(RegExp(r'[.,;:]+$'), '');
      if (seen.add(u)) out.add(('', u));
    }
    return out;
  }

  /// A `result` event (stream-json) or the `--output-format json` object.
  AiResult _toResult(Map<String, dynamic> data, String model,
      {required bool wantJson, required int ms}) {
    final resultText = (data['result'] ?? '').toString();
    if (data['is_error'] == true) {
      throw _mapError(resultText, data);
    }
    final usage = (data['usage'] as Map?) ?? const {};
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    final inTok = n(usage['input_tokens']) +
        n(usage['cache_read_input_tokens']) +
        n(usage['cache_creation_input_tokens']);
    final outTok = n(usage['output_tokens']);
    final models = (data['modelUsage'] as Map?)?.keys.map((k) => '$k') ??
        const <String>[];
    final usedModel = models.isNotEmpty ? models.first : model;

    Map<String, dynamic>? json;
    final so = data['structured_output'];
    if (so is Map) {
      json = so.cast<String, dynamic>();
    } else if (wantJson) {
      json = extractJsonObject(resultText);
    }
    final text = resultText.trim().isNotEmpty
        ? resultText.trim()
        : (json != null ? jsonEncode(json) : '');
    if (text.isEmpty) {
      throw const AiException('Claude вернул пустой ответ');
    }
    return AiResult(
      text: text,
      json: json,
      backend: 'Claude ${claudeModelLabel(_baseModel(usedModel))} · подписка',
      provider: 'claude_code',
      model: usedModel,
      stopReason: (data['stop_reason'] ?? '').toString(),
      inputTokens: inTok,
      outputTokens: outTok,
      durationMs: ms,
    );
  }

  // ─────────────────────────────────────────── warm sessions

  final _sessions = <_WarmSession>[];
  Timer? _reaper;

  /// At most this many running processes per model — two feed items are
  /// written in parallel.
  static const warmPerModel = 2;

  /// A session is replaced once its conversation (every turn is kept in
  /// context) gets long, or after this many turns.
  static const warmMaxContextTokens = 30000;
  static const warmMaxTurns = 12;
  static const warmIdleLimit = Duration(minutes: 20);

  static const _warmSystem =
      'You serve the LinguaTrace language-learning app. Every user message is '
      'a separate, independent task that brings its own instructions. Follow '
      'only the latest message: earlier messages in this conversation are '
      'unrelated and must not influence the answer. Answer exactly in the '
      'format the task asks for, with no preamble.';

  /// The instructions travel inside the message: one running process
  /// serves every feature.
  static String warmMessage(
      String system, String user, Map<String, dynamic>? schema) {
    final b = StringBuffer()
      ..writeln('=== NEW TASK — independent of every earlier message ===')
      ..writeln('<instructions>')
      ..writeln(system.trim())
      ..writeln('</instructions>')
      ..writeln('<input>')
      ..writeln(user.trim())
      ..writeln('</input>');
    if (schema != null) {
      b
        ..writeln('<output_format>')
        ..writeln('Return ONLY one JSON object that matches this JSON Schema '
            '— no prose, no code fences:')
        ..writeln(jsonEncode(schema))
        ..writeln('</output_format>');
    }
    return b.toString();
  }

  String _key(String model, String effort) =>
      '$model|$effort|${oauthToken().trim().hashCode}';

  /// Start a process for [model] now and let it finish its start-up with
  /// a tiny warm-up turn, so the user's first request is fast too.
  Future<void> prewarm(String model, {String effort = 'low'}) async {
    if (!warm()) return;
    final path = locate();
    if (path == null) return;
    final e = claudeSupportsEffort(model) ? effort : '';
    final key = _key(model, e);
    _sessions.removeWhere((x) => x.dead);
    if (_sessions.any((x) => x.key == key)) return;
    final s = await _spawnWarm(path, model, e, key);
    _sessions.add(s);
    s.warming = true;
    s.busy = true;
    try {
      await s.ask(warmMessage('Reply with exactly: ok', 'warm-up', null),
          const Duration(minutes: 2));
    } catch (_) {
      s.kill();
    } finally {
      s.warming = false;
      s.busy = false;
    }
  }

  Future<AiResult> _completeWarm(
    String path, {
    required String system,
    required String user,
    required String model,
    required String effort,
    Map<String, dynamic>? jsonSchema,
    required Duration timeout,
  }) async {
    final e = claudeSupportsEffort(model) ? effort : '';
    final s = await _acquire(path, model, e);
    final sw = Stopwatch()..start();
    Map<String, dynamic> data;
    try {
      data = await s.ask(warmMessage(system, user, jsonSchema), timeout);
    } on TimeoutException {
      s.kill();
      throw AiException(
          'Claude не ответил за ${timeout.inSeconds} с — попробуйте ещё раз '
          'или выберите более быструю модель.',
          retryable: true);
    } catch (_) {
      s.kill();
      throw const _WarmBroken();
    } finally {
      _release(s);
    }
    final r = _toResult(data, model,
        wantJson: jsonSchema != null, ms: sw.elapsedMilliseconds);
    // Structure is guaranteed only with --json-schema: if the JSON is
    // missing or lacks a required field, the cold run gets it right.
    if (jsonSchema != null && !hasRequiredFields(r.json, jsonSchema)) {
      throw const _WarmBroken();
    }
    return r;
  }

  /// Every top-level `required` key of [schema] is present in [json].
  static bool hasRequiredFields(
      Map<String, dynamic>? json, Map<String, dynamic> schema) {
    if (json == null) return false;
    final req = schema['required'];
    if (req is! List) return true;
    return req.every((k) => json.containsKey(k) && json[k] != null);
  }

  Future<_WarmSession> _acquire(String path, String model, String effort) async {
    final key = _key(model, effort);
    _reaper ??= Timer.periodic(const Duration(minutes: 1), (_) => _reap());
    for (;;) {
      _sessions.removeWhere((x) => x.dead);
      final mine = _sessions.where((x) => x.key == key).toList();
      final idle = mine.where((x) => !x.busy);
      if (idle.isNotEmpty) {
        final x = idle.first..busy = true;
        return x;
      }
      // A process finishing its warm-up is closer than a new cold one.
      if (mine.length < warmPerModel && !mine.any((x) => x.warming)) {
        final x = await _spawnWarm(path, model, effort, key);
        x.busy = true;
        _sessions.add(x);
        return x;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  void _release(_WarmSession s) {
    s.busy = false;
    s.lastUsed = DateTime.now();
    if (!s.dead &&
        (s.contextTokens > warmMaxContextTokens || s.turns >= warmMaxTurns)) {
      s.close();
      _sessions.remove(s);
      // A fresh process takes over in the background.
      final parts = s.key.split('|');
      unawaited(prewarm(parts[0], effort: parts[1].isEmpty ? 'low' : parts[1]));
    }
  }

  void _reap() {
    final now = DateTime.now();
    for (final x in [..._sessions]) {
      if (x.dead || (!x.busy && now.difference(x.lastUsed) > warmIdleLimit)) {
        x.close();
        _sessions.remove(x);
      }
    }
    if (_sessions.isEmpty) {
      _reaper?.cancel();
      _reaper = null;
    }
  }

  /// Stop every running process (tests, provider switch, app exit).
  void shutdownWarm() {
    for (final x in _sessions) {
      x.close();
    }
    _sessions.clear();
    _reaper?.cancel();
    _reaper = null;
  }

  Future<_WarmSession> _spawnWarm(
      String path, String model, String effort, String key) async {
    final dir = Directory(workDir())..createSync(recursive: true);
    final sysFile = File(p.join(dir.path, 'warm_system.txt'));
    if (!sysFile.existsSync() || sysFile.readAsStringSync() != _warmSystem) {
      sysFile.writeAsStringSync(_warmSystem, flush: true);
    }
    final proc = await _start(
      path,
      [
        '-p',
        '--input-format', 'stream-json',
        '--output-format', 'stream-json',
        '--verbose',
        '--tools', '',
        '--no-session-persistence',
        '--safe-mode',
        '--model', model,
        if (effort.isNotEmpty) ...['--effort', effort],
        '--system-prompt-file', sysFile.path,
      ],
      workingDirectory: dir.path,
      environment: childEnvironment(Platform.environment),
      includeParentEnvironment: false,
    );
    return _WarmSession(key, proc);
  }

  /// "claude-opus-5[1m]" / dated ids → the base id used in our tables.
  static String _baseModel(String m) {
    for (final k in kClaudePrices.keys) {
      if (m.startsWith(k)) return k;
    }
    return m;
  }

  static String _clip(String s) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= 160 ? t : '${t.substring(0, 160)}…';
  }

  static bool _looksLikeAuthError(String s) {
    final r = s.toLowerCase();
    return r.contains('not logged in') ||
        r.contains('/login') ||
        r.contains('failed to authenticate') ||
        r.contains('oauth') ||
        r.contains('unauthorized') ||
        r.contains('invalid api key') ||
        r.contains('authentication_error');
  }

  static AiException _mapError(String result, Map<String, dynamic> data) {
    final r = result.toLowerCase();
    if (_looksLikeAuthError(result)) {
      return AiException(
          r.contains('expired')
              ? 'Вход в Claude Code истёк (ответ Claude Code: «${_clip(result)}»). '
                  '$kNotLoggedInHint'
              : '$kNotLoggedInHint (ответ Claude Code: «${_clip(result)}»)',
          detail: result);
    }
    if (r.contains('usage limit') ||
        r.contains('limit reached') ||
        r.contains('rate limit')) {
      return AiException(
          'Исчерпан лимит подписки Claude на ближайшие часы. Подождите '
          'сброса лимита или временно выберите другой ИИ.',
          detail: result);
    }
    if (r.contains('credit balance') || r.contains('billing')) {
      return AiException(
          'Claude Code использует API-ключ без денег на счёте. Уберите '
          'ANTHROPIC_API_KEY из переменных среды, чтобы работала подписка.',
          detail: result);
    }
    if (r.contains('model') && (r.contains('not found') || r.contains('invalid'))) {
      return AiException('Модель недоступна для вашего аккаунта — выберите '
          'другую модель Claude в Настройках.', detail: result);
    }
    return AiException('Claude Code: ${result.isEmpty ? 'ошибка' : result}',
        detail: jsonEncode(data));
  }

  Future<(String, String, int)> _run(
    String exe,
    List<String> args, {
    String? stdin,
    required Duration timeout,
  }) async {
    Directory(workDir()).createSync(recursive: true);
    final proc = await _start(
      exe,
      args,
      workingDirectory: workDir(),
      environment: childEnvironment(Platform.environment),
      includeParentEnvironment: false,
    );
    final outF = proc.stdout.transform(utf8.decoder).join();
    final errF = proc.stderr.transform(utf8.decoder).join();
    if (stdin != null) {
      proc.stdin.add(utf8.encode(stdin));
    }
    await proc.stdin.close();
    try {
      final code = await proc.exitCode.timeout(timeout);
      return (await outF, await errF, code);
    } on TimeoutException {
      // Kill the whole tree: behind a shim, killing the parent would leave
      // the real CLI running and spending subscription quota.
      if (Platform.isWindows) {
        try {
          await Process.run(
              'taskkill', ['/T', '/F', '/PID', '${proc.pid}']);
        } catch (_) {
          proc.kill();
        }
      } else {
        proc.kill();
      }
      throw AiException(
          'Claude не ответил за ${timeout.inSeconds} с — попробуйте ещё раз '
          'или выберите более быструю модель.',
          retryable: true);
    }
  }
}

/// The warm process broke (exited, garbled output): retry in a cold run.
class _WarmBroken implements Exception {
  const _WarmBroken();
}

/// One Claude Code process in stream-json mode, kept between requests: its
/// start-up is paid once (measured on this PC: 12.7 s for the first answer,
/// 1.1–1.6 s for the next ones). Every turn stays in its context, so the
/// pool retires it after a while.
class _WarmSession {
  _WarmSession(this.key, this.proc) {
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone, onError: (_) => _onDone());
    proc.stderr.transform(utf8.decoder).listen((t) {
      _stderr.write(t);
      if (_stderr.length > 4000) {
        final keep = _stderr.toString().substring(_stderr.length - 2000);
        _stderr
          ..clear()
          ..write(keep);
      }
    }, onError: (_) {});
  }

  final String key;
  final Process proc;
  int turns = 0;
  int contextTokens = 0;
  bool busy = false;
  bool warming = false;
  bool dead = false;
  DateTime lastUsed = DateTime.now();
  Completer<Map<String, dynamic>>? _pending;
  final _stderr = StringBuffer();

  void _onLine(String line) {
    final l = line.trim();
    if (!l.startsWith('{')) return;
    Object? ev;
    try {
      ev = jsonDecode(l);
    } catch (_) {
      return;
    }
    if (ev is Map && ev['type'] == 'result') {
      final usage = (ev['usage'] as Map?) ?? const {};
      int n(Object? v) => (v as num?)?.toInt() ?? 0;
      contextTokens = n(usage['input_tokens']) +
          n(usage['cache_read_input_tokens']) +
          n(usage['cache_creation_input_tokens']) +
          n(usage['output_tokens']);
      final c = _pending;
      _pending = null;
      c?.complete(ev.cast<String, dynamic>());
    }
  }

  void _onDone() {
    dead = true;
    final c = _pending;
    _pending = null;
    c?.completeError(StateError('Claude Code exited: $_stderr'));
  }

  Future<Map<String, dynamic>> ask(String text, Duration timeout) async {
    if (dead) throw StateError('Claude Code is not running');
    final c = Completer<Map<String, dynamic>>();
    _pending = c;
    final line = jsonEncode({
      'type': 'user',
      'message': {'role': 'user', 'content': text},
    });
    // Bytes, not IOSink.writeln: its default encoding is the ANSI code page.
    proc.stdin.add(utf8.encode('$line\n'));
    await proc.stdin.flush();
    try {
      return await c.future.timeout(timeout);
    } finally {
      turns++;
      lastUsed = DateTime.now();
    }
  }

  /// Graceful: end of input lets the CLI finish and exit.
  void close() {
    if (dead) return;
    dead = true;
    try {
      proc.stdin.close();
    } catch (_) {}
    Timer(const Duration(seconds: 15), () => proc.kill());
  }

  void kill() {
    dead = true;
    if (Platform.isWindows) {
      Process.run('taskkill', ['/T', '/F', '/PID', '${proc.pid}'])
          .catchError((_) => ProcessResult(0, 0, '', ''));
    } else {
      proc.kill();
    }
  }
}

