/// Dictating thoughts on the go: the recogniser runs without a time limit,
/// the screen stays on, every recognised sentence is saved at once, and
/// «новая мысль» / «стоп запись» work by voice. When the dictation ends,
/// each note goes to the background research.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/idea.dart';
import '../providers/providers.dart';
import '../core/database.dart';
import '../services/android_long_speech.dart';
import '../services/exchange_service.dart';
import '../services/idea_enricher.dart';
import '../services/long_dictation.dart';
import '../services/screen_awake.dart';
import '../services/voice_service.dart';

class DictationScreen extends ConsumerStatefulWidget {
  final IdeaProject project;
  const DictationScreen({super.key, required this.project});

  static Future<void> open(BuildContext context, IdeaProject project) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DictationScreen(project: project)));

  @override
  ConsumerState<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends ConsumerState<DictationScreen> {
  LongDictation? _dictation;
  final _typed = TextEditingController();
  String _committed = '';
  String _partial = '';
  bool _listening = false;
  bool _stopping = false;
  // A discussion: Claude's latest answer, and what it is doing now.
  String _claude = '';
  bool _thinking = false;
  bool _speaking = false;
  String? _error;
  String? _trouble; // what the recogniser is waiting out
  AndroidLongSpeech? _native;
  int? _noteId;
  int _saved = 0;
  late String _lang;
  final _clock = Stopwatch();
  Timer? _tick;
  Timer? _saveDebounce;
  // Note writes run one at a time: «новая мысль» right after a sentence
  // must not insert the same note twice.
  Future<void> _writes = Future.value();

  Future<void> _serially(Future<void> Function() job) {
    final next = _writes.then((_) => job());
    _writes = next.catchError((Object _) {});
    return next;
  }

  bool get _voice => VoiceService.isSupportedPlatform;

  // Taken once: leaving the screen still saves the last note, after `ref`
  // is gone.
  late final DatabaseService _db = ref.read(databaseProvider);
  late final IdeaEnricher _enricher = ref.read(ideaEnricherProvider);

  @override
  void initState() {
    super.initState();
    _db;
    _enricher;
    _lang = ref.read(configProvider).ideasLang;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _listening) setState(() {});
    });
    if (_voice) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _saveDebounce?.cancel();
    _typed.dispose();
    ScreenAwake.set(false);
    // Leaving the screen ends the dictation; what was said is kept.
    final d = _dictation;
    if (d != null && d.active) {
      d.stop().then(_finishNote);
    }
    super.dispose();
  }

  Future<void> _start() async {
    final voice = ref.read(voiceProvider);
    // Android: the native loop (one long session, no beep per pause, keeps
    // going with the screen off); elsewhere the plugin, segment by segment.
    final SpeechEngine engine =
        Platform.isAndroid ? (_native ??= AndroidLongSpeech(voice)) : voice;
    _native
      ?..muteBeeps = ref.read(configProvider).dictationMuteBeeps
      ..bluetooth = ref.read(configProvider).dictationBluetooth;
    final d = _dictation ??= LongDictation(
      engine,
      lang: _lang,
      onUpdate: _onUpdate,
      onCommand: _onCommand,
      onTrouble: (t) {
        if (mounted) setState(() => _trouble = t);
      },
      onFatal: (code) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _trouble = null;
          _error = code;
        });
        _clock.stop();
        ScreenAwake.set(false);
        _finishNote(_dictation?.takeText() ?? '');
      },
    );
    d.lang = _lang;
    setState(() {
      _error = null;
      _trouble = null;
    });
    final ok = await d.start();
    if (!mounted) return;
    setState(() => _listening = ok);
    if (ok) {
      _clock.start();
      ScreenAwake.set(true);
    } else {
      setState(() => _error ??= voice.lastError ?? 'error_init');
    }
  }

  void _onUpdate(String committed, String partial) {
    if (!mounted) return;
    final grew = committed != _committed;
    setState(() {
      _committed = committed;
      _partial = partial;
    });
    // Saved while spoken — finished phrases at once, words still being
    // recognised every couple of seconds: a crash or a lost phone keeps the
    // thought even if the recogniser is slow with its final result.
    final full = partial.trim().isEmpty
        ? committed
        : LongDictation.joinSegments(committed, partial);
    if (full.trim().isEmpty) return;
    _scheduleSave(full, Duration(milliseconds: grew ? 400 : 2000));
  }

  String? _toSave;

  void _scheduleSave(String full, Duration within) {
    _toSave = full;
    if (_saveDebounce?.isActive ?? false) {
      if (within > const Duration(milliseconds: 400)) return; // already due
      _saveDebounce!.cancel();
    }
    _saveDebounce = Timer(within, () {
      final t = _toSave;
      _toSave = null;
      if (t != null) _save(t);
    });
  }

  Future<void> _save(String text) => _serially(() async {
        final id = _noteId;
        if (id == null) {
          _noteId = await _db.addIdeaNote(widget.project.id!, text,
              source: 'voice', lang: _lang);
        } else {
          await _db.updateIdeaNoteText(id, text);
        }
      });

  void _onCommand(DictationCommand c) {
    switch (c) {
      case DictationCommand.newNote:
        _newNote();
      case DictationCommand.stop:
        _stop();
      case DictationCommand.discuss:
        _discuss();
    }
  }

  /// «Что думаешь?»: the thought so far becomes a note, Claude answers it
  /// briefly with a question, aloud; then dictation simply goes on — the
  /// author's reply is the next note.
  Future<void> _discuss() async {
    if (_thinking || _speaking) return;
    final l = AppLocalizations.of(context)!;
    final text = await _dictation?.takeFinishedText() ?? '';
    await _finishNote(text);
    if (!mounted) return;
    if (!_enricher.isAvailable) {
      setState(() => _claude = l.ideasNoAi);
      return;
    }
    setState(() => _thinking = true);
    try {
      final (_, reply) =
          await _enricher.discuss(widget.project.id!, lang: _lang);
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _claude = reply;
      });
      final voice = _native;
      if (voice != null && _listening) {
        setState(() => _speaking = true);
        await voice.speak(reply, _lang);
        if (mounted) setState(() => _speaking = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _thinking = false;
          _speaking = false;
          _claude = l.dictationDiscussFailed('$e');
        });
      }
    }
  }

  /// Close the current note (it goes to research) and start the next one.
  /// A phrase still being recognised is finished first and stays in it.
  Future<void> _newNote() async {
    final text = await _dictation?.takeFinishedText() ?? '';
    await _finishNote(text);
  }

  Future<void> _finishNote(String text) {
    _saveDebounce?.cancel();
    _toSave = null;
    return _serially(() async {
      final id = _noteId;
      _noteId = null;
      if (text.trim().isEmpty) {
        if (id != null) await _db.deleteIdeaNote(id);
        return;
      }
      int noteId;
      if (id == null) {
        noteId = await _db.addIdeaNote(widget.project.id!, text,
            source: 'voice', lang: _lang);
      } else {
        await _db.updateIdeaNoteText(id, text);
        noteId = id;
      }
      await _enricher.enqueue(noteId);
      // To the sync server soon: the PC can research it if the phone can't.
      ExchangeService.requestSync();
      if (mounted) setState(() => _saved++);
    });
  }

  Future<void> _stop() async {
    // The button and «стоп запись» may both ask for it.
    if (_stopping) return;
    _stopping = true;
    final d = _dictation;
    _clock.stop();
    ScreenAwake.set(false);
    if (d != null) {
      final text = await d.stop();
      await _finishNote(text);
      _dictation = null;
    }
    if (mounted) {
      setState(() {
        _listening = false;
        _committed = '';
        _partial = '';
      });
      Navigator.of(context).pop();
    }
  }

  String _troubleText(AppLocalizations l, String code) => switch (code) {
        'error_network' ||
        'error_network_timeout' ||
        'error_server' ||
        'error_server_disconnected' ||
        'error_too_many_requests' =>
          l.dictationTroubleNet,
        'error_audio' => l.dictationTroubleMic,
        'error_background' => l.dictationTroubleBackground,
        'error_busy' || 'error_client' => l.dictationTroubleBusy,
        _ => code,
      };

  String _errorText(AppLocalizations l, String code) => switch (code) {
        'error_permission' ||
        'error_insufficient_permissions' =>
          l.dictationErrPermission,
        'error_language_not_supported' ||
        'error_language_unavailable' =>
          l.dictationErrLanguage,
        'error_no_recognizer' => l.dictationErrNoRecognizer,
        'error_init' => l.dictationErrInit,
        _ => code,
      };

  Future<void> _saveTyped() async {
    final t = _typed.text.trim();
    if (t.isEmpty) return;
    final id = await _db.addIdeaNote(widget.project.id!, t, source: 'typed', lang: _lang);
    await _enricher.enqueue(id);
    _typed.clear();
    if (mounted) setState(() => _saved++);
  }

  String _elapsed() {
    final s = _clock.elapsed.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final fs = ref.watch(configProvider).fontSize;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.title, overflow: TextOverflow.ellipsis),
        actions: [
          DropdownButton<String>(
            value: _lang,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'ru', child: Text('RU')),
              DropdownMenuItem(value: 'es', child: Text('ES')),
              DropdownMenuItem(value: 'en', child: Text('EN')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _lang = v);
              final cfg = ref.read(configProvider)..ideasLang = v;
              cfg.save();
              _dictation?.lang = v; // from the next segment on
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'log') showDictationLog(context);
              if (v == 'mute' || v == 'bluetooth') {
                final cfg = ref.read(configProvider);
                // Applies from the next start («Продолжить»).
                setState(() => v == 'mute'
                    ? cfg.dictationMuteBeeps = !cfg.dictationMuteBeeps
                    : cfg.dictationBluetooth = !cfg.dictationBluetooth);
                cfg.save();
              }
            },
            itemBuilder: (c) => [
              if (Platform.isAndroid) ...[
                CheckedPopupMenuItem(
                  value: 'bluetooth',
                  checked: ref.read(configProvider).dictationBluetooth,
                  child: Text(l.dictationBluetooth),
                ),
                CheckedPopupMenuItem(
                  value: 'mute',
                  checked: ref.read(configProvider).dictationMuteBeeps,
                  child: Text(l.dictationMuteBeeps),
                ),
              ],
              PopupMenuItem(value: 'log', child: Text(l.dictationLog)),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                    !_listening
                        ? Icons.mic_off_rounded
                        : _trouble != null
                            ? Icons.sync_rounded
                            : Icons.mic_rounded,
                    color: !_listening
                        ? cs.outline
                        : _trouble != null
                            ? cs.tertiary
                            : cs.error,
                    size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      _thinking
                          ? l.dictationThinking
                          : _speaking
                              ? l.dictationSpeaking
                              : !_listening
                          ? l.dictationPaused
                          : _trouble != null
                              ? l.dictationReconnecting(_troubleText(l, _trouble!))
                              : '${l.dictationListening} · ${_elapsed()}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _trouble != null && _listening
                              ? cs.tertiary
                              : cs.outline,
                          fontSize: 12)),
                ),
                if (_saved > 0)
                  Text(l.dictationSaved(_saved),
                      style: TextStyle(color: cs.primary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            if (!_voice) ...[
              Text(l.dictationNoVoice,
                  style: TextStyle(color: cs.outline, fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _typed,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(fontSize: fs + 1),
                  decoration: InputDecoration(
                    hintText: l.dictationTypeHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saveTyped,
                icon: const Icon(Icons.save_rounded),
                label: Text(l.dictationSave),
              ),
            ] else ...[
              if (_claude.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.forum_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: SingleChildScrollView(
                            child: Text(_claude,
                                style: TextStyle(
                                    fontSize: fs + 1,
                                    height: 1.4,
                                    color: cs.onSurface)),
                          ),
                        ),
                      ),
                      if (_speaking)
                        IconButton(
                          tooltip: l.dictationStopSpeaking,
                          onPressed: () => _native?.stopSpeaking(),
                          icon: const Icon(Icons.volume_off_rounded),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: _committed),
                      if (_partial.isNotEmpty)
                        TextSpan(
                            text: '${_committed.isEmpty ? '' : ' '}$_partial',
                            style: TextStyle(color: cs.outline)),
                    ]),
                    style: TextStyle(fontSize: fs + 4, height: 1.45, color: cs.onSurface),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l.dictationError(_errorText(l, _error!)),
                      style: TextStyle(color: cs.error, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              Text(l.dictationHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.outline, fontSize: 11.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _listening ? _newNote : null,
                      icon: const Icon(Icons.note_add_rounded),
                      label: Text(l.dictationNewNote),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _listening && !_thinking && !_speaking
                          ? _discuss
                          : null,
                      icon: const Icon(Icons.forum_rounded),
                      label: Text(l.dictationDiscuss),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _listening
                        ? FilledButton.icon(
                            onPressed: _stop,
                            icon: const Icon(Icons.stop_rounded),
                            label: Text(l.dictationStop),
                            style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                minimumSize: const Size.fromHeight(56)),
                          )
                        : FilledButton.icon(
                            onPressed: _start,
                            icon: const Icon(Icons.mic_rounded),
                            label: Text(l.dictationResume),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56)),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The latest dictation's log: what the recogniser did, for sending when
/// something goes wrong.
void showDictationLog(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  final text = LongDictation.lastLog.join('\n');
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (c, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(l.dictationLog,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: text.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      messenger.showSnackBar(
                          SnackBar(content: Text(l.dictationCopied)));
                    },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l.dictationCopy),
            ),
          ]),
          Text(l.dictationLogHint,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(c).colorScheme.outline)),
          const SizedBox(height: 8),
          SelectableText(text.isEmpty ? l.dictationLogEmpty : text,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11.5, height: 1.35)),
        ],
      ),
    ),
  );
}
