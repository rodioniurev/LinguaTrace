/// Dictation without a time limit, for thinking out loud while walking.
///
/// The phone's recogniser is made for short phrases. On Android the native
/// loop (LongSpeech.kt) keeps one long session going and retries whatever
/// goes wrong; elsewhere a new segment starts here whenever one ends. Every
/// recognised phrase is committed to the transcript (and saved by the
/// caller); transient trouble (no network, busy microphone, screen off) is
/// shown and waited out — only a missing permission or language ends it.
///
/// Voice commands at the end of a phrase: «новая мысль» starts a new note,
/// «стоп запись» ends the dictation — no need to look at the screen.
library;

import 'dart:async';

/// The recogniser, as the dictation needs it (a fake one in tests).
abstract class SpeechEngine {
  /// Start listening. [onEnd] fires when the platform ends a segment (pause,
  /// time limit) — an engine that restarts by itself never calls it;
  /// [onError] with the platform's code and whether retrying is pointless
  /// (no permission, no speech pack); [onTrouble] with what is being waited
  /// out, null once it hears again; [onLog] with lines for the diagnostics
  /// log. False if it can't start.
  Future<bool> startSegment({
    required String lang,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onEnd,
    required void Function(String code, bool permanent) onError,
    void Function(String? trouble)? onTrouble,
    void Function(String line)? onLog,
  });

  /// Stop; the last phrase's final result is delivered before this returns
  /// (where the platform allows).
  Future<void> stopSegment();

  /// Finish the phrase being spoken now; its final result follows.
  Future<void> flush();
}

enum DictationCommand { newNote, stop, discuss }

class LongDictation {
  LongDictation(
    this._engine, {
    required this.lang,
    required this.onUpdate,
    this.onCommand,
    this.onFatal,
    this.onTrouble,
    this.restartDelay = const Duration(milliseconds: 150),
  });

  final SpeechEngine _engine;
  String lang;
  /// Transcript so far and the words still being recognised.
  final void Function(String committed, String partial) onUpdate;
  final void Function(DictationCommand command)? onCommand;
  final void Function(String code)? onFatal;
  /// What is being waited out (an error code), null when hearing again.
  final void Function(String? trouble)? onTrouble;
  final Duration restartDelay;

  bool _active = false;
  bool _stopping = false;
  String _committed = '';
  String _partial = '';
  String? _trouble;
  int _failuresInRow = 0;
  int _segment = 0;
  Completer<void>? _finalWaiter;
  // Words «новая мысль» took from a phrase still being recognised: its late
  // final result must not repeat them in the next note.
  String _taken = '';

  /// Diagnostics: what the recogniser did (shown and copied on request).
  final log = <String>[];

  /// The latest dictation's log, kept after its screen is closed.
  static List<String> lastLog = const [];
  final _clock = Stopwatch();

  bool get active => _active;
  String get text => _committed;
  String? get trouble => _trouble;

  void _log(String line) {
    lastLog = log;
    log.add(line);
    if (log.length > 400) log.removeRange(0, log.length - 400);
  }

  void _note(String what) => _log(
      '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(6)} s  · $what');

  Future<bool> start() async {
    if (_active) return true;
    _active = true;
    _failuresInRow = 0;
    _clock.start();
    _note('start ($lang)');
    final ok = await _listen();
    if (!ok) {
      _active = false;
      _note('could not start');
    }
    return ok;
  }

  Future<bool> _listen() {
    final seg = ++_segment;
    return _engine.startSegment(
      lang: lang,
      onResult: (w, fin) {
        if (seg == _segment) _onResult(w, fin);
      },
      onEnd: () {
        if (seg == _segment) _onEnd();
      },
      onError: (code, permanent) {
        if (seg == _segment) _onError(code, permanent);
      },
      onTrouble: (t) {
        if (seg == _segment) _setTrouble(t);
      },
      onLog: _log,
    );
  }

  void _setTrouble(String? t) {
    if (!_active || t == _trouble) return;
    _trouble = t;
    _note(t == null ? 'hearing again' : 'waiting: $t');
    onTrouble?.call(t);
  }

  void _onResult(String words, bool isFinal) {
    if (!_active) return;
    _failuresInRow = 0;
    _setTrouble(null);
    if (isFinal) {
      _commit(words);
    } else {
      _partial = words;
      onUpdate(_committed, _partial);
    }
  }

  void _commit(String words, {bool commands = true}) {
    _partial = '';
    final (text, command) = splitCommand(_withoutTaken(words), lang);
    if (text.isNotEmpty) _committed = joinSegments(_committed, text);
    onUpdate(_committed, '');
    final w = _finalWaiter;
    if (w != null && !w.isCompleted) w.complete();
    if (command != null) {
      _note('command ${command.name}');
      if (commands && !_stopping) onCommand?.call(command);
    }
  }

  String _withoutTaken(String words) {
    final taken = _taken;
    _taken = '';
    if (taken.isEmpty) return words;
    final a = _norm(taken).split(' ');
    final w = words.trim().split(RegExp(r'\s+'));
    if (w.length < a.length) return words;
    for (var i = 0; i < a.length; i++) {
      if (_norm(w[i]) != a[i]) return words;
    }
    return w.skip(a.length).join(' ');
  }

  void _onEnd() {
    if (!_active || _stopping) return;
    // A segment cut off before its final result: keep what was heard.
    if (_partial.trim().isNotEmpty) _commit(_partial);
    _restartSoon(restartDelay);
  }

  void _onError(String code, bool permanent) {
    if (!_active || _stopping) return;
    _note('error $code${permanent ? ' (permanent)' : ''}');
    if (permanent) {
      _active = false;
      if (_partial.trim().isNotEmpty) _commit(_partial, commands: false);
      onFatal?.call(code);
      return;
    }
    if (_partial.trim().isNotEmpty) _commit(_partial);
    // Silence and "not recognised" are normal while walking; anything else
    // is waited out with a growing pause (up to 5 s) — never given up on.
    final quiet = code == 'error_no_match' || code == 'error_speech_timeout';
    if (!quiet) {
      _failuresInRow++;
      _setTrouble(code);
    }
    final wait = quiet
        ? restartDelay
        : Duration(milliseconds: (400 * _failuresInRow).clamp(400, 5000));
    _restartSoon(wait);
  }

  bool _restartPending = false;

  /// One restart at a time: the platform may report both "done" and an
  /// error for the same segment.
  void _restartSoon(Duration wait) {
    if (_restartPending) return;
    _restartPending = true;
    Future<void>.delayed(wait, () async {
      _restartPending = false;
      if (!_active || _stopping) return;
      final ok = await _listen();
      if (!ok && _active) _onError('error_client', false);
    });
  }

  /// Text so far, and a fresh transcript for the next note.
  String takeText() {
    final p = _partial;
    if (p.trim().isNotEmpty) {
      _commit(p, commands: false);
      _taken = p;
    }
    final t = _committed;
    _committed = '';
    onUpdate('', '');
    if (t.isNotEmpty) _note('note taken, ${t.length} chars');
    return t;
  }

  /// Like [takeText], but a phrase still being recognised is finished first
  /// (up to [wait]), so its words land in this note and not in the next one.
  Future<String> takeFinishedText(
      {Duration wait = const Duration(seconds: 3)}) async {
    if (_active && !_stopping && _partial.trim().isNotEmpty) {
      final c = _finalWaiter = Completer<void>();
      unawaited(_engine.flush());
      await c.future.timeout(wait, onTimeout: () {});
      _finalWaiter = null;
    }
    return takeText();
  }

  /// Stop listening; returns the transcript. The phrase being spoken is
  /// kept: the engine delivers it while stopping.
  Future<String> stop() async {
    if (_stopping) return _committed;
    if (_active) {
      _stopping = true;
      try {
        await _engine.stopSegment();
      } catch (_) {}
      _stopping = false;
    }
    _active = false;
    _segment++;
    _clock.stop();
    _note('stopped');
    if (_partial.trim().isNotEmpty) _commit(_partial, commands: false);
    return _committed;
  }

  // ─────────────────────────────────────────── text helpers

  static const _commands = <DictationCommand, List<String>>{
    DictationCommand.newNote: [
      'новая мысль', 'следующая мысль', 'новая заметка',
      'nueva idea', 'siguiente idea', 'nueva nota',
      'new thought', 'next thought', 'new note',
    ],
    DictationCommand.stop: [
      'стоп запись', 'конец записи', 'закончить запись', 'остановить запись',
      'parar grabación', 'fin de la grabación', 'detener grabación',
      'stop recording', 'end recording',
    ],
    // Claude answers and asks: a discussion.
    DictationCommand.discuss: [
      'что думаешь', 'что ты думаешь', 'что скажешь', 'твоё мнение',
      'твое мнение', 'обсудим', 'задай вопрос', 'задай мне вопрос',
      'qué opinas', 'qué piensas', 'hazme una pregunta',
      'what do you think', 'your thoughts', 'ask me a question',
    ],
  };

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// A command spoken at the end of a segment («…и это всё. Новая мысль»)
  /// is cut off and returned separately. Visible for tests.
  static (String, DictationCommand?) splitCommand(String words, String lang) {
    final w = words.trim();
    if (w.isEmpty) return ('', null);
    final n = _norm(w);
    for (final e in _commands.entries) {
      for (final phrase in e.value) {
        final p = _norm(phrase);
        if (n == p) return ('', e.key);
        if (n.endsWith(' $p')) {
          // Remove as many trailing words as the command has.
          final count = p.split(' ').length;
          final parts = w.split(RegExp(r'\s+'));
          final keep = parts.sublist(0, (parts.length - count).clamp(0, parts.length));
          return (keep.join(' ').trim(), e.key);
        }
      }
    }
    return (w, null);
  }

  /// A pause ends a sentence: segments are joined with a full stop unless
  /// the recogniser already put punctuation there.
  static String joinSegments(String before, String next) {
    final b = before.trimRight();
    final n = next.trim();
    if (b.isEmpty) return _capitalize(n);
    final ends = RegExp(r'[.!?…:;,]$').hasMatch(b);
    return '$b${ends ? ' ' : '. '}${_capitalize(n)}';
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
