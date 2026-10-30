import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../core/constructions.dart';
import '../core/database.dart';
import '../core/languages.dart';
import '../l10n/app_localizations.dart';
import '../models/correction.dart';
import '../models/mistake.dart';
import '../models/translation_entry.dart';
import '../providers/providers.dart';
import '../services/linguistics_service.dart';
import '../services/proverb_service.dart';
import '../services/translator_service.dart';
import '../services/voice_service.dart';
import '../widgets/language_selector.dart';
import 'etymology_screen.dart';
import 'word_choice_screen.dart';

/// A translation waiting to be committed to history once typing settles.
class _PendingLookup {
  final String text;
  final TranslationResult result;
  _PendingLookup(this.text, this.result);
  bool get cached => result.translator.contains('cached');
}

/// A group of translations by part of speech from Google dictionary data.
class _DictGroup {
  final String pos;
  final List<String> translations;
  _DictGroup(this.pos, this.translations);
}

/// A single word + its translation for word-by-word breakdown.
class _WordPair {
  final String source;
  final String target;
  _WordPair(this.source, this.target);
}

class TranslateScreen extends ConsumerStatefulWidget {
  final String? initialText;

  const TranslateScreen({super.key, this.initialText});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen>
    with WidgetsBindingObserver {
  // Cached so a pending lookup can still be committed from dispose() and
  // app-lifecycle callbacks, where `ref` must not be used.
  late final DatabaseService _db = ref.read(databaseProvider);
  late final _cfg = ref.read(configProvider);
  late final _historyVersion = ref.read(historyVersionProvider.notifier);

  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  Timer? _debounce;

  String _result = '';
  String _translatorName = '';
  bool _loading = false;
  String? _error;

  late String _srcLang;
  late String _tgtLang;

  // Linguistics — source word
  LinguisticInfo? _lingInfo;
  // Linguistics — target word (the translated word)
  LinguisticInfo? _lingInfoTarget;
  // Grammar cards expanded state
  bool _grammarExpanded = false;
  bool _grammarTargetExpanded = false;

  // Voice
  bool _isListening = false;
  // Saved text around the cursor position for insert-at-cursor mode
  String _voiceTextBefore = '';
  String _voiceTextAfter  = '';

  // Word-by-word breakdown
  List<_WordPair>? _wordByWord;
  bool _wbwLoading = false;

  // All meanings (dictionary) for source word
  List<_DictGroup>? _dictMeanings;
  bool _dictLoading = false;
  bool _dictExpanded = false;

  // Proverb search
  List<ProverbMatch>? _proverbResults;
  bool _proverbLoading = false;

  // Cultural context (AI)
  String? _culturalContext;
  bool _contextLoading = false;

  // Clean capture: a lookup is written to history only once typing has
  // settled (2.5 s idle, copy, clear, leaving) — the old 300 ms auto-save
  // stored every keystroke fragment ("добры" → "добрый" → "добрый ден").
  Timer? _commitTimer;
  _PendingLookup? _pending;
  int? _lastCommittedId;
  String _lastCommittedNorm = '';
  String _lastCommittedPair = '';
  DateTime? _lastCommittedAt;
  /// Bumped by clear/swap/language change: a commit still in flight from
  /// before must not make the next lookup look like its continuation.
  int _captureEpoch = 0;
  /// Last text seen by the listener — selection-only notifications (a
  /// click in the field, arrow keys) must not count as edits.
  String _lastInputText = '';
  int _ownCheckGen = 0;
  bool _ownCheckInFlight = false; // UI flag _ownChecking is reset on edits
  /// After a failed automatic check (no credit, offline) the next ones wait:
  /// otherwise every sentence typed would end in the same error.
  DateTime? _ownCheckPausedUntil;
  _PendingLookup? _recheckAfter;

  // Notebook: keys "kind|lang|norm" already taken into use.
  final Set<String> _savedKeys = {};

  // Background check of text the user writes in the language they develop.
  CorrectionResult? _ownCheck;
  bool _ownChecking = false;
  String _ownCheckedNorm = '';
  String? _ownCheckError;
  final Map<CorrectionFix, int> _ownFixIds = {};
  final Set<int> _rejectedFixIds = {};

  // Only text the user produced (typed or dictated) is "their" language —
  // a pasted article or a shared message must not be checked as their own
  // writing (it would burn the subscription and record other people's
  // sentences). A jump of more than 15 characters in one change = paste.
  bool _pasted = false;
  int _prevLen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Touch the late caches while `ref` is certainly valid.
    _db;
    _historyVersion;
    final cfg = _cfg;
    _srcLang = cfg.sourceLang;
    _tgtLang = cfg.targetLang;

    _inputCtrl.addListener(_onTextChanged);

    // No auto-focus: the feed is the home tab now, and focusing this (kept
    // alive, invisible) field would pop the keyboard over it.
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _inputCtrl.text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _translate());
    }
  }

  @override
  void dispose() {
    // Stop voice recognition if the user navigates away mid-dictation,
    // otherwise the mic stays hot and callbacks keep firing.
    if (_isListening) {
      try {
        ref.read(voiceProvider).stopListening();
      } catch (_) {/* provider may already be disposed */}
    }
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _commitNow();
    _inputCtrl.removeListener(_onTextChanged);
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app counts as "done typing".
    if (state != AppLifecycleState.resumed) _commitNow();
  }

  // ── debounced auto-translate ──────────────────────────────────────────────

  void _onTextChanged() {
    // TextEditingController also notifies on cursor/selection changes.
    if (_inputCtrl.text == _lastInputText) return;
    _lastInputText = _inputCtrl.text;
    _debounce?.cancel();
    // Idle time counts from the last keystroke, not from the last result.
    if (_pending != null) {
      if (_inputCtrl.text.trim().isEmpty) {
        _commitNow(); // the user wiped the field: keep what they looked up
      } else {
        _commitTimer?.cancel();
        _pending = null; // superseded by what is being typed now
      }
    }
    final len = _inputCtrl.text.length;
    if (len == 0) {
      _pasted = false;
    } else if (len - _prevLen > 15) {
      _pasted = true;
    }
    _prevLen = len;
    final text = _inputCtrl.text.trim();
    // Clear all secondary data on ANY text change
    setState(() {
      _wordByWord = null;
      _wbwLoading = false;
      _proverbResults = null;
      _proverbLoading = false;
      _culturalContext = null;
      _contextLoading = false;
      _ownCheck = null;
      _ownCheckError = null;
      _ownChecking = false;
    });
    if (text.isEmpty) {
      setState(() {
        _result = '';
        _translatorName = '';
        _error = null;
        _lingInfo = null;
        _lingInfoTarget = null;
        _dictMeanings = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _translate);
  }

  // ── translation ───────────────────────────────────────────────────────────

  int _translateId = 0;

  Future<void> _translate() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    // Generation counter — a slow first request whose response arrives after
    // a faster second request must NOT overwrite the second request's state.
    final reqId = ++_translateId;

    setState(() {
      _loading = true;
      _error = null;
      // Clear ALL secondary data from previous translation
      _wordByWord = null;
      _wbwLoading = false;
      _proverbResults = null;
      _proverbLoading = false;
      _dictMeanings = null;
      _dictLoading = false;
      _lingInfo = null;
      _lingInfoTarget = null;
    });

    try {
      final svc = ref.read(translatorProvider);
      final db = ref.read(databaseProvider);

      var result = await svc.translateWithCache(
        text,
        db,
        targetLang: _tgtLang,
        sourceLang: _srcLang,
      );
      // Stale response — a newer translate call superseded us. Drop silently.
      if (reqId != _translateId) return;

      // Auto-retarget: with source=auto, typing Russian while the target is
      // Russian just echoes the input back (RU→RU). Flip the target to the
      // "other" studied language and translate again — like every mainstream
      // translator does.
      final detected = result.sourceLang.length >= 2
          ? result.sourceLang.substring(0, 2).toLowerCase()
          : result.sourceLang;
      final tgt2 = _tgtLang.length >= 2
          ? _tgtLang.substring(0, 2).toLowerCase()
          : _tgtLang;
      if (_srcLang == 'auto' && detected == tgt2) {
        final newTarget = detected == 'ru' ? 'es' : 'ru';
        setState(() => _tgtLang = newTarget);
        final cfg = ref.read(configProvider)
          ..targetLang = newTarget;
        cfg.save();
        result = await svc.translateWithCache(
          text,
          db,
          targetLang: newTarget,
          sourceLang: _srcLang,
        );
        if (reqId != _translateId) return;
      }

      // History is written once typing settles, not on every keystroke.
      _scheduleCommit(_PendingLookup(text, result));

      if (mounted) {
        _lastDetectedSrc = result.sourceLang;
        setState(() {
          _result = result.text;
          _translatorName = result.translator;
          _loading = false;
        });

        // For single words: fetch all dictionary meanings + grammar
        if (isSingleWord(text)) {
          _fetchAllMeanings(text, _srcLang == 'auto' ? result.sourceLang : _srcLang, _tgtLang);
          final analyzeLang = _srcLang == 'auto' ? result.sourceLang : _srcLang;
          _fetchLinguistics(text, analyzeLang);
          if (isSingleWord(result.text) && result.text != text) {
            _fetchLinguistics(result.text, _tgtLang, secondary: true);
          }
        } else {
          // Multi-word input: look for a matching proverb automatically —
          // requiring a separate tap on "Idiom" made the feature invisible.
          // Silent when nothing matches (no empty box after every sentence).
          _searchProverb(auto: true);
        }
      }
    } catch (e) {
      if (reqId != _translateId) return; // stale failure, ignore
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchLinguistics(String word, String lang, {bool secondary = false}) async {
    final svc = ref.read(linguisticsProvider);
    final info = await svc.analyze(word, lang);

    if (mounted) {
      if (secondary) {
        setState(() => _lingInfoTarget = info);
      } else {
        setState(() => _lingInfo = info);
      }
    }
  }

  // ── clean capture + learner model ─────────────────────────────────────────

  static String _two(String code) =>
      code.length >= 2 ? code.substring(0, 2).toLowerCase() : code.toLowerCase();

  static final _cyrillic = RegExp(r'[Ѐ-ӿ]');

  /// The real source language of [text]. Offline backends (on-device LLM,
  /// ML Kit, Ollama) report 'auto' — which _two() would turn into "au".
  /// Falls back to an explicit source, then to the script; null = unknown.
  String? _resolvedSrc(String reported, String text) {
    final r = reported.toLowerCase();
    if (r.isNotEmpty && r != 'auto' && kLanguages.containsKey(_two(r))) {
      return _two(r);
    }
    if (_srcLang != 'auto') return _two(_srcLang);
    if (_cyrillic.hasMatch(text)) return 'ru';
    return null;
  }

  void _scheduleCommit(_PendingLookup p) {
    _pending = p;
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 2500), _commitNow);
  }

  /// Write the pending lookup. Safe to call any time (no-op if nothing is
  /// pending). Continuing to edit the same text within two minutes replaces
  /// the row instead of adding a fragment.
  Future<void> _commitNow() async {
    _commitTimer?.cancel();
    final p = _pending;
    _pending = null;
    if (p == null) return;
    final db = _db;
    final r = p.result;
    final norm = DatabaseService.normalize(p.text);
    final pair = '${r.sourceLang}>${r.targetLang}';
    final epoch = _captureEpoch;
    try {
      // Cache hits are written too: a repeated lookup is exactly the "I
      // keep forgetting this" signal, and a row survives pattern rebuilds.
      final entry = TranslationEntry(
        sourceText: p.text,
        translatedText: r.text,
        sourceLang: r.sourceLang,
        targetLang: r.targetLang,
        translator: r.translator,
        contextApp: DatabaseService.deviceId.split(':').first,
        device: DatabaseService.deviceId,
      );
      final last = _lastCommittedAt;
      final continuation = _lastCommittedId != null &&
          last != null &&
          pair == _lastCommittedPair &&
          DateTime.now().difference(last) < const Duration(minutes: 2) &&
          (norm.startsWith(_lastCommittedNorm) ||
              _lastCommittedNorm.startsWith(norm));
      final int translationId = continuation
          ? await db.replaceTranslation(_lastCommittedId!, entry)
          : await db.addTranslation(entry);
      if (epoch == _captureEpoch) {
        _lastCommittedId = translationId;
        _lastCommittedNorm = norm;
        _lastCommittedPair = pair;
        _lastCommittedAt = DateTime.now();
      }
      await _recordLookupItem(p, translationId);
      _historyVersion.state++;
    } catch (_) {
      // History is best-effort; never break translating.
    }
    if (mounted) _maybeCheckOwnText(p);
  }

  /// Short lookups become learning items: the foreign side of the pair is
  /// what the user needed (RU→ES = a word they needed to SAY; ES→RU = a
  /// word they needed to UNDERSTAND).
  Future<void> _recordLookupItem(_PendingLookup p, int? translationId) async {
    final tokens = DatabaseService.tokenCount(p.text);
    if (tokens == 0 || tokens > 4) return;
    final cfg = _cfg;
    final native = _two(cfg.nativeLang);
    final src = _resolvedSrc(p.result.sourceLang, p.text);
    if (src == null) return; // unknown language: don't guess
    final tgt = _two(p.result.targetLang);
    final String lang, text, gloss;
    if (src != native) {
      (lang, text, gloss) = (src, p.text, p.result.text);
    } else if (tgt != native) {
      (lang, text, gloss) = (tgt, p.result.text, p.text);
    } else {
      return;
    }
    if (text.trim().isEmpty || DatabaseService.tokenCount(text) > 6) return;
    final db = _db;
    final id = await db.upsertItem(
      kind: DatabaseService.tokenCount(text) == 1 ? 'word' : 'collocation',
      lang: lang,
      text: text,
      gloss: gloss,
      source: src == native ? 'lookup_produce' : 'lookup_understand',
    );
    await db.addEvent(id, 'lookup',
        surface: 'translate', translationId: translationId);
  }

  String _itemKey(String kind, String lang, String text) =>
      '$kind|$lang|${DatabaseService.normalize(text)}';

  /// What «В тетрадь» on the translation would save: the foreign side of a
  /// short pair (≤ 8 words), or null when there is nothing sensible.
  ({String kind, String lang, String text, String gloss})? _notebookCandidate() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _result.isEmpty || _loading) return null;
    final native = _two(_cfg.nativeLang);
    final srcDetected = _resolvedSrc(_lastDetectedSrc ?? _srcLang, text);
    if (srcDetected == null) return null;
    final tgt = _two(_tgtLang);
    final (lang, itemText, gloss) = srcDetected != native
        ? (srcDetected, text, _result)
        : (tgt, _result, text);
    if (lang == native) return null;
    final n = DatabaseService.tokenCount(itemText);
    if (n == 0 || n > 8) return null;
    final kind = n == 1 ? 'word' : 'collocation';
    return (kind: kind, lang: lang, text: itemText, gloss: gloss);
  }

  /// The foreign word or short expression of this lookup, for its
  /// «Происхождение» page (≤ 5 words, punctuation stripped).
  ({String lang, String text})? _originTerm() {
    final c = _notebookCandidate();
    if (c == null) return null;
    final t = c.text
        .replaceAll(RegExp(r'^[\s¿¡«"“(]+|[\s?!.,;:»"”)]+$'), '')
        .trim();
    if (t.isEmpty || DatabaseService.tokenCount(t) > 5) return null;
    return (lang: c.lang, text: t);
  }

  Future<void> _openWordChoice() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _result.isEmpty) return;
    final src = _resolvedSrc(_lastDetectedSrc ?? _srcLang, text) ??
        (_srcLang == 'auto' ? 'ru' : _two(_srcLang));
    final chosen = await WordChoiceScreen.open(context,
        source: text, translation: _result, srcLang: src, tgtLang: _two(_tgtLang));
    if (chosen != null && chosen.trim().isNotEmpty && mounted) {
      await _applyChosen(chosen.trim());
    }
  }

  /// The user took a better translation from «Подбор слова»: show it, and
  /// keep it in the history (and so in the cache) instead of the machine
  /// one — next time the same text gets the user's own choice.
  Future<void> _applyChosen(String sentence) async {
    final text = _inputCtrl.text.trim();
    final l = AppLocalizations.of(context)!;
    final src = _pending?.result.sourceLang ?? _lastDetectedSrc ?? _srcLang;
    final r = TranslationResult(
      text: sentence,
      sourceLang: src,
      targetLang: _tgtLang,
      translator: 'claude-choice',
    );
    setState(() {
      _result = sentence;
      _translatorName = l.chosenTranslation;
    });
    if (_pending != null) {
      _pending = _PendingLookup(text, r); // committed with the chosen text
      return;
    }
    final id = _lastCommittedId;
    if (id == null) {
      _scheduleCommit(_PendingLookup(text, r));
      return;
    }
    try {
      await _db.replaceTranslation(
          id,
          TranslationEntry(
            sourceText: text,
            translatedText: sentence,
            sourceLang: src,
            targetLang: _tgtLang,
            translator: 'claude-choice',
            contextApp: DatabaseService.deviceId.split(':').first,
            device: DatabaseService.deviceId,
          ));
      _historyVersion.state++;
    } catch (_) {}
  }

  /// «В тетрадь» for the current short translation.
  Future<void> _saveResultToNotebook() async {
    final c = _notebookCandidate();
    if (c == null) return;
    await _commitNow();
    await _saveItem(
        kind: c.kind, lang: c.lang, text: c.text, gloss: c.gloss,
        source: 'translate');
  }

  /// What «В тетрадь» saves for a proverb row: only text that came from
  /// the dictionary itself (never the "(авто)" machine fill), in the
  /// language being developed — or the target language if it is foreign.
  /// Null = nothing sensible to save (the button is hidden).
  ({String lang, String text, String gloss})? _proverbSaveTarget(
      ProverbMatch pm) {
    final marker = AppLocalizations.of(context)!.autoMarker;
    final orig = {
      for (final e in pm.byLang().entries)
        if (!e.value.trim().endsWith(marker)) e.key: e.value,
    };
    final native = _two(_cfg.nativeLang);
    final learn = _two(_cfg.learningLang);
    final tgt = _two(_tgtLang);
    final lang = orig.containsKey(learn)
        ? learn
        : (tgt != native && orig.containsKey(tgt) ? tgt : null);
    if (lang == null) return null;
    return (
      lang: lang,
      text: orig[lang]!,
      gloss: orig[native] ?? orig['en'] ?? '',
    );
  }

  Future<void> _saveProverb(ProverbMatch pm) async {
    final t = _proverbSaveTarget(pm);
    if (t == null) return;
    await _saveItem(
      kind: 'proverb',
      lang: t.lang,
      text: t.text,
      gloss: t.gloss,
      conceptKey: pm.conceptKey ?? '',
      source: 'proverb_db:${pm.source ?? ''}',
    );
  }

  Future<void> _saveItem({
    required String kind,
    required String lang,
    required String text,
    String gloss = '',
    String conceptKey = '',
    String source = '',
  }) async {
    final db = ref.read(databaseProvider);
    final id = await db.upsertItem(
      kind: kind,
      lang: lang,
      text: text,
      gloss: gloss,
      conceptKey: conceptKey,
      source: source,
      status: 'learning',
    );
    await db.addEvent(id, 'saved',
        surface: 'translate', context: _inputCtrl.text.trim());
    ref.read(historyVersionProvider.notifier).state++;
    if (!mounted) return;
    setState(() => _savedKeys.add(_itemKey(kind, lang, text)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.savedToNotebookSnack(text)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  bool _isSaved(String kind, String lang, String text) =>
      _savedKeys.contains(_itemKey(kind, lang, text));

  String? _lastDetectedSrc;

  /// The user wrote in the language they are developing → check it in the
  /// background and record real mistakes. This is what makes "my problem
  /// constructions" accumulate without a trip to the Проверка tab.
  Future<void> _maybeCheckOwnText(_PendingLookup p) async {
    final cfg = ref.read(configProvider);
    if (!cfg.autoCheckOwnText || _pasted) return;
    if (_resolvedSrc(p.result.sourceLang, p.text) != _two(cfg.learningLang)) {
      return;
    }
    if (DatabaseService.tokenCount(p.text) < 3) return;
    final norm = DatabaseService.normalize(p.text);
    if (norm == _ownCheckedNorm) return;
    final svc = ref.read(correctionProvider);
    if (!svc.hasBackend) return;
    final paused = _ownCheckPausedUntil;
    if (paused != null && DateTime.now().isBefore(paused)) return;
    // Still the text on screen?
    if (DatabaseService.normalize(_inputCtrl.text) != norm) return;
    // One check at a time (each is a Claude call); the newest settled text
    // is checked when the running one finishes.
    if (_ownCheckInFlight) {
      _recheckAfter = p;
      return;
    }

    final gen = ++_ownCheckGen;
    _ownCheckInFlight = true;
    _ownCheckedNorm = norm;
    setState(() {
      _ownChecking = true;
      _ownCheck = null;
      _ownCheckError = null;
      _ownFixIds.clear();
    });
    bool current() =>
        mounted &&
        gen == _ownCheckGen &&
        DatabaseService.normalize(_inputCtrl.text) == norm;
    try {
      final r = await svc.correct(p.text, cfg.learningLang,
          nativeLang: cfg.nativeLang, feature: 'auto_check');
      final db = ref.read(databaseProvider);
      final ids = <CorrectionFix, int>{};
      for (final f in r.recordable) {
        ids[f] = await db.addMistake(Mistake(
          original: f.original,
          corrected: f.fixed,
          reason: f.reason,
          category: f.category ?? '',
          construction: f.construction,
          severity: f.severity,
          backend: r.backend,
          lang: _two(cfg.learningLang),
          context: p.text,
          source: 'auto_check',
        ));
      }
      if (r.trustworthy && r.fixes.isEmpty) {
        // A correct sentence is evidence too (production without errors).
        await db.addEvent(null, 'produced_ok',
            surface: 'auto_check', context: p.text);
      }
      if (ids.isNotEmpty && mounted) {
        ref.read(historyVersionProvider.notifier).state++;
      }
      _ownCheckPausedUntil = null;
      if (current()) {
        setState(() {
          _ownFixIds
            ..clear()
            ..addAll(ids);
          _ownCheck = r;
          _ownCheckError = null;
          _ownChecking = false;
        });
      } else if (mounted) {
        setState(() => _ownChecking = false);
      }
    } catch (e) {
      _ownCheckPausedUntil = DateTime.now().add(const Duration(minutes: 10));
      if (current()) {
        setState(() {
          _ownChecking = false;
          _ownCheckError = e.toString();
        });
      } else if (mounted) {
        setState(() => _ownChecking = false);
      }
    }
    _ownCheckInFlight = false;
    final next = _recheckAfter;
    _recheckAfter = null;
    if (next != null && mounted) _maybeCheckOwnText(next);
  }

  Future<void> _rejectOwnFix(CorrectionFix f) async {
    final id = _ownFixIds[f];
    if (id == null) return;
    await ref.read(databaseProvider).rejectMistake(id);
    ref.read(historyVersionProvider.notifier).state++;
    if (!mounted) return;
    setState(() => _rejectedFixIds.add(id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.markedNotError),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── swap ───────────────────────────────────────────────────────────────────

  void _swap() {
    if (_srcLang == 'auto') {
      // Silent return would be confusing — explain why nothing happened.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pickSourceBeforeSwap),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _commitNow();
    _captureEpoch++;
    _lastCommittedId = null;
    // The swapped-in text is a machine translation, not the user's writing.
    _pasted = true;
    final cfg = ref.read(configProvider);
    final tmpLang = _srcLang;
    setState(() {
      _srcLang = _tgtLang;
      _tgtLang = tmpLang;
      // Put result into input
      if (_result.isNotEmpty) {
        _inputCtrl.removeListener(_onTextChanged);
        _inputCtrl.text = _result;
        _prevLen = _inputCtrl.text.length;
        _lastInputText = _inputCtrl.text;
        _result = '';
        _translatorName = '';
        _lingInfo = null;
        _inputCtrl.addListener(_onTextChanged);
        // Trigger translate with swapped text
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 100), _translate);
      }
    });
    cfg.sourceLang = _srcLang;
    cfg.targetLang = _tgtLang;
    cfg.save();
  }

  // ── voice ──────────────────────────────────────────────────────────────────

  /// Tap mic: insert dictation at the cursor (keeps surrounding text).
  Future<void> _toggleVoice() => _startVoice(replaceAll: false);

  /// Long-press mic: clear field first, then dictate fresh.
  Future<void> _longPressVoice() async {
    // Light haptic so the user knows long-press registered
    HapticFeedback.mediumImpact();
    await _startVoice(replaceAll: true);
  }

  Future<void> _startVoice({required bool replaceAll}) async {
    final voice = ref.read(voiceProvider);
    if (_isListening) {
      await voice.stopListening();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    // Decide where dictation goes. Replace-all wipes the field; otherwise we
    // insert at the cursor (or at the end if no cursor).
    if (replaceAll) {
      _inputCtrl.removeListener(_onTextChanged);
      _inputCtrl.clear();
      _inputCtrl.addListener(_onTextChanged);
      _pasted = false;
      _voiceTextBefore = '';
      _voiceTextAfter  = '';
    } else {
      final sel = _inputCtrl.selection;
      final insertAt = (sel.isValid && sel.baseOffset >= 0)
          ? sel.baseOffset
          : _inputCtrl.text.length;
      _voiceTextBefore = _inputCtrl.text.substring(0, insertAt);
      _voiceTextAfter  = _inputCtrl.text.substring(insertAt);
    }

    // When the source language is auto, guess from the target: dictating in
    // the language you are ABOUT to translate from is the common case, and
    // en_US mis-hearing Russian was the old behavior's worst failure.
    final dictationLang = _srcLang != 'auto'
        ? _srcLang
        : (_tgtLang == 'ru' ? 'es' : 'ru');

    setState(() => _isListening = true);
    final started = await voice.startListening(
      lang: dictationLang,
      onResult: (text, isFinal) {
        if (mounted) {
          _inputCtrl.removeListener(_onTextChanged);
          _inputCtrl.text = _voiceTextBefore + text + _voiceTextAfter;
          // Dictation is the user's own language, not a paste.
          _prevLen = _inputCtrl.text.length;
          _lastInputText = _inputCtrl.text;
          // Keep cursor right after the newly dictated text
          _inputCtrl.selection = TextSelection.collapsed(
              offset: _voiceTextBefore.length + text.length);
          _inputCtrl.addListener(_onTextChanged);
          if (isFinal) {
            setState(() => _isListening = false);
            _translate();
          }
        }
      },
      // The engine can stop on its own (silence timeout) without a final
      // result — without this hook the mic button stayed "listening" forever.
      onDone: () {
        if (mounted && _isListening) {
          setState(() => _isListening = false);
          if (_inputCtrl.text.trim().isNotEmpty) _translate();
        }
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
    if (!started && mounted && _isListening) {
      setState(() => _isListening = false);
    }
  }

  // ── copy ───────────────────────────────────────────────────────────────────

  void _copyResult() {
    _commitNow(); // copying = the user is done with this text
    if (_result.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _result));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.copied)),
      );
    }
  }

  // ── all meanings (dictionary card) ───────────────────────────────────────

  Future<void> _fetchAllMeanings(String text, String src, String tgt) async {
    setState(() {
      _dictLoading = true;
      _dictMeanings = null;
    });

    try {
      var groups = <_DictGroup>[];

      // Strategy 1: Direct src→tgt with dt=bd (works for en→*, sometimes others)
      groups = await _fetchGoogleDict(text, src, tgt);

      // Strategy 2: If empty, go via English: src→en (get dict data) then
      // separately show what English meanings map to in target language
      if (groups.isEmpty && src != 'en') {
        groups = await _fetchGoogleDict(text, src, 'en');
        // Now translate each English meaning to target language
        if (groups.isNotEmpty && tgt != 'en') {
          final translated = <_DictGroup>[];
          for (final g in groups) {
            final tList = <String>[];
            for (final eng in g.translations.take(5)) {
              // Translate each English meaning to target
              try {
                final tUrl = Uri.parse(
                  'https://translate.googleapis.com/translate_a/single'
                  '?client=gtx&sl=en&tl=${Uri.encodeComponent(tgt)}&dt=t'
                  '&q=${Uri.encodeComponent(eng)}');
                final tResp = await http.get(tUrl, headers: {'User-Agent': 'Mozilla/5.0'})
                    .timeout(const Duration(seconds: 4));
                if (tResp.statusCode == 200) {
                  final td = jsonDecode(tResp.body);
                  final buf = StringBuffer();
                  for (final s in (td[0] as List)) {
                    if (s is List && s.isNotEmpty && s[0] is String) buf.write(s[0]);
                  }
                  final tr = buf.toString().trim();
                  if (tr.isNotEmpty) tList.add('$tr ($eng)');
                }
              } catch (_) {
                tList.add(eng); // fallback: show English
              }
            }
            if (tList.isNotEmpty) {
              translated.add(_DictGroup(g.pos, tList));
            }
          }
          groups = translated;
        }
      }

      // Strategy 3: Use data[5] alternatives (always available)
      if (groups.isEmpty) {
        final altUrl = Uri.parse(
          'https://translate.googleapis.com/translate_a/single'
          '?client=gtx'
          '&sl=${Uri.encodeComponent(src)}'
          '&tl=${Uri.encodeComponent(tgt)}'
          '&dt=at&dt=t'
          '&q=${Uri.encodeComponent(text)}');
        final altResp = await http.get(altUrl, headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 8));
        if (altResp.statusCode == 200) {
          final data = jsonDecode(altResp.body);
          if (data.length > 5 && data[5] is List) {
            final alts = <String>[];
            for (final item in data[5] as List) {
              if (item is List && item.length > 2 && item[2] is List) {
                for (final alt in (item[2] as List).take(8)) {
                  if (alt is List && alt.isNotEmpty && alt[0] is String) {
                    final t = alt[0] as String;
                    if (!alts.contains(t)) alts.add(t);
                  }
                }
              }
            }
            if (alts.isNotEmpty) {
              groups = [_DictGroup('', alts)];
            }
          }
        }
      }

      if (mounted && groups.isNotEmpty) {
        setState(() { _dictMeanings = groups; _dictLoading = false; });
      } else {
        if (mounted) setState(() => _dictLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _dictLoading = false);
    }
  }

  Future<List<_DictGroup>> _fetchGoogleDict(String text, String src, String tgt) async {
    final url = Uri.parse(
      'https://translate.googleapis.com/translate_a/single'
      '?client=gtx'
      '&sl=${Uri.encodeComponent(src)}'
      '&tl=${Uri.encodeComponent(tgt)}'
      '&dt=bd'
      '&q=${Uri.encodeComponent(text)}');
    final resp = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return [];

    final data = jsonDecode(resp.body);
    final groups = <_DictGroup>[];
    if (data.length > 1 && data[1] is List) {
      for (final group in data[1] as List) {
        if (group is! List || group.length < 2) continue;
        final pos = (group[0] as String? ?? '');
        final translations = <String>[];
        // Format: [pos, [trans1, trans2, ...], [[trans, [reverse], score], ...]]
        if (group[1] is List) {
          for (final t in (group[1] as List).take(6)) {
            if (t is String) translations.add(t);
          }
        }
        if (translations.isEmpty && group.length > 2 && group[2] is List) {
          for (final entry in (group[2] as List).take(6)) {
            if (entry is List && entry.isNotEmpty && entry[0] is String) {
              translations.add(entry[0] as String);
            }
          }
        }
        if (translations.isNotEmpty) groups.add(_DictGroup(pos, translations));
      }
    }
    return groups;
  }

  // ── word-by-word breakdown ───────────────────────────────────────────────

  Future<void> _wordByWordBreakdown() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    // Strip punctuation from tokens — a chip "молиться," with a trailing
    // comma both looks sloppy and hurts the per-word translation.
    final words = text
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(
            RegExp(r'^[^\wа-яёА-ЯЁáéíóúüñÁÉÍÓÚÜÑ]+|[^\wа-яёА-ЯЁáéíóúüñÁÉÍÓÚÜÑ]+$'),
            ''))
        .where((w) => w.length > 1)
        .toList();
    if (words.isEmpty) return;

    setState(() {
      _wbwLoading = true;
      _wordByWord = null;
    });

    try {
      final src = _srcLang == 'auto' ? 'auto' : _srcLang;
      final tgt = _tgtLang;
      final pairs = <_WordPair>[];

      for (final word in words.take(15)) {
        try {
          final url = Uri.parse(
            'https://translate.googleapis.com/translate_a/single'
            '?client=gtx&sl=${Uri.encodeComponent(src)}'
            '&tl=${Uri.encodeComponent(tgt)}&dt=t&dt=bd'
            '&q=${Uri.encodeComponent(word)}');
          final resp = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'})
              .timeout(const Duration(seconds: 4));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            // Get primary translation
            var trans = '';
            if (data[0] is List) {
              for (final s in data[0] as List) {
                if (s is List && s.isNotEmpty && s[0] is String) {
                  trans = s[0] as String;
                  break;
                }
              }
            }
            // Check if dict data has more info
            String? posHint;
            if (data.length > 1 && data[1] is List) {
              for (final g in data[1] as List) {
                if (g is List && g.isNotEmpty) {
                  posHint = (g[0] as String? ?? '').toLowerCase();
                  // Get first translation from dict
                  if (g.length > 1 && g[1] is List && (g[1] as List).isNotEmpty) {
                    trans = (g[1] as List).first as String;
                  }
                  break;
                }
              }
            }
            final label = posHint != null && posHint.isNotEmpty
                ? '$trans ($posHint)'
                : trans;
            pairs.add(_WordPair(word, label));
          }
        } catch (_) {
          pairs.add(_WordPair(word, '?'));
        }
      }

      if (mounted) {
        setState(() {
          _wordByWord = pairs;
          _wbwLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _wbwLoading = false);
    }
  }

  // ── proverb search (in-app) ──────────────────────────────────────────────

  int _proverbSearchId = 0;

  Future<void> _searchProverb({bool auto = false}) async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final searchId = ++_proverbSearchId;

    setState(() {
      // In auto mode keep the UI quiet — no spinner, no empty box.
      _proverbLoading = !auto;
      if (!auto) _proverbResults = null;
    });

    try {
      final svc = ref.read(proverbProvider);
      var results = await svc.search(text);

      // Cancelled — new search started
      if (searchId != _proverbSearchId || !mounted) return;

      // Also search the translated result if the source query returned nothing
      if (results.isEmpty && _result.isNotEmpty && _result != text) {
        results = await svc.search(_result);
        if (searchId != _proverbSearchId || !mounted) return;
      }

      if (auto && results.isEmpty) {
        setState(() => _proverbLoading = false);
        return;
      }

      // Show local matches IMMEDIATELY — the old code first spent seconds on
      // network round-trips filling missing translations while the user
      // stared at a spinner.
      setState(() {
        _proverbResults = results;
        _proverbLoading = false;
      });

      // Then fill missing target-language slots progressively in-place.
      _fillMissingTargets(results, searchId);
    } catch (_) {
      if (searchId == _proverbSearchId && mounted) {
        setState(() {
          _proverbResults = auto ? null : [];
          _proverbLoading = false;
        });
      }
    }
  }

  /// The v2 DB already contains direct equivalents in many languages. For
  /// rows where the target column is empty, machine-translate the English
  /// text and patch the row in-place — one setState per filled row, so
  /// results render progressively instead of blocking on the network.
  Future<void> _fillMissingTargets(
      List<ProverbMatch> results, int searchId) async {
    final tgtLc = _tgtLang.length >= 2 ? _tgtLang.substring(0, 2) : _tgtLang;
    if (tgtLc == 'en') return;

    for (var i = 0; i < results.length && i < 6; i++) {
      if (searchId != _proverbSearchId || !mounted) return;
      final pm = results[i];
      final tgtAlready = pm.byLang()[tgtLc];
      if (tgtAlready != null && tgtAlready.isNotEmpty) continue; // direct match
      if (pm.textEn == null || pm.textEn!.isEmpty) continue;
      try {
        final url = Uri.parse(
          'https://translate.googleapis.com/translate_a/single'
          '?client=gtx&sl=en&tl=${Uri.encodeComponent(tgtLc)}&dt=t'
          '&q=${Uri.encodeComponent(pm.textEn!)}');
        final resp = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && searchId == _proverbSearchId && mounted) {
          final data = jsonDecode(resp.body);
          final buf = StringBuffer();
          for (final s in (data[0] as List)) {
            if (s is List && s.isNotEmpty && s[0] is String) buf.write(s[0]);
          }
          final tr = buf.toString().trim();
          if (tr.isNotEmpty) {
            final autoMarker = AppLocalizations.of(context)!.autoMarker;
            setState(() {
              results[i] = _withFilledLang(pm, tgtLc, '$tr $autoMarker');
              _proverbResults = results;
            });
          }
        }
      } catch (_) {}
    }
  }

  // ── cultural context (AI) ────────────────────────────────────────────────

  int _contextRequestId = 0;

  Future<void> _fetchCulturalContext() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final svc = ref.read(culturalContextProvider);
    if (!svc.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.addAiKeyHint),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reqId = ++_contextRequestId;
    setState(() {
      _contextLoading = true;
      _culturalContext = null;
    });
    try {
      final result = await svc.explain(text);
      if (reqId == _contextRequestId && mounted) {
        setState(() {
          _culturalContext = result;
          _contextLoading = false;
        });
      }
    } catch (e) {
      if (reqId == _contextRequestId && mounted) {
        setState(() {
          _culturalContext =
              AppLocalizations.of(context)!.contextFailed(e.toString());
          _contextLoading = false;
        });
      }
    }
  }

  /// Return a copy of [pm] with the named language slot filled in.
  ProverbMatch _withFilledLang(ProverbMatch pm, String lang, String value) {
    return ProverbMatch(
      textRu:    lang == 'ru' ? value : pm.textRu,
      textEs:    lang == 'es' ? value : pm.textEs,
      textEn:    lang == 'en' ? value : pm.textEn,
      textDe:    lang == 'de' ? value : pm.textDe,
      textFr:    lang == 'fr' ? value : pm.textFr,
      textUk:    lang == 'uk' ? value : pm.textUk,
      textTr:    lang == 'tr' ? value : pm.textTr,
      literalEn: pm.literalEn,
      source:    pm.source,
      confidence: pm.confidence,
      conceptKey: pm.conceptKey,
      region:     pm.region,
    );
  }

  // ── language picker ────────────────────────────────────────────────────────

  Future<void> _pickSource() async {
    final code = await LanguagePickerSheet.show(
      context,
      currentValue: _srcLang,
      includeAuto: true,
    );
    if (code != null && code != _srcLang) {
      _commitNow();
      _captureEpoch++;
      _lastCommittedId = null;
      setState(() => _srcLang = code);
      ref.read(configProvider)
        ..sourceLang = code
        ..save();
      if (_inputCtrl.text.trim().isNotEmpty) _translate();
    }
  }

  Future<void> _pickTarget() async {
    final code = await LanguagePickerSheet.show(
      context,
      currentValue: _tgtLang,
    );
    if (code != null && code != _tgtLang) {
      _commitNow();
      _captureEpoch++;
      _lastCommittedId = null;
      setState(() => _tgtLang = code);
      ref.read(configProvider)
        ..targetLang = code
        ..save();
      if (_inputCtrl.text.trim().isNotEmpty) _translate();
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = ref.watch(configProvider).fontSize;

    // Text shared from another app while we are already running.
    ref.listen<String?>(sharedTextProvider, (_, text) {
      if (text == null || text.isEmpty) return;
      ref.read(sharedTextProvider.notifier).state = null; // consume
      _inputCtrl.text = text; // listener schedules the debounced translate
      _debounce?.cancel();
      _translate();
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Content scrolls freely — lang bar is pinned at the bottom
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _buildInputContainer(cs, fs),
                    if (_result.isNotEmpty || _loading || _error != null) ...[
                      const SizedBox(height: 10),
                      _buildResultCard(cs, fs),
                    ],
                    // The user's own text in the language they develop,
                    // checked in the background.
                    if (_ownChecking ||
                        _ownCheck != null ||
                        _ownCheckError != null) ...[
                      const SizedBox(height: 10),
                      _buildOwnCheckCard(cs, fs),
                    ],
                    // Dictionary card — all meanings by PoS
                    if (_dictMeanings != null || _dictLoading) ...[
                      const SizedBox(height: 10),
                      _buildDictCard(cs),
                    ],
                    // Grammar cards — collapsible
                    if (_lingInfo != null && !_lingInfo!.isEmpty) ...[
                      const SizedBox(height: 10),
                      _buildCollapsibleGrammar(
                        cs, _lingInfo!, _inputCtrl.text.trim(),
                        _grammarExpanded, (v) => setState(() => _grammarExpanded = v),
                      ),
                    ],
                    if (_lingInfoTarget != null && !_lingInfoTarget!.isEmpty) ...[
                      const SizedBox(height: 10),
                      _buildCollapsibleGrammar(
                        cs, _lingInfoTarget!, _result,
                        _grammarTargetExpanded, (v) => setState(() => _grammarTargetExpanded = v),
                      ),
                    ],
                    // Cultural context (AI) — origin, meaning, connotations
                    if (_culturalContext != null || _contextLoading) ...[
                      const SizedBox(height: 10),
                      _buildContextCard(cs, fs),
                    ],
                  ],
                ),
              ),
            ),
            // Lang bar at the BOTTOM — always in thumb-reach zone
            _buildLangBar(cs),
          ],
        ),
      ),
    );
  }

  // ── language bar ──────────────────────────────────────────────────────────

  Widget _buildLangBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline)),
      ),
      child: Row(
        children: [
          Expanded(child: _langChip(_srcLang, cs, _pickSource)),
          // Swap — 48×48 touch target per Material spec, with ripple feedback
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _swap,
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.swap_horiz_rounded, color: cs.primary, size: 28),
              ),
            ),
          ),
          Expanded(child: _langChip(_tgtLang, cs, _pickTarget)),
        ],
      ),
    );
  }

  Widget _langChip(String code, ColorScheme cs, VoidCallback onTap) {
    final label = code == 'auto'
        ? AppLocalizations.of(context)!.autoDetect
        : localizedLangName(code, Localizations.localeOf(context).languageCode);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.outline.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(color: cs.onSurface, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }

  // ── clear all ────────────────────────────────────────────────────────────

  void _clearAll() {
    _commitNow();
    _captureEpoch++;
    _lastCommittedId = null; // the next text is a new lookup, not an edit
    _pasted = false;
    _prevLen = 0;
    _lastInputText = '';
    _inputCtrl.removeListener(_onTextChanged);
    _inputCtrl.clear();
    _inputCtrl.addListener(_onTextChanged);
    setState(() {
      _result = '';
      _translatorName = '';
      _error = null;
      _lingInfo = null;
      _lingInfoTarget = null;
      _wordByWord = null;
      _wbwLoading = false;
      _dictMeanings = null;
      _dictLoading = false;
      _proverbResults = null;
      _proverbLoading = false;
      _culturalContext = null;
      _contextLoading = false;
      _ownCheck = null;
      _ownChecking = false;
      _ownCheckError = null;
    });
    // requestFocus alone doesn't re-open the soft keyboard when the platform
    // has already hidden it — ask for it explicitly so the user can type
    // again immediately without tapping the field.
    _inputFocus.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  // ── proverb row (single match, multi-language) ───────────────────────────

  /// Display-friendly language name from a 2-letter ISO code, in the UI
  /// language ("язык: русский", not "язык: Russian").
  String _langChipName(String code) {
    if (code.length < 2) return code.toUpperCase();
    final two = code.substring(0, 2).toLowerCase();
    final ui = Localizations.localeOf(context).languageCode;
    return localizedLangName(two, ui).split('(').first.trim();
  }

  static const _langFlag = <String, String>{
    'ru': '🇷🇺', 'es': '🇪🇸', 'en': '🇬🇧', 'de': '🇩🇪',
    'fr': '🇫🇷', 'uk': '🇺🇦', 'tr': '🇹🇷',
  };

  Widget _buildProverbRow(ProverbMatch pm, ColorScheme cs) {
    final tgtLc = _tgtLang.length >= 2
        ? _tgtLang.substring(0, 2).toLowerCase()
        : _tgtLang.toLowerCase();
    final byLang = pm.byLang();
    // Sort languages: target first → source → others
    final srcLc = _srcLang.length >= 2
        ? _srcLang.substring(0, 2).toLowerCase()
        : _srcLang.toLowerCase();
    final order = <String>[];
    if (byLang.containsKey(tgtLc)) order.add(tgtLc);
    if (srcLc != tgtLc && byLang.containsKey(srcLc)) order.add(srcLc);
    for (final code in ['ru', 'es', 'en', 'de', 'fr', 'uk', 'tr']) {
      if (!order.contains(code) && byLang.containsKey(code)) order.add(code);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One line per language, with the target highlighted
          for (final code in order)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Small lang tag — flag if known, else code
                  Container(
                    width: 26,
                    padding: const EdgeInsets.only(top: 1, right: 4),
                    child: Text(
                      _langFlag[code] ?? code.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: code == tgtLc ? cs.tertiary : cs.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      byLang[code]!,
                      style: TextStyle(
                        color: code == tgtLc ? cs.onSurface : cs.onSurface.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: code == tgtLc ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Literal back-translation (only when distinct from the proverb itself)
          if (pm.literalEn != null && pm.literalEn!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              AppLocalizations.of(context)!.literalLabel(pm.literalEn!),
              style: TextStyle(
                color: cs.outline,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          // Source + «В тетрадь» — the one verb that takes an expression into
          // active use (it becomes a target of practice and the feed).
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                if (pm.source != null && pm.source!.isNotEmpty)
                  Expanded(
                    child: Text(
                      pm.region != null && pm.region!.isNotEmpty
                          ? '${pm.source!} · ${pm.region!}'
                          : pm.source!,
                      style: TextStyle(color: cs.outline, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                Builder(builder: (context) {
                  final t = _proverbSaveTarget(pm);
                  if (t == null) return const SizedBox(height: 32);
                  final saved = _isSaved('proverb', t.lang, t.text);
                  final l = AppLocalizations.of(context)!;
                  return TextButton.icon(
                    onPressed: saved ? null : () => _saveProverb(pm),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: Icon(
                      saved
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      size: 16,
                    ),
                    label: Text(saved ? l.savedToNotebook : l.saveToNotebook,
                        style: const TextStyle(fontSize: 12)),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── small action chip (Idiom / Words) ────────────────────────────────────

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final active = onTap != null;
    // Material-spec 48×48 minimum touch target wrapped around a visually
    // small chip — the hit area is generous, the visual stays compact.
    return Material(
      color: color.withOpacity(active ? 0.1 : 0.05),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(active ? 0.3 : 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color.withOpacity(active ? 1.0 : 0.4)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color.withOpacity(active ? 1.0 : 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── input container ───────────────────────────────────────────────────────

  Widget _buildInputContainer(ColorScheme cs, double fs) {
    final l = AppLocalizations.of(context)!;
    final hasText = _inputCtrl.text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        children: [
          TextField(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            maxLines: null,
            minLines: 3,
            style: TextStyle(color: cs.onSurface, fontSize: fs),
            decoration: InputDecoration(
              hintText: l.typeOrSpeak,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            ),
          ),
          // Action row below text field
          Container(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                // Voice input — tap: insert at cursor · long-press: replace all.
                // Hidden entirely where speech_to_text has no implementation
                // (Windows/Linux) — a dead mic button reads as "broken".
                if (VoiceService.isSupportedPlatform)
                  GestureDetector(
                    onLongPress: _isListening ? null : _longPressVoice,
                    child: IconButton(
                      onPressed: _toggleVoice,
                      icon: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        size: 22,
                        color: _isListening ? cs.error : cs.primary,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: _isListening
                            ? cs.error.withOpacity(0.1)
                            : cs.primary.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      tooltip: _isListening ? l.tooltipStop : l.tooltipDictate,
                    ),
                  ),
                if (_isListening)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      l.listening,
                      style: TextStyle(color: cs.error, fontSize: 12),
                    ),
                  ),
                const Spacer(),
                // Idiom + Words — fixed location, appear when input has enough
                // text to be worth searching. Idiom works on single words too
                // (e.g. "блестит" → "all that glitters is not gold").
                if (_inputCtrl.text.trim().length >= 3) ...[
                  _buildActionChip(
                    icon: Icons.travel_explore_rounded,
                    label: l.chipIdiom,
                    color: cs.tertiary,
                    onTap: _proverbLoading ? null : _searchProverb,
                  ),
                  const SizedBox(width: 4),
                  // Cultural context via Claude/ChatGPT: origin of a quote,
                  // history of an idiom, connotations, real analogs.
                  _buildActionChip(
                    icon: Icons.account_balance_rounded,
                    label: l.chipContext,
                    color: cs.primary,
                    onTap: _contextLoading ? null : _fetchCulturalContext,
                  ),
                  const SizedBox(width: 4),
                  // Words breakdown only makes sense for multi-word phrases
                  if (_inputCtrl.text.trim().contains(' ')) ...[
                    _buildActionChip(
                      icon: Icons.segment_rounded,
                      label: l.chipWords,
                      color: cs.secondary,
                      onTap: _wbwLoading ? null : _wordByWordBreakdown,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
                // Clear button — only when there's text
                if (hasText)
                  IconButton(
                    onPressed: _clearAll,
                    icon: Icon(Icons.clear_rounded, size: 20, color: cs.outline),
                    tooltip: l.tooltipClear,
                  ),
              ],
            ),
          ),
          if (_loading)
            LinearProgressIndicator(
              minHeight: 2,
              color: cs.primary,
              backgroundColor: cs.outline.withOpacity(0.2),
            ),
        ],
      ),
    );
  }

  // ── result card ───────────────────────────────────────────────────────────

  Widget _buildResultCard(ColorScheme cs, double fs) {
    final l = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: cs.error, fontSize: 13),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    _result,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: fs + 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_notebookCandidate() case final c?)
                  IconButton(
                    onPressed: _isSaved(c.kind, c.lang, c.text)
                        ? null
                        : _saveResultToNotebook,
                    visualDensity: VisualDensity.compact,
                    tooltip: _isSaved(c.kind, c.lang, c.text)
                        ? l.savedToNotebook
                        : l.saveToNotebook,
                    icon: Icon(
                      _isSaved(c.kind, c.lang, c.text)
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      size: 20,
                      color: cs.primary,
                    ),
                  ),
                if (_result.isNotEmpty)
                  GestureDetector(
                    onTap: _copyResult,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 8),
                      child: Icon(Icons.copy_rounded, size: 18, color: cs.primary),
                    ),
                  ),
              ],
            ),
            // Translator attribution (Idiom/Words are now in the input action strip)
            if (_translatorName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l.viaProvider(_translatorName),
                style: TextStyle(color: cs.outline, fontSize: 11),
              ),
            ],
            // Not the word you meant? Pick it. Where does it come from?
            if (_result.isNotEmpty && !_loading)
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _openWordChoice,
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: Text(l.chipChoice,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  if (_originTerm() case final o?)
                    TextButton.icon(
                      onPressed: () =>
                          EtymologyScreen.open(context, o.text, o.lang),
                      icon: const Icon(Icons.history_edu_rounded, size: 16),
                      label: Text(l.chipOrigin,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),

            // Word-by-word result
            if (_wbwLoading)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.secondary)),
                    const SizedBox(width: 8),
                    Text(l.breakingDown, style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12)),
                  ],
                ),
              ),
            if (_wordByWord != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.secondary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.secondary.withOpacity(0.2)),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _wordByWord!.map((wp) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.outline.withOpacity(0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(wp.source, style: TextStyle(color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(wp.target, style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontSize: 11)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ],

            // Proverb search results
            if (_proverbLoading)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.tertiary)),
                    const SizedBox(width: 8),
                    Text(l.searchingProverbs, style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 12)),
                  ],
                ),
              ),
            if (_proverbResults != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.tertiary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.tertiary.withOpacity(0.2)),
                ),
                child: _proverbResults!.isEmpty
                    ? Text(
                        l.noProverbsFound,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 12),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: count + hint
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(Icons.travel_explore_rounded,
                                    size: 14, color: cs.tertiary),
                                const SizedBox(width: 4),
                                Text(
                                  l.idiomsFoundHeader(_proverbResults!.length,
                                      _langChipName(_tgtLang)),
                                  style: TextStyle(color: cs.tertiary, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          ...(_proverbResults!.map((pm) => _buildProverbRow(pm, cs))),
                        ],
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── own-text check card ──────────────────────────────────────────────────

  Widget _buildOwnCheckCard(ColorScheme cs, double fs) {
    final l = AppLocalizations.of(context)!;
    final langName = _langChipName(_cfg.learningLang);
    final r = _ownCheck;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(l.ownTextCheckTitle(langName),
                  style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (_ownChecking)
                Expanded(
                  child: Text(l.ownTextChecking,
                      style: TextStyle(color: cs.outline, fontSize: 12)),
                )
              else if (r != null)
                Expanded(
                  child: Text(
                    r.fixes.isEmpty
                        ? l.ownTextPerfect
                        : l.ownTextFixes(r.fixes.length),
                    style: TextStyle(
                        color: r.fixes.isEmpty ? cs.tertiary : cs.onSurface,
                        fontSize: 12),
                  ),
                )
              else
                const Spacer(),
              if (r != null)
                Flexible(
                  child: Text(r.backend,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.outline, fontSize: 10)),
                ),
            ],
          ),
          if (_ownCheckError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_ownCheckError!,
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
          if (r != null && r.fixes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final f in r.fixes) _buildOwnFixRow(f, cs, l),
            if (!r.trustworthy)
              Text(l.notRecordedLocal,
                  style: TextStyle(color: cs.outline, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _buildOwnFixRow(CorrectionFix f, ColorScheme cs, AppLocalizations l) {
    final id = _ownFixIds[f];
    final rejected = id != null && _rejectedFixIds.contains(id);
    final upgrade = f.severity == 'upgrade';
    final title = constructionTitle(f.construction == 'other' ? '' : f.construction);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: rejected ? 0.45 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(f.original,
                    style: TextStyle(
                      color: upgrade ? cs.outline : cs.error,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough,
                    )),
                Icon(Icons.arrow_forward_rounded, size: 14, color: cs.outline),
                Text(f.fixed.isEmpty ? l.removeWordLabel : f.fixed,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (upgrade)
                  Text('· ${l.upgradeLabel}',
                      style: TextStyle(color: cs.outline, fontSize: 11))
                else if (title.isNotEmpty)
                  Text('· $title',
                      style: TextStyle(color: cs.outline, fontSize: 11)),
              ],
            ),
            if (f.reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(f.reason,
                    style: TextStyle(
                        color: cs.onSurface.withOpacity(0.8), fontSize: 12)),
              ),
            if (id != null && !rejected)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _rejectOwnFix(f),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text(l.notAnError, style: const TextStyle(fontSize: 11)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── cultural context card ────────────────────────────────────────────────

  Widget _buildContextCard(ColorScheme cs, double fs) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outline)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_rounded, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text(AppLocalizations.of(context)!.culturalContext,
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Flexible(
                  child: Text(
                      ref.read(culturalContextProvider).lastBackend ??
                          ref.read(culturalContextProvider).providerName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.outline, fontSize: 10)),
                ),
              ],
            ),
          ),
          if (_contextLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_culturalContext != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                _culturalContext!,
                style: TextStyle(color: cs.onSurface, fontSize: fs - 1, height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  // ── dictionary card (all meanings by PoS) ────────────────────────────────

  Widget _buildDictCard(ColorScheme cs) {
    final meaningCount = _dictMeanings?.fold<int>(0, (n, g) => n + g.translations.length) ?? 0;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsed by default — an always-open wall of meanings pushed the
          // actual translation off screen (information overload).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _dictExpanded = !_dictExpanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: _dictExpanded
                  ? BoxDecoration(
                      border: Border(bottom: BorderSide(color: cs.outline)),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(Icons.library_books_rounded, size: 14, color: cs.secondary),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context)!.allMeanings,
                      style: TextStyle(color: cs.secondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  if (meaningCount > 0) ...[
                    const SizedBox(width: 6),
                    Text('($meaningCount)', style: TextStyle(color: cs.outline, fontSize: 11)),
                  ],
                  const Spacer(),
                  Icon(
                    _dictExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16, color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_dictLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_dictMeanings != null && _dictExpanded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _dictMeanings!.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (g.pos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            g.pos,
                            style: TextStyle(color: cs.primary, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ...g.translations.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 2),
                        child: Text(
                          '${e.key + 1}. ${e.value}',
                          style: TextStyle(color: cs.onSurface, fontSize: 13),
                        ),
                      )),
                    ],
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── collapsible grammar card ────────────────────────────────────────────

  Widget _buildCollapsibleGrammar(
    ColorScheme cs,
    LinguisticInfo info,
    String word,
    bool expanded,
    ValueChanged<bool> onToggle,
  ) {
    final langLabel = localizedLangName(
        info.lang, Localizations.localeOf(context).languageCode);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        children: [
          // Tappable header
          GestureDetector(
            onTap: () => onToggle(!expanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded, size: 14, color: cs.outline),
                  const SizedBox(width: 6),
                  Text(
                    word.isNotEmpty
                        ? '"$word"'
                        : AppLocalizations.of(context)!.grammar,
                    style: TextStyle(color: cs.outline, fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  Text('($langLabel)', style: TextStyle(color: cs.outline, fontSize: 10)),
                  const Spacer(),
                  Text(info.source, style: TextStyle(color: cs.outline, fontSize: 10)),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16, color: cs.outline,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: cs.outline),
            Padding(
              padding: const EdgeInsets.all(14),
              child: _buildLingContent(info, cs),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLingContent(LinguisticInfo info, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tags: PoS, gender, plural
        if (info.partOfSpeech.isNotEmpty ||
            info.gender.isNotEmpty ||
            info.plural.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (info.partOfSpeech.isNotEmpty)
                _tag(info.partOfSpeech, cs.primary.withOpacity(0.15), cs.primary),
              if (info.gender.isNotEmpty)
                _tag(info.gender, cs.error.withOpacity(0.15), cs.error),
              if (info.plural.isNotEmpty)
                _tag(
                  AppLocalizations.of(context)!.pluralTag(info.plural),
                  Colors.transparent,
                  cs.outline,
                  border: cs.outline,
                ),
            ],
          ),

        // Meanings
        if (info.meanings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...info.meanings
              .take(3)
              .toList()
              .asMap()
              .entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${e.key + 1}. ${e.value}',
                      style: TextStyle(color: cs.onSurface, fontSize: 13),
                    ),
                  )),
        ],

        // Etymology
        if (info.etymology.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${AppLocalizations.of(context)!.etymLabel} ',
                  style: TextStyle(color: cs.primary, fontSize: 11)),
              Expanded(
                child: Text(
                  info.etymology,
                  style: TextStyle(color: cs.outline, fontSize: 11),
                ),
              ),
            ],
          ),
        ],

        // Example
        if (info.examples.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '"${info.examples.first}"',
            style: TextStyle(
              color: cs.outline,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],

        // Note
        if (info.note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            info.note,
            style: TextStyle(color: cs.tertiary, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _tag(String label, Color bg, Color fg, {Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }
}
