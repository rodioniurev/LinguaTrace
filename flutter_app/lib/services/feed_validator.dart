/// Deterministic checks for one model-written feed item (a [FeedDraft]).
///
/// The model is good at prose and unreliable at bookkeeping: it claims a
/// target it never used, "rounds" a number, invents a spokesperson, copies
/// the lead or miscounts. Each rule here is cheap and explainable, and each
/// violation is one short, specific sentence that FeedComposer sends back to
/// the model for a single repair round — so messages name the target or the
/// source and quote the offending words.
///
///   V1  story sources cited; headline and body present
///   V2  body length within [0.8·min, 1.2·max] words
///   V3  every required target used, or skipped with a reason
///   V4  target spans located in the body (UTF-16 offsets for the UI)
///   V5  each form really realises its target; a mistake's wrong form is absent
///   V6  numbers, multi-word names and quotes come from the sources
///   V7  at most 6 consecutive words shared with any source title or lead
///   V8  the outlet is named in the body
///   V9  the text is written in the right script
///   V10 tasks are well-formed and answerable from the body
///
/// The static helpers ([fold], [answerMatches], [realises], [locate], …) are
/// pure and shared with the UI, so grading and validation agree.
library;

import 'dart:math' as math;

import '../core/mistake_forms.dart' as mf;
import '../models/feed.dart';
import '../models/news_article.dart';

class FeedValidator {
  const FeedValidator();

  /// Task kinds the feed screen can render and grade.
  static const taskKinds = {'cloze', 'choice', 'rephrase', 'retell'};

  /// Longest run of consecutive words the text may share with one source
  /// title or lead (system prompt rule 4).
  static const maxSharedRun = 6;

  /// Sources are referred to as 'S1', 'S2', … = index + 1 in [sources];
  /// targets by their [FeedTargetSpec.id]. Spans in the report are sorted,
  /// non-overlapping and carry the given target id and the exact body text.
  ValidationReport check(
    FeedDraft d,
    List<NewsArticle> sources,
    List<FeedTargetSpec> targets, {
    String lang = 'es',
    int minWords = 80,
    int maxWords = 220,
  }) {
    final v = <String>[];
    final srcs = [
      for (var i = 0; i < sources.length; i++) _Source(i + 1, sources[i]),
    ];
    final byId = <String, FeedTargetSpec>{};
    for (final t in targets) {
      byId.putIfAbsent(_idKey(t.id), () => t);
    }
    final headline = d.headline.trim();
    final body = d.body;

    // V1 — which stories the item retells, and that there is text to check.
    final cited = _checkStoryIds(d.storySourceIds, srcs, v);
    if (headline.isEmpty) v.add('headline is empty');
    if (body.trim().isEmpty) {
      v.add('body is empty');
      _checkBookkeeping(d, byId, v);
      return ValidationReport(_dedupe(v), const []);
    }
    // Facts must come from the cited stories: a number borrowed from another
    // story is a wrong fact even though it is "in the sources". With no valid
    // id (already a V1 violation) fall back to everything the model saw.
    final grounding = cited.isEmpty ? srcs : cited;
    final uncited = [
      for (final s in srcs)
        if (!grounding.contains(s)) s
    ];

    // V2 — the band is wider than the requested range: models count words
    // loosely, and a slightly short item is still a useful item.
    final n = wordCount(body);
    final lo = minWords * 8 ~/ 10;
    final hi = (maxWords * 12 + 9) ~/ 10;
    if (n < lo || n > hi) {
      v.add('body has $n words; it must have $lo–$hi '
          '(aim for $minWords–$maxWords)');
    }

    // V3
    _checkBookkeeping(d, byId, v);

    // V4 + V5 — models are unreliable at offsets, so we find the form
    // ourselves; and a claimed use must really contain the expression.
    final spans = <FeedSpan>[];
    // Words of each claimed use, and the targets whose use is already
    // reported as wrong (V10 does not pile follow-up errors on them).
    final claimed = <String, Set<String>>{};
    final faulty = <String>{};
    for (final u in d.targetsUsed) {
      final t = byId[_idKey(u.targetId)];
      if (t == null) continue; // unknown target: reported by V3
      final form = u.formUsed.trim();
      final before = v.length;
      if (form.isEmpty) {
        v.add('${t.id} form_used is empty; give the exact words of body '
            'that realise «${t.canonical.trim()}»');
        faulty.add(_idKey(t.id));
        continue;
      }
      (claimed[_idKey(t.id)] ??= <String>{}).addAll(words(form));
      final at = locate(body, form, occurrence: u.occurrence);
      if (at == null) {
        v.add("${t.id} form_used '$form' not found in body");
      } else {
        spans.add(FeedSpan(t.id, at.$1, at.$2, body.substring(at.$1, at.$2)));
      }
      _checkRealisation(t, form, v);
      if (v.length > before) faulty.add(_idKey(t.id));
    }
    final kept = _dropOverlaps(spans, v);
    _checkWrongForms(headline, body, byId.values, v);

    // V6 — grounded facts. Target spans are exempt: an idiom is not a fact.
    final inTargets = [for (final s in kept) (s.start, s.end)];
    final quotes = _quoteRanges(body);
    final headlineQuotes = _quoteRanges(headline);
    _checkNumbers('', body, inTargets, grounding, uncited, v);
    _checkNumbers('headline: ', headline, const [], grounding, uncited, v);
    _checkNames(body, inTargets, grounding, uncited, byId.values, v);
    _checkQuotes('', body, quotes, inTargets, grounding, uncited, v);
    _checkQuotes('headline: ', headline, headlineQuotes, const [], grounding,
        uncited, v);

    // V7 — retold, not copied (checked against every source shown).
    _checkCopy('', body, quotes, srcs, v);
    _checkCopy('headline: ', headline, headlineQuotes, srcs, v);
    _checkOwnHeadline(headline, srcs, v);

    // V8, V9, V10
    _checkAttribution(body, grounding, v);
    _checkScript(headline, body, lang, v);
    _checkTasks(d.tasks, body, byId, claimed, faulty, v);

    return ValidationReport(_dedupe(v), kept);
  }

  // ─────────────────────────────────────────── V1 sources

  static final _sourceIdRe = RegExp(r'^\s*[sS]?\s*(\d{1,4})\s*$');

  /// The cited sources, in citation order. Lenient about 's1' / '1' because
  /// FeedComposer resolves ids the same way.
  static List<_Source> _checkStoryIds(
      List<String> ids, List<_Source> srcs, List<String> v) {
    final given = switch (srcs.length) {
      0 => 'no sources were given',
      1 => 'given: S1',
      _ => 'given: S1–S${srcs.length}',
    };
    if (ids.isEmpty) {
      v.add('story_source_ids is empty; list the sources the story is '
          'based on ($given)');
      return const [];
    }
    final cited = <_Source>[];
    for (final raw in ids) {
      final m = _sourceIdRe.firstMatch(raw);
      final k = m == null ? null : int.tryParse(m[1]!);
      if (k == null || k < 1 || k > srcs.length) {
        v.add("story_source_ids has unknown id '$raw' ($given)");
      } else if (!cited.contains(srcs[k - 1])) {
        cited.add(srcs[k - 1]);
      }
    }
    return cited;
  }

  // ─────────────────────────────────────────── V3 targets used / skipped

  static void _checkBookkeeping(
      FeedDraft d, Map<String, FeedTargetSpec> byId, List<String> v) {
    final given = byId.isEmpty
        ? 'no targets were given'
        : 'given: ${byId.values.map((t) => t.id).join(', ')}';
    final used = <String>{};
    for (final u in d.targetsUsed) {
      final t = byId[_idKey(u.targetId)];
      if (t == null) {
        v.add("targets_used has unknown target '${u.targetId}' ($given)");
      } else {
        used.add(t.id);
      }
    }
    final reasons = <String, String>{};
    for (final (id, reason) in d.skipped) {
      final t = byId[_idKey(id)];
      if (t == null) continue;
      final r = reason.trim();
      if (r.isNotEmpty || !reasons.containsKey(t.id)) reasons[t.id] = r;
    }
    final skippedRequired = <String>[];
    for (final t in byId.values) {
      if (!t.required || used.contains(t.id)) continue;
      final r = reasons[t.id];
      if (r == null) {
        v.add('required target ${t.id} «${t.canonical.trim()}» is neither '
            'in targets_used nor in skipped');
      } else {
        skippedRequired.add(t.id);
        if (r.isEmpty) {
          v.add('skipped target ${t.id} needs a one-sentence reason');
        }
      }
    }
    if (skippedRequired.length > 1) {
      v.add('${skippedRequired.length} required targets skipped '
          '(${skippedRequired.join(', ')}); at most one may be skipped');
    }
  }

  // ─────────────────────────────────────────── V4 spans

  /// Sorted by position; when two overlap the earlier one wins and the
  /// clash is reported (one highlight cannot belong to two targets).
  static List<FeedSpan> _dropOverlaps(List<FeedSpan> spans, List<String> v) {
    final sorted = [...spans]..sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : a.end.compareTo(b.end));
    final kept = <FeedSpan>[];
    for (final s in sorted) {
      if (kept.isNotEmpty) {
        final last = kept.last;
        if (s.targetId == last.targetId &&
            s.start == last.start &&
            s.end == last.end) {
          continue; // the same use listed twice
        }
        if (s.start < last.end) {
          v.add("${s.targetId} form '${s.form}' overlaps ${last.targetId} "
              "form '${last.form}'; each target needs its own words");
          continue;
        }
      }
      kept.add(s);
    }
    return kept;
  }

  /// UTF-16 offsets of the [occurrence]-th (1-based) occurrence of [form] in
  /// [body], or null.
  ///
  /// Exact match first; then a case-, accent- and NFC/NFD-insensitive match
  /// whose offsets are mapped back to the ORIGINAL body (a decomposed "ñ" is
  /// two code units there). Whole-word occurrences are preferred ("leña" in
  /// "leñador" does not count while a whole "leña" exists). An occurrence
  /// beyond the count falls back to the last one: models miscount, and a
  /// highlight on the right expression is still the right highlight.
  static (int, int)? locate(String body, String form, {int occurrence = 1}) {
    final want = occurrence < 1 ? 1 : occurrence;
    final core = _stripEdges(form.trim());
    if (core.isEmpty || body.isEmpty) return null;

    final exact = _occurrences(body, core);
    if (exact.length >= want) return exact[want - 1];

    final map = <int>[];
    final hay = _foldInto(body, map);
    final needle = fold(core);
    final loose = <(int, int)>[
      if (needle.isNotEmpty)
        for (final (s, e) in _occurrences(hay, needle))
          (map[s], e < map.length ? map[e] : body.length),
    ];
    if (loose.length >= want) return loose[want - 1];
    if (exact.isNotEmpty) return exact.last;
    if (loose.isNotEmpty) return loose.last;
    return null;
  }

  static List<(int, int)> _occurrences(String hay, String needle) {
    final all = <(int, int)>[];
    var i = hay.indexOf(needle);
    while (i >= 0) {
      all.add((i, i + needle.length));
      i = hay.indexOf(needle, i + needle.length);
    }
    final whole = [
      for (final o in all)
        if (_boundaryAt(hay, o.$1 - 1) && _boundaryAt(hay, o.$2)) o,
    ];
    return whole.isNotEmpty ? whole : all;
  }

  static bool _boundaryAt(String s, int i) =>
      i < 0 || i >= s.length || !_isWordUnit(s.codeUnitAt(i));

  // ─────────────────────────────────────────── V5 realisation

  static void _checkRealisation(FeedTargetSpec t, String form, List<String> v) {
    final canonical = t.canonical.trim();
    if (canonical.isEmpty) return;
    final have = words(form);
    final keys = _keys(canonical);
    final anchors = t.kind.toLowerCase() == 'mistake' && t.mustContain.isNotEmpty
        ? mf.patternAnchors(canonical, t.mustContain,
            construction: t.construction)
        : const <mf.PatternAnchor>[];
    if (anchors.isNotEmpty) {
      // A pattern mistake: the corrected function word next to its anchor
      // (the governing verb, the noun or number after it) — any «a» or «el»
      // somewhere in the phrase is not the construction.
      if (!realisesPattern(form, canonical, t.mustContain,
          construction: t.construction)) {
        v.add("${t.id} form_used '$form' must reuse the corrected pattern "
            '«$canonical»: ${mf.describeAnchors(anchors)}');
      }
    } else if (keys.isEmpty) {
      // Only function words ("a", "de"): the canonical itself must be there.
      if (_indexOfSeq(have, words(canonical)) < 0) {
        v.add("${t.id} form_used '$form' does not contain «$canonical»");
      }
    } else if (t.kind.toLowerCase() == 'mistake') {
      // The model should reuse the construction around ANOTHER verb or noun
      // ("atreverse a" + pedir instead of + decir), so half is enough.
      final hit = _anyOrderHits(keys, have);
      if (hit * 2 < keys.length) {
        v.add("${t.id} form_used '$form' does not use the construction "
            '«$canonical» (shares $hit of ${keys.length} key words)');
      }
    } else if (_inOrderHits(keys, have) * 10 < keys.length * 7) {
      final missing = [
        for (final k in keys)
          if (!have.any(k.matches)) k.label,
      ];
      v.add(missing.isEmpty
          ? "${t.id} form_used '$form' has the words of «$canonical» "
              'out of order'
          : "${t.id} form_used '$form' does not realise «$canonical» "
              '(missing: ${missing.join(', ')})');
    }
    // The span is highlighted in the text: a whole clause is not a target.
    final size = words(canonical).length;
    if (have.length > math.max(size * 2, size + 5)) {
      v.add('${t.id} form_used is ${have.length} words long; give only the '
          'words that realise «$canonical»');
    }
  }

  /// A mistake target exists because the reader wrote [FeedTargetSpec.wrongForm];
  /// showing it again — even in passing — would reinforce the error.
  static void _checkWrongForms(String headline, String body,
      Iterable<FeedTargetSpec> targets, List<String> v) {
    for (final t in targets) {
      if (t.kind.toLowerCase() != 'mistake' || t.wrongForm.trim().isEmpty) {
        continue;
      }
      // A lone function word ("en", "la") is in every text: nothing to check.
      if (mf.onlyFunctionWords(t.wrongForm)) continue;
      for (final (field, text) in [('body', body), ('headline', headline)]) {
        if (_containsWrongForm(text, t.wrongForm, t.canonical)) {
          v.add("${t.id} the reader's wrong form «${t.wrongForm.trim()}» "
              'appears in the $field; write only the correct '
              '«${t.canonical.trim()}»');
        }
      }
    }
  }

  static bool _containsWrongForm(String text, String wrong, String right) {
    var w = words(wrong);
    var r = words(right);
    var hay = words(text);
    if (w.isEmpty) return false;
    if (_listEq(w, r)) {
      // Accent-only mistake ("esta" for "está"): folding would find the
      // correct form too, so compare with accents kept.
      w = _accentWords(wrong);
      r = _accentWords(right);
      hay = _accentWords(text);
      if (_listEq(w, r)) return false; // case/punctuation only: not visible
    }
    // The wrong form inside the right one ("gente" ⊂ "la gente"): only
    // occurrences outside the right form count.
    if (_indexOfSeq(r, w) >= 0) hay = _maskSeq(hay, r);
    return _indexOfSeq(hay, w) >= 0;
  }

  /// Share of [canonical]'s key words present in [text] (in order unless
  /// [inOrder] is false). 1.0 when the canonical has nothing to check.
  static double coverage(String text, String canonical, {bool inOrder = true}) {
    final (hit, of) = _coverage(text, canonical, inOrder: inOrder);
    return of == 0 ? 1.0 : hit / of;
  }

  /// Does [text] realise [canonical]? Idioms, collocations, proverbs and
  /// words: ≥ 70 % of the key words in order, inflection allowed ("echaron
  /// leña al fuego" ≈ "echar leña al fuego", "no dio su brazo a torcer" ≈
  /// "no dar su brazo a torcer"). Mistakes (`kind: 'mistake'`): ≥ 50 % in
  /// any order — the construction around another verb still counts.
  static bool realises(String text, String canonical, {String kind = 'idiom'}) {
    final mistake = kind.toLowerCase() == 'mistake';
    final (hit, of) = _coverage(text, canonical, inOrder: !mistake);
    if (of == 0) return true;
    return mistake ? hit * 2 >= of : hit * 10 >= of * 7;
  }

  /// Does [text] reuse a pattern mistake: one of the corrected function
  /// words [mustContain] right next to its anchor from [canonical] — after a
  /// form of the governing verb («se atrevieron a»), or before the same noun
  /// or any number («el 26» for «el 18»)? Function words keep their accents
  /// (esta ≠ está).
  static bool realisesPattern(
      String text, String canonical, List<String> mustContain,
      {String construction = ''}) {
    final anchors =
        mf.patternAnchors(canonical, mustContain, construction: construction);
    if (anchors.isEmpty) return false;
    final toks = _accentWords(text);
    bool sameWord(String tok, String fw) =>
        tok == fw || (fw.length >= 4 && tok.startsWith(fw)); // está → están
    for (final a in anchors) {
      for (var j = 0; j < toks.length; j++) {
        if (!sameWord(toks[j], a.word)) continue;
        if (a.before.isNotEmpty && j > 0 && _anchorMatches(a.before, toks[j - 1])) {
          return true;
        }
        if (a.after.isNotEmpty) {
          for (var k = j + 1; k < toks.length && k <= j + 3; k++) {
            if (mf.isFunctionWord(toks[k])) continue;
            if (_anchorMatches(a.after, toks[k])) return true;
            break;
          }
        }
      }
    }
    return false;
  }

  static bool _anchorMatches(String anchor, String word) {
    if (mf.isNumberWord(anchor)) return mf.isNumberWord(word);
    return _KeyMatcher(fold(anchor)).matches(fold(word));
  }

  /// Does [text] use the correct form of a past mistake ([wrong] → [right],
  /// as stored on the learning item)? A pattern must sit at its anchor
  /// ([realisesPattern]); a word-form slip needs the corrected word itself,
  /// accents included («compré», not «compro» or «compre»).
  static bool realisesMistake(String text, String wrong, String right,
      {String construction = ''}) {
    final (w, r) = mf.keyForms(wrong, right);
    if (r.trim().isEmpty) return false;
    final pattern = mf.patternWords(w, r);
    if (pattern.isNotEmpty) {
      return realisesPattern(text, r, pattern, construction: construction);
    }
    final changed = _accentWords(mf.changedWords(w, r).join(' '));
    if (changed.isEmpty) return false;
    final have = _accentWords(text).toSet();
    return changed.every(have.contains);
  }

  /// One predicate for choice options, shared by validation and grading:
  /// case, spacing, punctuation and Unicode form are ignored; accents are
  /// not — «esta» / «está» can be the whole point of the task.
  static bool sameOption(String a, String b) {
    final x = _accentWords(a), y = _accentWords(b);
    if (x.isEmpty || y.isEmpty) {
      // Symbol-only options ("—" = nothing goes here) compare as typed.
      return x.isEmpty && y.isEmpty && a.trim() == b.trim();
    }
    return _listEq(x, y);
  }

  static (int, int) _coverage(String text, String canonical,
      {required bool inOrder}) {
    final keys = _keys(canonical);
    final have = words(text);
    if (keys.isEmpty) {
      final c = words(canonical);
      if (c.isEmpty) return (0, 0);
      return (_indexOfSeq(have, c) >= 0 ? 1 : 0, 1);
    }
    return (
      inOrder ? _inOrderHits(keys, have) : _anyOrderHits(keys, have),
      keys.length,
    );
  }

  /// Key words of a canonical form: folded, without stopwords, dictionary
  /// placeholders ("algo", "alguien", "+ infinitivo") and tokens shorter
  /// than 3 letters. "echar leña al fuego" → [echar, lena, fuego].
  static List<String> significantTokens(String canonical) =>
      [for (final k in _keys(canonical)) k.alternatives.first.key];

  static final _bracketsRe = RegExp(r'\([^)]*\)|\[[^\]]*\]');
  static final _spacesRe = RegExp(r'\s+');

  /// "(le)" / "[algo]" are optional parts; "echar/tirar" are alternatives.
  static List<_Key> _keys(String canonical) {
    final out = <_Key>[];
    final cleaned = canonical.replaceAll(_bracketsRe, ' ');
    for (final chunk in cleaned.split(_spacesRe)) {
      if (chunk.isEmpty) continue;
      if (chunk.contains('/')) {
        final alts = [
          for (final part in chunk.split('/'))
            for (final t in _tokens(part))
              if (_isKeyWord(t.norm)) t,
        ];
        if (alts.isNotEmpty) {
          out.add(_Key(
              alts.first.text, [for (final t in alts) _KeyMatcher(t.norm)]));
        }
      } else {
        for (final t in _tokens(chunk)) {
          if (_isKeyWord(t.norm)) out.add(_Key(t.text, [_KeyMatcher(t.norm)]));
        }
      }
    }
    return out;
  }

  static bool _isKeyWord(String w) =>
      w.length >= 3 && !_stopwords.contains(w) && !_placeholders.contains(w);

  /// Longest in-order matching of keys against words (an LCS: greedy
  /// matching can pair a key with the wrong word and undercount). With
  /// [reverse] (a matcher per word), a word also matches a key that is one
  /// of ITS inflections.
  static int _inOrderHits(List<_Key> keys, List<String> have,
      [List<_KeyMatcher>? reverse]) {
    var prev = List<int>.filled(have.length + 1, 0);
    for (final k in keys) {
      final cur = List<int>.filled(have.length + 1, 0);
      for (var j = 1; j <= have.length; j++) {
        final hit = k.matches(have[j - 1]) ||
            (reverse != null &&
                k.alternatives.any((m) => reverse[j - 1].matches(m.key)));
        final diag = hit ? prev[j - 1] + 1 : 0;
        cur[j] = math.max(diag, math.max(prev[j], cur[j - 1]));
      }
      prev = cur;
    }
    return prev[have.length];
  }

  static int _anyOrderHits(List<_Key> keys, List<String> have) =>
      keys.where((k) => have.any(k.matches)).length;

  // ── Spanish verb morphology for the key matcher ─────────────────────────

  static const _clitics = [
    'selos', 'selas', 'seles', 'selo', 'sela', 'sele', 'nos', 'les', 'los',
    'las', 'se', 'le', 'lo', 'la', 'me', 'te', 'os',
  ];

  /// The infinitive of an (optionally clitic-carrying) infinitive token:
  /// "atreverse" → "atrever", "darle" → "dar"; null for anything else.
  static String? _infinitive(String w) {
    bool isInf(String s) =>
        s.length >= 2 &&
        (s.endsWith('ar') || s.endsWith('er') || s.endsWith('ir'));
    if (isInf(w)) return w;
    for (final c in _clitics) {
      if (w.length > c.length + 1 && w.endsWith(c)) {
        final base = w.substring(0, w.length - c.length);
        if (isInf(base)) return base;
      }
    }
    return null;
  }

  /// Prefixes / exact forms that inflect [inf]: its root (echó ← echar), the
  /// stem-changed root (cierra ← cerrar, pide ← pedir), spelling changes
  /// (saqué, pagué, empecé, conozco, redujo) and irregular stems, also in
  /// compounds (mantuvo ← mantener).
  static void _addVerbPatterns(
      String inf, Set<String> prefixes, Set<String> forms) {
    final ar = inf.endsWith('ar');
    final ir = inf.endsWith('ir');
    final root = inf.substring(0, inf.length - 2);
    final roots = <String>{root};
    final k = _lastStemVowel(root);
    if (k >= 0) {
      String swap(String r) =>
          '${root.substring(0, k)}$r${root.substring(k + 1)}';
      if (root[k] == 'e') {
        roots.add(swap('ie'));
        if (ir) roots.add(swap('i'));
      } else if (root[k] == 'o') {
        roots.add(swap('ue'));
        if (ir) roots.add(swap('u'));
      }
    }
    for (final r in [...roots]) {
      if (r.isEmpty) continue;
      final head = r.substring(0, r.length - 1);
      if (ar) {
        if (r.endsWith('c')) roots.add('${head}qu');
        if (r.endsWith('g')) roots.add('${r}u');
        if (r.endsWith('z')) roots.add('${head}c');
      } else {
        if (r.endsWith('duc')) roots.add('${head}j');
        if (r.endsWith('c')) roots.addAll(['${head}z', '${head}zc']);
        if (r.endsWith('gu')) {
          roots.add(head);
        } else if (r.endsWith('g')) {
          roots.add('${head}j');
        }
      }
    }
    // Shorter roots ("d" of dar, "v" of ver) would match half the language.
    prefixes.addAll(roots.where((r) => r.length >= 3));
    for (final e in _irregularStems.entries) {
      final pre = _compoundPrefix(inf, e.key);
      if (pre != null) prefixes.addAll(e.value.map((p) => '$pre$p'));
    }
    for (final e in _irregularForms.entries) {
      final pre = _compoundPrefix(inf, e.key);
      if (pre != null) forms.addAll(e.value.map((f) => '$pre$f'));
    }
  }

  /// '' when [inf] is [base] itself, the prefix when it is a compound of it
  /// (mantener ← tener), else null. Short bases (dar, ver, ir) never
  /// compound: too many unrelated verbs end in them.
  static String? _compoundPrefix(String inf, String base) {
    if (inf == base) return '';
    if (base.length >= 4 && inf.length > base.length && inf.endsWith(base)) {
      return inf.substring(0, inf.length - base.length);
    }
    return null;
  }

  /// The vowel that diphthongises in stem-changing verbs: the last one of
  /// the root, skipping the silent u of gu/qu (seguir → sigue).
  static int _lastStemVowel(String root) {
    for (var i = root.length - 1; i >= 0; i--) {
      final c = root[i];
      if (!'aeiou'.contains(c)) continue;
      if (c == 'u' && i > 0 && (root[i - 1] == 'g' || root[i - 1] == 'q')) {
        continue;
      }
      return i;
    }
    return -1;
  }

  /// Irregular stems the prefix rule cannot reach (folded, prefixes).
  static const _irregularStems = <String, List<String>>{
    'dar': ['dab', 'dand', 'dar', 'dier', 'diese'],
    'ver': ['vist', 'veia'],
    'ir': ['vay', 'yend'],
    'hacer': ['hag', 'hic', 'hiz', 'hech'],
    'decir': ['dic', 'dij'],
    'poner': ['pus', 'puest'],
    'tener': ['tuv'],
    'venir': ['vin'],
    'poder': ['pud'],
    'querer': ['quis'],
    'saber': ['supier'],
    'caber': ['quep', 'cupier'],
    'traer': ['traj', 'traig'],
    'caer': ['cae', 'cai', 'cay'],
    'oir': ['oy', 'oi'],
    'andar': ['anduv'],
    'jugar': ['jueg'],
    'oler': ['huel'],
    'volver': ['vuelt'],
    'romper': ['rot'],
    'abrir': ['abiert'],
    'cubrir': ['cubiert'],
    'escribir': ['escrit'],
    'morir': ['muert'],
    'valer': ['valg'],
    'salir': ['salg'],
  };

  /// Irregular forms too short to be safe prefixes ("dio" ← dar, "fue" ← ir).
  static const _irregularForms = <String, List<String>>{
    'dar': [
      'da', 'das', 'dan', 'damos', 'di', 'dio', 'diste', 'dimos', 'dieron',
      'doy', 'den', 'dado', 'dada', 'dados', 'dadas',
    ],
    'ver': [
      've', 'ves', 'ven', 'veo', 'vemos', 'vi', 'vio', 'vimos', 'vieron',
      'vea', 'vean', 'vera', 'veran', 'veria', 'verian', 'verse', 'verlo',
      'verla', 'viendo',
    ],
    'ir': [
      'va', 'vas', 'van', 'voy', 'vamos', 'fue', 'fui', 'fueron', 'fuera',
      'fueran', 'fuese', 'iba', 'iban', 'ido', 'ira', 'iran', 'iria',
      'irian', 'irse',
    ],
    'hacer': ['hara', 'haran', 'haria', 'harian'],
    'decir': ['diga', 'digan', 'digo', 'dira', 'diran', 'diria', 'dirian'],
    'saber': ['supo', 'supe', 'sepa', 'sepan'],
    'reir': [
      'rie', 'rien', 'rio', 'rieron', 'reia', 'reian', 'reido', 'riendo',
      'reirse',
    ],
    'leer': [
      'lee', 'leen', 'leyo', 'leyeron', 'leia', 'leian', 'leido', 'leyendo',
      'lea', 'lean',
    ],
    'freir': ['frie', 'frien', 'frito', 'frita', 'fritos', 'fritas'],
  };

  // ─────────────────────────────────────────── V6 facts

  static void _checkNumbers(String prefix, String text, List<(int, int)> skip,
      List<_Source> grounding, List<_Source> uncited, List<String> v) {
    for (final n in _numberMentions(text)) {
      if (_overlapsAny(n.start, n.end, skip)) continue;
      if (grounding.any((s) => s.numberKeys.any(n.keys.contains))) continue;
      final other = uncited.where((s) => s.numberKeys.any(n.keys.contains));
      v.add(other.isEmpty
          ? '${prefix}number ${n.display} not in any source'
          : '${prefix}number ${n.display} appears only in ${other.first.id}, '
              'which is not in story_source_ids');
    }
  }

  /// Canonical keys of every number in [text]: thousands separators
  /// normalised ("180.000" = "180 000" = "180000"), decimal comma or point
  /// ("1,5" = "1.5"), scale words applied ("1,5 millones" = "1500000"),
  /// clock times ("10.30" = "10:30"). Ambiguous forms get every reading
  /// ("2.500" is 2500 or 2.5) — grounding only needs one key in common.
  /// With [includeWords], also number words ("tres", "medio millón").
  static Set<String> numberKeys(String text, {bool includeWords = false}) => {
        for (final n in _numberMentions(text)) ...n.keys,
        if (includeWords) ..._numberWordKeys(text),
      };

  static final _numRe = RegExp(r'\d+(?:(?:[.,:]|[ \u00A0\u202F\u2009])\d+)*');
  static final _spaceSepRe = RegExp('[ \u00A0\u202F\u2009]');
  static final _thousandsHeadRe = RegExp(r'^\d{1,3}(?: \d{3})*$');
  static final _threeDigitsRe = RegExp(r'^\d{3}$');
  static final _percentRe = RegExp('^[ \u00A0\u202F]?%');

  static List<_Num> _numberMentions(String text) {
    final out = <_Num>[];
    for (final m in _numRe.allMatches(text)) {
      // A space groups thousands only in the "180 000" shape: "en 2024 180
      // casos" is two numbers.
      var cur = '';
      var curStart = m.start;
      var pos = m.start;
      for (final part in m[0]!.split(_spaceSepRe)) {
        if (cur.isEmpty) {
          cur = part;
          curStart = pos;
        } else if (_thousandsHeadRe.hasMatch(cur) &&
            _threeDigitsRe.hasMatch(part)) {
          cur = '$cur $part';
        } else {
          out.add(_mention(text, cur, curStart));
          cur = part;
          curStart = pos;
        }
        pos += part.length + 1;
      }
      if (cur.isNotEmpty) out.add(_mention(text, cur, curStart));
    }
    return out;
  }

  static _Num _mention(String text, String token, int start) {
    final end = start + token.length;
    final keys = _numKeys(token.replaceAll(' ', ''));
    final scale = _scaleAfter(text, end);
    if (scale > 0) {
      keys.addAll([
        for (final k in keys)
          if (!k.startsWith('t') && !k.startsWith('r')) _shift(k, scale),
      ]);
    }
    var display = text.substring(start, end);
    if (_percentRe.hasMatch(text.substring(end))) display += '%';
    return _Num(display, start, end, keys);
  }

  static final _decimalSepRe = RegExp('[.,]');

  static Set<String> _numKeys(String token) {
    final keys = <String>{};
    if (token.contains(':')) {
      final p = token.split(':');
      if (p.length == 2 &&
          p[0].length <= 2 &&
          p[1].length == 2 &&
          !p[0].contains(_decimalSepRe) &&
          !p[1].contains(_decimalSepRe)) {
        keys.add('t${int.parse(p[0])}:${p[1]}');
      } else {
        keys.add('r$token');
      }
      return keys;
    }
    final groups = token.split(_decimalSepRe);
    final seps = [for (final m in _decimalSepRe.allMatches(token)) m[0]!];
    if (seps.isEmpty) return {_canonNum(token)};
    // Every separator groups thousands: "180.000", "1,234,567".
    if (seps.toSet().length == 1 &&
        groups.first.length <= 3 &&
        groups.skip(1).every((g) => g.length == 3)) {
      keys.add(_canonNum(groups.join()));
    }
    // The last separator is the decimal one: "1,5", "1.234,5", "2.5".
    final last = seps.last;
    final earlier = seps.sublist(0, seps.length - 1);
    if (earlier.isEmpty ||
        (earlier.toSet().length == 1 &&
            earlier.first != last &&
            groups.first.length <= 3 &&
            groups.sublist(1, groups.length - 1).every((g) => g.length == 3))) {
      keys.add(_canonNum(
          '${groups.sublist(0, groups.length - 1).join()}.${groups.last}'));
    }
    // A clock time written with a dot: "a las 10.30".
    if (seps.length == 1 &&
        last == '.' &&
        groups[0].length <= 2 &&
        groups[1].length == 2 &&
        int.parse(groups[0]) <= 24 &&
        int.parse(groups[1]) < 60) {
      keys.add('t${int.parse(groups[0])}:${groups[1]}');
    }
    if (keys.isEmpty) keys.add('r${groups.join('.')}');
    return keys;
  }

  static final _leadingZerosRe = RegExp(r'^0+');
  static final _trailingZerosRe = RegExp(r'0+$');

  /// "007" → "7", "1.50" → "1.5", "180.000" (as a decimal) → "180".
  static String _canonNum(String s) {
    final dot = s.indexOf('.');
    var whole =
        (dot < 0 ? s : s.substring(0, dot)).replaceFirst(_leadingZerosRe, '');
    final frac =
        dot < 0 ? '' : s.substring(dot + 1).replaceFirst(_trailingZerosRe, '');
    if (whole.isEmpty) whole = '0';
    return frac.isEmpty ? whole : '$whole.$frac';
  }

  /// Multiplies a canonical number by 10^[places] without floating point.
  static String _shift(String canon, int places) {
    final dot = canon.indexOf('.');
    final whole = dot < 0 ? canon : canon.substring(0, dot);
    final frac = dot < 0 ? '' : canon.substring(dot + 1);
    final digits = whole + frac;
    final point = whole.length + places;
    if (point >= digits.length) return _canonNum(digits.padRight(point, '0'));
    return _canonNum(
        '${digits.substring(0, point)}.${digits.substring(point)}');
  }

  static const _scaleWords = <String, int>{
    'mil': 3, 'millon': 6, 'millones': 6, 'millardo': 9, 'millardos': 9,
    'billon': 12, 'billones': 12, 'thousand': 3, 'million': 6,
    'millions': 6, 'billion': 9, 'billions': 9, 'trillion': 12,
    'trillions': 12, 'тыс': 3, 'тысяча': 3, 'тысячи': 3, 'тысяч': 3,
    'млн': 6, 'миллион': 6, 'миллиона': 6, 'миллионов': 6, 'млрд': 9,
    'миллиард': 9, 'миллиарда': 9, 'миллиардов': 9, 'трлн': 12,
  };

  /// Power of ten of a scale word right after a number ("mil millones" = 9).
  static int _scaleAfter(String text, int end) {
    bool space(int c) => c == 0x20 || c == 0xA0 || c == 0x202F;
    bool letter(int c) => _isWordUnit(c) && !_isDigit(c);
    var i = end;
    while (i < text.length && space(text.codeUnitAt(i))) {
      i++;
    }
    final a = i;
    while (i < text.length && letter(text.codeUnitAt(i))) {
      i++;
    }
    if (i == a) return 0;
    final w1 = fold(text.substring(a, i));
    if (i < text.length && text.codeUnitAt(i) == 0x2E) i++; // "tys." "mill."
    var j = i;
    while (j < text.length && space(text.codeUnitAt(j))) {
      j++;
    }
    final b = j;
    while (j < text.length && letter(text.codeUnitAt(j))) {
      j++;
    }
    if (w1 == 'mil' && b > i && j > b) {
      final w2 = fold(text.substring(b, j));
      if (w2 == 'millones' || w2 == 'millon') return 9;
    }
    return _scaleWords[w1] ?? 0;
  }

  static const _numberWords = <String, String>{
    'un': '1', 'una': '1', 'uno': '1', 'medio': '0.5', 'media': '0.5',
    'dos': '2', 'tres': '3', 'cuatro': '4', 'cinco': '5', 'seis': '6',
    'siete': '7', 'ocho': '8', 'nueve': '9', 'diez': '10', 'once': '11',
    'doce': '12', 'trece': '13', 'catorce': '14', 'quince': '15',
    'dieciseis': '16', 'diecisiete': '17', 'dieciocho': '18',
    'diecinueve': '19', 'veinte': '20', 'treinta': '30', 'cuarenta': '40',
    'cincuenta': '50', 'sesenta': '60', 'setenta': '70', 'ochenta': '80',
    'noventa': '90', 'cien': '100', 'ciento': '100', 'doscientos': '200',
    'doscientas': '200', 'trescientos': '300', 'trescientas': '300',
    'quinientos': '500', 'quinientas': '500', 'mil': '1000',
    'millon': '1000000',
    'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
    'eleven': '11', 'twelve': '12', 'twenty': '20', 'thirty': '30',
    'fifty': '50', 'hundred': '100', 'thousand': '1000',
    'million': '1000000',
    'один': '1', 'одна': '1', 'два': '2', 'две': '2', 'три': '3',
    'четыре': '4', 'пять': '5', 'шесть': '6', 'семь': '7', 'восемь': '8',
    'девять': '9', 'десять': '10', 'сто': '100', 'тысяча': '1000',
  };

  /// Sources often spell small numbers out; the retelling may use digits.
  static Iterable<String> _numberWordKeys(String text) sync* {
    for (final t in _tokens(text)) {
      final n = _numberWords[t.norm];
      if (n == null) continue;
      yield n;
      final scale = _scaleAfter(text, t.end);
      if (scale > 0) yield _shift(n, scale);
    }
  }

  static Set<String> _sourceNumberKeys(NewsArticle a) {
    final keys = <String>{
      for (final text in [a.title, a.lead, a.outlet])
        ...numberKeys(text, includeWords: true),
    };
    // The model sees each story's date: "el 26 de septiembre" is grounded.
    final p = a.publishedAt;
    if (p != null) {
      for (final d in [p, p.toLocal(), p.toUtc()]) {
        keys.addAll(['${d.day}', '${d.month}', '${d.year}']);
      }
    }
    return keys;
  }

  static const _nameLinks = {
    'de', 'del', 'la', 'las', 'los', 'el', 'da', 'das', 'do', 'dos', 'di',
    'du', 'van', 'von', 'der', 'den', 'le', 'of',
  };

  /// Capitalised in English running text without being names.
  static const _calendarWords = {
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
    'sunday', 'january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december',
  };

  /// Multi-word names ("Isabel Rodríguez", "Sindicato de Inquilinas") are
  /// where invented people and bodies show up. Word by word, so "el
  /// presidente Sánchez" is fine when the lead says "Pedro Sánchez"; a
  /// shared 5-letter prefix absorbs inflection (Путина ≈ Путин).
  static void _checkNames(
      String body,
      List<(int, int)> skip,
      List<_Source> grounding,
      List<_Source> uncited,
      Iterable<FeedTargetSpec> targets,
      List<String> v) {
    final toks = _tokens(body);
    final targetWords = {for (final t in targets) ...words(t.canonical)};
    var i = 0;
    while (i < toks.length) {
      if (!_isCapitalised(toks[i].text)) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < toks.length &&
          _onlySpaces(body, toks[j - 1].end, toks[j].start) &&
          (_isCapitalised(toks[j].text) || _nameLinks.contains(toks[j].text))) {
        j++;
      }
      var run = toks.sublist(i, j);
      i = j;
      // A capital at the start of a sentence says nothing about a name.
      if (_sentenceInitial(body, run.first.start)) run = run.sublist(1);
      while (run.isNotEmpty && !_isCapitalised(run.first.text)) {
        run = run.sublist(1);
      }
      while (run.isNotEmpty && !_isCapitalised(run.last.text)) {
        run = run.sublist(0, run.length - 1);
      }
      final caps = [
        for (final t in run)
          if (_isCapitalised(t.text)) t,
      ];
      if (caps.length < 2) continue;
      if (_overlapsAny(run.first.start, run.last.end, skip)) continue;
      final unknown = [
        for (final t in caps)
          if (!targetWords.contains(t.norm) &&
              !_calendarWords.contains(t.norm) &&
              !grounding.any((s) => s.knowsName(t.norm)))
            t,
      ];
      if (unknown.isEmpty) continue;
      final name = body.substring(run.first.start, run.last.end);
      final other =
          uncited.where((s) => unknown.every((t) => s.knowsName(t.norm)));
      v.add(other.isEmpty
          ? "name '$name' not in any source "
              '(unknown: ${unknown.map((t) => t.text).join(', ')})'
          : "name '$name' appears only in ${other.first.id}, which is not "
              'in story_source_ids');
    }
  }

  /// A quote attributes words to a real person: they must exist verbatim.
  static void _checkQuotes(
      String prefix,
      String text,
      List<(int, int)> quotes,
      List<(int, int)> skip,
      List<_Source> grounding,
      List<_Source> uncited,
      List<String> v) {
    for (final (a, b) in quotes) {
      final seg = text.substring(a, b).trim();
      final w = words(seg);
      if (w.length < 3 || _overlapsAny(a, b, skip)) continue;
      if (grounding.any((s) => s.hasSequence(w))) continue;
      final other = uncited.where((s) => s.hasSequence(w));
      v.add(other.isEmpty
          ? '${prefix}quote «${_clip(seg)}» is not verbatim in any source; '
              'quote only exact words from a source'
          : '${prefix}quote «${_clip(seg)}» appears only in '
              '${other.first.id}, which is not in story_source_ids');
    }
  }

  /// Inner ranges (without the marks) of «…», “…” and "…" segments.
  static List<(int, int)> _quoteRanges(String s) {
    final out = <(int, int)>[];
    void pairs(String open, String close) {
      var from = 0;
      while (true) {
        final a = s.indexOf(open, from);
        if (a < 0) return;
        final b = s.indexOf(close, a + 1);
        if (b < 0) return;
        out.add((a + 1, b));
        from = b + 1;
      }
    }

    pairs('«', '»');
    pairs('“', '”');
    pairs('"', '"');
    return out;
  }

  // ─────────────────────────────────────────── V7 copying

  /// Longest run of consecutive words (case, accents and punctuation
  /// ignored) that [a] and [b] share.
  static int longestSharedRun(String a, String b) =>
      _longestRun(words(a), words(b)).$1;

  static void _checkCopy(String prefix, String text, List<(int, int)> quotes,
      List<_Source> srcs, List<String> v) {
    final toks = _tokens(text);
    if (toks.isEmpty) return;
    // Quoted words are checked for being verbatim (V6), not for copying.
    final seq = [
      for (var k = 0; k < toks.length; k++)
        _insideAny(toks[k].start, quotes) ? '\u0000$k' : toks[k].norm,
    ];
    for (final s in srcs) {
      var best = 0, at = 0;
      var part = '';
      for (final (name, ws) in [
        ('title', s.titleWords),
        ('lead', s.leadWords)
      ]) {
        final (len, start) = _longestRun(seq, ws);
        if (len > best) {
          best = len;
          at = start;
          part = name;
        }
      }
      if (best > maxSharedRun) {
        final copied = text.substring(toks[at].start, toks[at + best - 1].end);
        v.add("$prefix$best consecutive words copied from ${s.id} $part: "
            "'${_clip(copied)}'; retell it in your own words");
      }
    }
  }

  static void _checkOwnHeadline(
      String headline, List<_Source> srcs, List<String> v) {
    final h = words(headline);
    if (h.isEmpty) return;
    for (final s in srcs) {
      if (_listEq(h, s.titleWords)) {
        v.add('headline repeats the ${s.id} title; write your own headline');
        return;
      }
    }
  }

  /// (length, start in [a]) of the longest common run of tokens.
  static (int, int) _longestRun(List<String> a, List<String> b) {
    var best = 0, bestEnd = 0;
    var prev = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      for (var j = 1; j <= b.length; j++) {
        if (a[i - 1] == b[j - 1]) {
          cur[j] = prev[j - 1] + 1;
          if (cur[j] > best) {
            best = cur[j];
            bestEnd = i;
          }
        }
      }
      prev = cur;
    }
    return (best, bestEnd - best);
  }

  // ─────────────────────────────────────────── V8 attribution

  static const _domainWords = {'es', 'com', 'org', 'net', 'eu', 'info'};

  static void _checkAttribution(
      String body, List<_Source> used, List<String> v) {
    final outlets = <String>{
      for (final s in used)
        if (s.a.outlet.trim().isNotEmpty) s.a.outlet.trim(),
    };
    if (outlets.isEmpty) return; // nothing to attribute to
    final have = words(body);
    final compactBody = have.join();
    for (final o in outlets) {
      var ow = words(o);
      // "elDiario.es" is written "elDiario.es" or just "elDiario".
      while (ow.length > 1 && _domainWords.contains(ow.last)) {
        ow = ow.sublist(0, ow.length - 1);
      }
      if (ow.isEmpty) continue;
      if (_indexOfSeq(have, ow) >= 0) return;
      // "20 Minutos" for "20minutos".
      final compact = ow.join();
      if (compact.length >= 5 && compactBody.contains(compact)) return;
    }
    v.add('the body never names the outlet; attribute the story to '
        '${outlets.join(' / ')} by name at least once');
  }

  // ─────────────────────────────────────────── V9 script

  static const _cyrillicLangs = {'ru', 'uk', 'be', 'bg', 'sr', 'mk', 'kk'};
  static final _cyrillicWordRe =
      RegExp('[\u0400-\u04FF][\u0400-\u04FF\u0300-\u036F]*');

  static void _checkScript(
      String headline, String body, String lang, List<String> v) {
    if (_cyrillicLangs.contains(lang)) {
      var cyr = 0, lat = 0;
      for (final c in body.codeUnits) {
        if (c >= 0x0400 && c <= 0x04FF) {
          cyr++;
        } else if ((c >= 0x41 && c <= 0x5A) ||
            (c >= 0x61 && c <= 0x7A) ||
            (c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7)) {
          lat++;
        }
      }
      if (cyr + lat > 0 && cyr * 2 < cyr + lat) {
        v.add('body must be written in ${_langName(lang)}: only '
            '${(100 * cyr / (cyr + lat)).round()}% of its letters are Cyrillic');
      }
      return;
    }
    for (final (field, text) in [('headline', headline), ('body', body)]) {
      final m = _cyrillicWordRe.firstMatch(text);
      if (m != null) {
        v.add("$field contains Cyrillic text ('${m[0]}'); write it entirely "
            'in ${_langName(lang)}');
      }
    }
  }

  static String _langName(String lang) => switch (lang) {
        'es' => 'Spanish',
        'en' => 'English',
        'ru' => 'Russian',
        'uk' => 'Ukrainian',
        'de' => 'German',
        'fr' => 'French',
        'it' => 'Italian',
        'pt' => 'Portuguese',
        _ => lang,
      };

  // ─────────────────────────────────────────── V10 tasks

  static final _blankRe = RegExp(r'_{3,}');

  static void _checkTasks(
      List<DraftTask> tasks,
      String body,
      Map<String, FeedTargetSpec> byId,
      Map<String, Set<String>> usedWords,
      Set<String> faulty,
      List<String> v) {
    final flatBody = _flat(body);
    var retells = 0;
    final practised = <String>{};
    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      // Exact: the stored kind drives the UI (`kind == 'choice'`).
      if (!taskKinds.contains(t.kind)) {
        v.add("task ${i + 1} has unknown kind '${t.kind}' "
            "(allowed: ${taskKinds.join(', ')})");
        continue;
      }
      final target = t.targetId.trim();
      final label = target.isEmpty
          ? 'task ${i + 1} (${t.kind})'
          : 'task ${i + 1} (${t.kind}, $target)';
      if (t.promptRu.trim().isEmpty) v.add('$label: prompt_ru is empty');
      if (t.kind != 'retell' &&
          target.isNotEmpty &&
          !byId.containsKey(_idKey(target))) {
        v.add("$label: target_id '$target' is not one of the given targets");
      }
      var filled = false;
      switch (t.kind) {
        case 'retell':
          retells++;
        case 'cloze':
          filled = _checkCloze(label, t, flatBody, v);
        case 'choice':
          filled = _checkChoice(label, t, flatBody, v);
        case 'rephrase':
          if (t.text.trim().isEmpty) {
            v.add('$label: text is empty; give the neutral sentence to '
                'rewrite');
          }
      }
      final key = _idKey(target);
      if (t.kind == 'retell' || target.isEmpty || !byId.containsKey(key)) {
        continue;
      }
      final inBody = usedWords[key];
      if (inBody == null) {
        v.add('$label: $target is not used in body — a task may only '
            'practise a target the text uses');
        continue;
      }
      practised.add(key);
      // The gap must be the target itself, not another word of the sentence
      // (a cloze on «martes» does not practise «dar luz verde»). Checked
      // only for a well-formed task on a well-used target: otherwise the
      // violation above already asks for a fix.
      if (filled && !faulty.contains(key)) {
        final a = words(t.answer);
        if (a.isNotEmpty && !a.any(inBody.contains)) {
          v.add("$label: the answer '${t.answer.trim()}' is not part of "
              "$target ('${inBody.join(' ')}'); blank the target's words");
        }
      }
    }
    if (retells != 1) {
      v.add('tasks must include exactly one retell task (found $retells)');
    }
    for (final e in byId.entries) {
      if (e.value.required &&
          usedWords.containsKey(e.key) &&
          !faulty.contains(e.key) &&
          !practised.contains(e.key)) {
        v.add('${e.value.id} is used in body but has no task; add a '
            '${e.value.kind.toLowerCase() == 'mistake' ? 'choice' : 'cloze'} '
            'task for it');
      }
    }
  }

  /// True when the filled gap restores a sentence of the body.
  static bool _checkCloze(
      String label, DraftTask t, String flatBody, List<String> v) {
    final answer = t.answer.trim();
    final blanks = _blankRe.allMatches(t.text).length;
    if (blanks == 0) {
      v.add("$label: text has no '____' blank");
    } else if (blanks > 1) {
      v.add("$label: text has $blanks blanks; use exactly one '____'");
    }
    if (answer.isEmpty) {
      v.add('$label: answer is empty');
      return false;
    }
    final filled =
        blanks == 1 && _checkFill(label, t.text, answer, flatBody, v);
    if (_reveals(t.promptRu, answer)) {
      v.add("$label: prompt_ru gives away the answer '$answer'");
    }
    return filled;
  }

  /// True when the filled gap restores a sentence of the body.
  static bool _checkChoice(
      String label, DraftTask t, String flatBody, List<String> v) {
    final answer = t.answer.trim();
    final options = [
      for (final o in t.options)
        if (o.trim().isNotEmpty) o.trim(),
    ];
    if (options.length < 2 || options.length > 4) {
      v.add('$label: needs 2–4 options, got ${options.length}');
    }
    // A tap is graded with sameOption (accents count, case does not):
    // options it cannot tell apart would mark the wrong one correct.
    for (var a = 0; a < options.length; a++) {
      for (var b = a + 1; b < options.length; b++) {
        if (options[a] == options[b]) {
          v.add("$label: option '${options[a]}' is listed twice");
        } else if (sameOption(options[a], options[b])) {
          v.add("$label: options '${options[a]}' and '${options[b]}' differ "
              'only in case or punctuation — the grader cannot tell them '
              'apart');
        }
      }
    }
    if (answer.isEmpty) {
      v.add('$label: answer is empty');
      return false;
    }
    if (!options.any((o) => sameOption(o, answer))) {
      v.add("$label: answer '$answer' is not one of the options "
          "(${options.map((o) => "'$o'").join(', ')})");
    }
    // With a gap, the right option must restore the body sentence — this
    // catches an answer key that marks the wrong option as correct.
    final blanks = _blankRe.allMatches(t.text).length;
    var filled = false;
    if (blanks > 1) {
      v.add("$label: text has $blanks blanks; use exactly one '____'");
    } else if (blanks == 1) {
      filled = _checkFill(label, t.text, answer, flatBody, v);
    }
    // Listing every option is not a giveaway; singling out the answer is.
    if (_reveals(t.promptRu, answer) &&
        !options.every((o) => _reveals(t.promptRu, o))) {
      v.add("$label: prompt_ru gives away the answer '$answer'");
    }
    return filled;
  }

  static bool _checkFill(String label, String text, String answer,
      String flatBody, List<String> v) {
    // An option like "—" stands for "nothing goes here".
    final fill = _wordSpans(answer).isNotEmpty ? answer : '';
    final filled = text.replaceFirst(_blankRe, fill);
    final probe = _stripEdges(_flat(filled));
    if (probe.isEmpty || !flatBody.contains(probe)) {
      v.add("$label: with the answer filled in, '${_clip(filled.trim())}' "
          'is not a sentence of body');
      return false;
    }
    return true;
  }

  /// The prompt quotes the answer: verbatim, or — for answers with several
  /// key words — in another form ("no dar su brazo a torcer" for "no
  /// dieron su brazo a torcer"). Either way the task tests conjugation at
  /// best, not recall of the expression from its meaning.
  static bool _reveals(String prompt, String answer) {
    final a = words(answer);
    if (a.isEmpty) return false;
    final p = words(prompt);
    if (_indexOfSeq(p, a) >= 0) return true;
    final keys = _keys(answer);
    if (keys.length < 2) return false;
    // Both directions: the answer's key may be the inflected form and the
    // prompt's word the infinitive (dieron ← dar).
    final reverse = [for (final w in p) _KeyMatcher(w)];
    return _inOrderHits(keys, p, reverse) * 10 >= keys.length * 7;
  }

  /// Grades a typed (or tapped) answer: case-, accent- and
  /// punctuation-insensitive. `accentsDiffer` is true when the answer is
  /// right except for accents/ñ, so the UI can say "correct — mind the
  /// accents". [expected] may list alternatives: "echaron / echó".
  static (bool ok, bool accentsDiffer) answerMatches(
      String user, String expected) {
    final got = _accentWords(user);
    if (got.isEmpty) {
      // Symbol-only options ("—" = nothing goes here) compare as typed.
      final a = user.trim();
      return (a.isNotEmpty && a == expected.trim(), false);
    }
    final gotFolded = [for (final w in got) fold(w)];
    for (final e in _answerVariants(expected)) {
      final want = _accentWords(e);
      if (want.isEmpty) continue;
      if (_listEq(gotFolded, [for (final w in want) fold(w)])) {
        return (true, !_listEq(got, want));
      }
    }
    return (false, false);
  }

  static final _alternativesRe = RegExp('[/|]');

  static Iterable<String> _answerVariants(String expected) sync* {
    yield expected;
    if (expected.contains(_alternativesRe)) {
      for (final p in expected.split(_alternativesRe)) {
        if (p.trim().isNotEmpty) yield p;
      }
    }
  }

  // ─────────────────────────────────────────── text helpers

  /// Lowercase, accents/diacritics removed (precomposed or combining),
  /// ё → е, typographic quotes/dashes/spaces unified, whitespace collapsed.
  static String fold(String s) => _foldInto(s, null).trim();

  /// Folded word tokens ("Leña," → "lena"; "180.000" stays one token).
  static List<String> words(String s) =>
      [for (final (a, b) in _wordSpans(s)) fold(s.substring(a, b))];

  static int wordCount(String s) => _wordSpans(s).length;

  static List<_Tok> _tokens(String s) => [
        for (final (a, b) in _wordSpans(s))
          _Tok(s.substring(a, b), fold(s.substring(a, b)), a, b),
      ];

  /// (start, end) of every word: a number with inner separators ("180.000",
  /// "1,5", "10:30"), or letters/digits/marks joined by apostrophes or
  /// hyphens ("d'Hondt", "COVID-19", "Castilla-La").
  ///
  /// Hand-rolled on purpose: Dart's `\p{…}` RegExps run ~80× slower on
  /// two-byte strings — any text with “”, — or Cyrillic, i.e. most model
  /// output and every Russian prompt — and validation runs on the UI isolate.
  static List<(int, int)> _wordSpans(String s) {
    final out = <(int, int)>[];
    final n = s.length;
    var i = 0;
    while (i < n) {
      final c = s.codeUnitAt(i);
      if (!_isWordUnit(c)) {
        i++;
        continue;
      }
      final start = i;
      if (_isDigit(c)) {
        var j = i;
        while (j < n && _isDigit(s.codeUnitAt(j))) {
          j++;
        }
        var end = j;
        while (end + 1 < n &&
            _isNumberSeparator(s.codeUnitAt(end)) &&
            _isDigit(s.codeUnitAt(end + 1))) {
          end++;
          while (end < n && _isDigit(s.codeUnitAt(end))) {
            end++;
          }
        }
        if (end > j) {
          out.add((start, end));
          i = end;
          continue;
        }
      }
      var j = i;
      while (j < n && _isWordUnit(s.codeUnitAt(j))) {
        j++;
      }
      while (j + 1 < n &&
          _isJoiner(s.codeUnitAt(j)) &&
          _isWordUnit(s.codeUnitAt(j + 1))) {
        j++;
        while (j < n && _isWordUnit(s.codeUnitAt(j))) {
          j++;
        }
      }
      out.add((start, j));
      i = j;
    }
    return out;
  }

  /// Letters (Latin, Cyrillic, other cased scripts), ASCII digits and
  /// combining marks.
  static bool _isWordUnit(int c) {
    if (c < 0x80) {
      return (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A);
    }
    if (_isMark(c)) return true;
    if (c == 0xAA || c == 0xB5 || c == 0xBA) return true; // ª µ º
    if (c < 0xC0) return false;
    if (c <= 0x24F) return c != 0xD7 && c != 0xF7; // × ÷
    if (c >= 0x0400 && c <= 0x052F) return c < 0x0482 || c > 0x0489;
    if (c >= 0xD800 && c <= 0xDFFF) return false; // astral: emoji and co.
    final ch = String.fromCharCode(c);
    return ch.toLowerCase() != ch.toUpperCase();
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isNumberSeparator(int c) => c == 0x2E || c == 0x2C || c == 0x3A;

  /// ' ’ ‐ ‑ -
  static bool _isJoiner(int c) =>
      c == 0x27 || c == 0x2019 || c == 0x2010 || c == 0x2011 || c == 0x2D;

  /// Composes the decomposed accented letters Spanish (and й/ё) use, so a
  /// model's NFD output compares equal to NFC text.
  static String nfc(String s) {
    if (!s.codeUnits.any(_isMark)) return s;
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (i + 1 < s.length) {
        final composed = _composeMap[(c << 16) | s.codeUnitAt(i + 1)];
        if (composed != null) {
          b.writeCharCode(composed);
          i++;
          continue;
        }
      }
      b.writeCharCode(c);
    }
    return b.toString();
  }

  static final Map<int, int> _composeMap = () {
    final m = <int, int>{};
    void add(String bases, int mark, String composed) {
      for (var i = 0; i < bases.length; i++) {
        m[(bases.codeUnitAt(i) << 16) | mark] = composed.codeUnitAt(i);
      }
    }

    add('aeiouyAEIOUY', 0x301, 'áéíóúýÁÉÍÓÚÝ');
    add('aeiouAEIOU', 0x300, 'àèìòùÀÈÌÒÙ');
    add('aeiouAEIOU', 0x302, 'âêîôûÂÊÎÔÛ');
    add('aeiouyAEIOU', 0x308, 'äëïöüÿÄËÏÖÜ');
    add('anoANO', 0x303, 'ãñõÃÑÕ');
    add('cC', 0x327, 'çÇ');
    add('иИ', 0x306, 'йЙ');
    add('еЕ', 0x308, 'ёЁ');
    return m;
  }();

  static final Map<int, int> _typoMap = {
    for (final c in '\u00A0\u2007\u2009\u200A\u202F\u205F\u3000\t\n\r'
            '\u000B\u000C\u2028\u2029\u0085'
        .codeUnits)
      c: 0x20,
    for (final c in '’‘‛′`´'.codeUnits) c: 0x27,
    for (final c in '“”„‟«»″'.codeUnits) c: 0x22,
    for (final c in '‐‑‒–—―−'.codeUnits) c: 0x2D,
  };

  static final Map<int, int> _foldMap = () {
    final m = <int, int>{..._typoMap};
    void add(String from, String to) {
      for (final c in from.codeUnits) {
        m[c] = to.codeUnitAt(0);
      }
    }

    add('àáâãäåāăą', 'a');
    add('çćĉċč', 'c');
    add('ďđ', 'd');
    add('èéêëēĕėęě', 'e');
    add('ĝğġģ', 'g');
    add('ĥħ', 'h');
    add('ìíîïĩīĭįı', 'i');
    add('ĵ', 'j');
    add('ķ', 'k');
    add('ĺļľŀł', 'l');
    add('ñńņň', 'n');
    add('òóôõöøōŏő', 'o');
    add('ŕŗř', 'r');
    add('śŝşš', 's');
    add('ţťŧ', 't');
    add('ùúûüũūŭůűų', 'u');
    add('ŵ', 'w');
    add('ýÿŷ', 'y');
    add('źżž', 'z');
    add('ё', 'е');
    return m;
  }();

  static bool _isMark(int c) =>
      (c >= 0x0300 && c <= 0x036F) ||
      (c >= 0x1AB0 && c <= 0x1AFF) ||
      (c >= 0x1DC0 && c <= 0x1DFF) ||
      (c >= 0x20D0 && c <= 0x20FF) ||
      (c >= 0xFE20 && c <= 0xFE2F);

  static bool _isInvisible(int c) =>
      c == 0x00AD || (c >= 0x200B && c <= 0x200D) || c == 0x2060 || c == 0xFEFF;

  /// [fold] without the final trim; when [src] is given, records for every
  /// output code unit the index of the input code unit it came from, so a
  /// match in the folded text maps back to the original (UTF-16) offsets.
  static String _foldInto(String s, List<int>? src) {
    final b = StringBuffer();
    var space = false;
    void emit(int u, int from) {
      if (_isMark(u)) return;
      final f = _foldMap[u] ?? u;
      if (f == 0x20) {
        if (space) return;
        space = true;
      } else {
        space = false;
      }
      b.writeCharCode(f);
      src?.add(from);
    }

    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      // Fast path for Latin-1, i.e. almost all Spanish text.
      if (c < 0x100) {
        final upper =
            (c >= 0x41 && c <= 0x5A) || (c >= 0xC0 && c <= 0xDE && c != 0xD7);
        if (c != 0xAD) emit(upper ? c + 0x20 : c, i); // soft hyphen: drop
        continue;
      }
      if (_isMark(c) || _isInvisible(c)) continue;
      if ((c == 0x0438 || c == 0x0418) &&
          i + 1 < s.length &&
          s.codeUnitAt(i + 1) == 0x0306) {
        emit(0x0439, i); // и + breve is й, a letter of its own
        continue;
      }
      for (final u in String.fromCharCode(c).toLowerCase().codeUnits) {
        emit(u, i);
      }
    }
    return b.toString();
  }

  /// Lowercase, NFC, typography unified, whitespace collapsed — accents
  /// kept. For "is this sentence in the body" checks.
  static String _flat(String s) {
    final b = StringBuffer();
    var space = true;
    for (final c in nfc(s).toLowerCase().codeUnits) {
      if (_isInvisible(c)) continue;
      final f = _typoMap[c] ?? c;
      if (f == 0x20) {
        if (space) continue;
        space = true;
      } else {
        space = false;
      }
      b.writeCharCode(f);
    }
    return b.toString().trimRight();
  }

  /// Lowercase NFC word tokens with accents kept.
  static List<String> _accentWords(String s) {
    final t = nfc(s);
    return [
      for (final (a, b) in _wordSpans(t))
        String.fromCharCodes(t
            .substring(a, b)
            .toLowerCase()
            .codeUnits
            .map((c) => _typoMap[c] ?? c)),
    ];
  }

  /// Drops leading and trailing punctuation, quotes and spaces (a trailing
  /// combining mark belongs to the last letter and stays).
  static String _stripEdges(String s) {
    var a = 0, b = s.length;
    while (
        a < b && (!_isWordUnit(s.codeUnitAt(a)) || _isMark(s.codeUnitAt(a)))) {
      a++;
    }
    while (b > a && !_isWordUnit(s.codeUnitAt(b - 1))) {
      b--;
    }
    return s.substring(a, b);
  }

  static bool _isCapitalised(String w) {
    if (w.isEmpty) return false;
    final first = String.fromCharCode(w.runes.first);
    return first != first.toLowerCase() && first == first.toUpperCase();
  }

  /// Starts a sentence, a paragraph or a quotation.
  static bool _sentenceInitial(String s, int start) {
    var i = start - 1;
    var quoted = false;
    while (i >= 0) {
      final ch = s[i];
      if (ch == ' ' || ch == '\u00A0' || ch == '\t') {
        i--;
      } else if ('«“"‘\''.contains(ch)) {
        quoted = true;
        i--;
      } else if ('¿¡([—–-'.contains(ch)) {
        i--;
      } else {
        break;
      }
    }
    if (i < 0 || quoted) return true;
    return '.!?…:\n\r'.contains(s[i]);
  }

  static bool _onlySpaces(String s, int from, int to) {
    if (to <= from) return false;
    for (var i = from; i < to; i++) {
      final c = s.codeUnitAt(i);
      if (c != 0x20 && c != 0xA0 && c != 0x202F) return false;
    }
    return true;
  }

  static bool _overlapsAny(int a, int b, List<(int, int)> ranges) =>
      ranges.any((r) => a < r.$2 && r.$1 < b);

  static bool _insideAny(int pos, List<(int, int)> ranges) =>
      ranges.any((r) => r.$1 <= pos && pos < r.$2);

  static int _indexOfSeq(List<String> hay, List<String> needle) {
    if (needle.isEmpty) return -1;
    outer:
    for (var i = 0; i + needle.length <= hay.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static List<String> _maskSeq(List<String> hay, List<String> seq) {
    final out = [...hay];
    if (seq.isEmpty) return out;
    for (var i = 0; i + seq.length <= out.length; i++) {
      var match = true;
      for (var j = 0; j < seq.length; j++) {
        if (out[i + j] != seq[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        for (var j = 0; j < seq.length; j++) {
          out[i + j] = '\u0000';
        }
        i += seq.length - 1;
      }
    }
    return out;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _idKey(String id) => id.trim().toUpperCase();

  /// Shortens a quote for a message without splitting a surrogate pair
  /// (the message is JSON-encoded into the repair prompt).
  static String _clip(String s, [int max = 90]) {
    if (s.length <= max) return s;
    var end = max;
    final c = s.codeUnitAt(end - 1);
    if (c >= 0xD800 && c <= 0xDBFF) end--;
    return '${s.substring(0, end)}…';
  }

  static List<String> _dedupe(List<String> v) => v.toSet().toList();

  /// Function words (folded) that carry no meaning of their own.
  static const _stopwords = {
    // es
    'el', 'la', 'los', 'las', 'lo', 'le', 'les', 'un', 'una', 'unos', 'unas',
    'uno', 'de', 'del', 'al', 'a', 'ante', 'bajo', 'con', 'contra', 'desde',
    'en', 'entre', 'hacia', 'hasta', 'para', 'por', 'segun', 'sin', 'sobre',
    'tras', 'y', 'e', 'o', 'u', 'ni', 'que', 'se', 'su', 'sus', 'mi', 'mis',
    'tu', 'tus', 'me', 'te', 'nos', 'os', 'es', 'son', 'ser', 'estar',
    'esta', 'este', 'esto', 'estos', 'estas', 'ese', 'esa', 'eso', 'esos',
    'esas', 'como', 'mas', 'muy', 'ya', 'si', 'no', 'pero', 'porque',
    'cuando', 'donde', 'hay', 'haber', 'ha', 'han', 'fue', 'era',
    // en
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'into', 'not', 'are',
    'was', 'were', 'has', 'have', 'had', 'his', 'her', 'its', 'their', 'our',
    'your',
    // ru
    'и', 'в', 'во', 'не', 'на', 'с', 'со', 'как', 'а', 'то', 'у', 'же', 'бы',
    'по', 'за', 'от', 'из', 'к', 'до', 'о', 'об', 'что', 'это', 'все', 'так',
    'его', 'ее', 'их', 'но', 'да', 'для', 'без', 'при',
  };

  /// Dictionary notation, not words to find in the text.
  static const _placeholders = {
    'algo', 'alguien', 'alguno', 'alguna', 'algun', 'infinitivo', 'inf',
    'infinitive', 'sustantivo', 'verbo', 'subjuntivo', 'indicativo', 'sb',
    'sth', 'someone', 'something', 'oneself', 'etc',
  };
}

// ─────────────────────────────────────────── private types

class _Tok {
  const _Tok(this.text, this.norm, this.start, this.end);
  final String text; // as written
  final String norm; // folded
  final int start;
  final int end;
}

class _Num {
  const _Num(this.display, this.start, this.end, this.keys);
  final String display;
  final int start;
  final int end;
  final Set<String> keys;
}

/// One key word of a canonical form, with alternatives ("echar/tirar").
class _Key {
  _Key(this.label, this.alternatives);
  final String label; // as written in the canonical, for messages
  final List<_KeyMatcher> alternatives;
  bool matches(String w) => alternatives.any((m) => m.matches(w));
}

/// The surface forms one folded key word accepts: the plan's prefix rule
/// (first max(4, len − 2) letters: "echaron" ≈ "echar", "leña" = "lena"),
/// plurals of short words, and Spanish verb inflection the prefix rule
/// cannot reach ("dio" ← dar, "puso" ← ponerse, "cierra" ← cerrar).
class _KeyMatcher {
  _KeyMatcher(this.key) {
    final inf = FeedValidator._infinitive(key);
    if (inf != null) FeedValidator._addVerbPatterns(inf, _prefixes, _forms);
  }

  final String key;
  final Set<String> _prefixes = {};
  final Set<String> _forms = {};

  bool matches(String w) {
    if (w == key) return true;
    if (key.length <= 3) {
      if (w == '${key}s' || w == '${key}es') return true;
    } else if (w.startsWith(key.substring(0, math.max(4, key.length - 2)))) {
      return true;
    }
    if (key.endsWith('z') && w == '${key.substring(0, key.length - 1)}ces') {
      return true; // luz → luces, vez → veces
    }
    if (_forms.contains(w)) return true;
    for (final p in _prefixes) {
      if (w.startsWith(p)) return true;
    }
    return false;
  }
}

class _Source {
  _Source(this.n, this.a)
      : titleWords = FeedValidator.words(a.title),
        leadWords = FeedValidator.words(a.lead);

  final int n;
  final NewsArticle a;
  final List<String> titleWords;
  final List<String> leadWords;

  String get id => 'S$n';

  late final Set<String> _names = {
    ...titleWords,
    ...leadWords,
    ...FeedValidator.words(a.outlet),
  };

  late final Set<String> numberKeys = FeedValidator._sourceNumberKeys(a);

  /// Exact (folded) word, or a shared first 5 letters for inflected names.
  bool knowsName(String w) {
    if (_names.contains(w)) return true;
    if (w.length < 5) return false;
    final stem = w.substring(0, 5);
    return _names.any((s) => s.startsWith(stem));
  }

  bool hasSequence(List<String> seq) =>
      FeedValidator._indexOfSeq(titleWords, seq) >= 0 ||
      FeedValidator._indexOfSeq(leadWords, seq) >= 0;
}
