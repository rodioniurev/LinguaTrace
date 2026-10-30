/// Proverb / idiom service backed by a pre-built SQLite database.
///
/// Schema v2 supports 7 languages (ru, es, en, de, fr, uk, tr) and an optional
/// embedding column for future semantic search. The seed DB is shipped in
/// `assets/proverbs/proverbs.db` and copied to the app's documents directory
/// on first run. If a v1 DB is already on disk, we detect the schema and
/// re-copy the v2 seed transparently.
///
/// Matching is done against an in-memory index with aggressive normalization
/// (stress marks, ё→е, Latin diacritics, punctuation, stopwords) and
/// significant-token overlap scoring. The stored texts keep their stress
/// marks — they are a feature for learners — only matching ignores them.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ProverbMatch {
  final String? textRu;
  final String? textEs;
  final String? textEn;
  final String? textDe;
  final String? textFr;
  final String? textUk;
  final String? textTr;
  final String? literalEn;
  final String? source;       // 'wikiquote-ru', 'refranero', 'kiselev', ...
  final double  confidence;   // 0.0 – 1.0
  /// Permyakov-style logico-semiotic invariant (e.g. "appearance-deceives") —
  /// links proverbs across languages that share the same underlying idea.
  final String? conceptKey;
  /// Spanish region for regionalisms ("andalucia", "canarias", ...).
  final String? region;

  const ProverbMatch({
    this.textRu,
    this.textEs,
    this.textEn,
    this.textDe,
    this.textFr,
    this.textUk,
    this.textTr,
    this.literalEn,
    this.source,
    this.confidence = 0.5,
    this.conceptKey,
    this.region,
  });

  /// Texts in language→text form, in stable display order. Skips nulls.
  Map<String, String> byLang() {
    final m = <String, String>{};
    if (textRu != null && textRu!.isNotEmpty) m['ru'] = textRu!;
    if (textEs != null && textEs!.isNotEmpty) m['es'] = textEs!;
    if (textEn != null && textEn!.isNotEmpty) m['en'] = textEn!;
    if (textDe != null && textDe!.isNotEmpty) m['de'] = textDe!;
    if (textFr != null && textFr!.isNotEmpty) m['fr'] = textFr!;
    if (textUk != null && textUk!.isNotEmpty) m['uk'] = textUk!;
    if (textTr != null && textTr!.isNotEmpty) m['tr'] = textTr!;
    return m;
  }

  /// Count of populated language columns — used by the UI to skip empty rows.
  int get languageCount => byLang().length;
}

// ── matching normalization ─────────────────────────────────────────────────

/// Latin diacritics folding (precomposed forms — decomposed combining marks
/// are stripped separately).
const _diacriticFold = <String, String>{
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c', 'ß': 'ss', 'ş': 's', 'ğ': 'g', 'ı': 'i', 'ý': 'y',
};

/// Function words that carry no meaning for proverb matching.
/// All entries are already in normalized (folded, lowercase) form.
const _stopwords = <String>{
  // ru
  'и', 'в', 'во', 'не', 'на', 'с', 'со', 'как', 'а', 'то', 'у', 'же', 'бы',
  'б', 'по', 'за', 'от', 'из', 'к', 'ко', 'до', 'о', 'об', 'что', 'кто',
  'это', 'все', 'так', 'его', 'ее', 'их', 'но', 'да', 'ты', 'вы', 'мы',
  'он', 'она', 'оно', 'они', 'мне', 'тебе', 'себе', 'ни', 'ли', 'или',
  'уж', 'для', 'без', 'при', 'чем', 'том', 'тот', 'та', 'те', 'есть',
  // es (folded: más→mas, sí→si, está→esta)
  'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'de', 'del', 'al',
  'a', 'en', 'y', 'o', 'u', 'que', 'no', 'se', 'su', 'sus', 'con', 'por',
  'para', 'es', 'son', 'esta', 'este', 'esto', 'lo', 'le', 'les', 'mas',
  'como', 'si', 'ya', 'hay', 'ser', 'estar',
  // en
  'the', 'an', 'of', 'to', 'in', 'and', 'or', 'is', 'are', 'be', 'it',
  'that', 'this', 'you', 'your', 'not', 'on', 'at', 'as', 'for', 'with',
  'he', 'she', 'they', 'we', 'his', 'her', 'its', 'who', 'what', 'than',
  'then', 'there',
};

/// Combining diacritical marks block (U+0300–U+036F) — covers the acute
/// stress marks the RU corpus uses (е́, о́, ...).
final _combiningMarks = RegExp('[̀-ͯ]');
final _nonWordChars = RegExp(r'[^a-z0-9а-яіїєґ]+');
final _multiSpace = RegExp(r'\s+');

/// Normalize text for matching: lowercase, strip stress marks / combining
/// diacritics (the RU corpus is fully stress-marked!), fold ё→е and Latin
/// diacritics, replace punctuation with spaces.
String normalizeForMatch(String s) {
  var t = s.toLowerCase();
  // Re-compose decomposed й (и + U+0306) and ё (е + U+0308) BEFORE stripping
  // combining marks, otherwise NFD input would collapse "какой" to "какои"
  // while NFC input keeps "какой" — and the two sides would never match.
  t = t
      .replaceAll('й', 'й') // и+breve → й
      .replaceAll('ё', 'ё'); // е+diaeresis → ё
  t = t.replaceAll(_combiningMarks, '');
  t = t.replaceAll('ё', 'е'); // ё → е
  final sb = StringBuffer();
  for (final ch in t.split('')) {
    sb.write(_diacriticFold[ch] ?? ch);
  }
  t = sb.toString();
  t = t.replaceAll(_nonWordChars, ' ');
  return t.replaceAll(_multiSpace, ' ').trim();
}

/// Significant (non-stopword) tokens of a normalized string.
List<String> significantTokens(String normalized) => normalized
    .split(' ')
    .where((w) => w.length >= 2 && !_stopwords.contains(w))
    .toList();

/// Loose token equality that survives inflection: exact match, or a shared
/// prefix of ≥4 chars covering most of both tokens (стенку≈стену, gato≈gatos).
bool _tokensAlike(String a, String b) {
  if (a == b) return true;
  final minLen = a.length < b.length ? a.length : b.length;
  if (minLen < 4) return false;
  var common = 0;
  while (common < minLen && a[common] == b[common]) {
    common++;
  }
  if (common < 4) return false;
  final maxLen = a.length > b.length ? a.length : b.length;
  return common / maxLen >= 0.6;
}

class _IndexedProverb {
  final ProverbMatch match;
  final List<String> tokens;    // significant tokens across all languages
  final List<String> normTexts; // normalized full texts, for phrase inclusion
  _IndexedProverb(this.match, this.tokens, this.normTexts);
}

class ProverbService {
  Database? _db;
  bool _available = false;
  bool _hasV2Schema = false;  // True if extended language columns exist
  bool _hasConcept = false;   // True if concept_key/region columns exist (v4)

  List<_IndexedProverb>? _index;
  Map<String, List<_IndexedProverb>>? _byConcept;
  Future<void>? _indexBuild;

  bool get isAvailable => _available;
  bool get isMultilingual => _hasV2Schema;

  // The marker file lets us detect upgrades cheaply without opening the DB.
  // v4: re-parsed Kiselev corpus (the v3 import had a systematic ±1
  // proverb↔equivalent shift), curated concept-key core, regionalisms.
  // Old installs see a missing marker and re-seed from the bundled asset.
  static const _seedMarker = '.proverbs_v4_seeded';

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'proverbs.db');
      final markerPath = p.join(dir.path, _seedMarker);

      final dbExists = File(dbPath).existsSync();
      final markerExists = File(markerPath).existsSync();

      // (Re-)seed when:
      //   - first run (no DB on disk), OR
      //   - DB exists but the v2 marker is missing (upgraded from v1)
      // Write to a `.tmp` sidecar then rename atomically. If the process is
      // killed mid-write the next launch sees only the old file or no file,
      // never a half-written one. The marker is written *after* the rename
      // so a present marker always implies a fully-seeded DB.
      if (!dbExists || !markerExists) {
        try {
          final data = await rootBundle.load('assets/proverbs/proverbs.db');
          final tmpPath = '$dbPath.tmp';
          final tmpFile = File(tmpPath);
          await tmpFile.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
          // Remove stale marker first so a crash between rename and marker
          // write doesn't leave us with an inconsistent (new DB, no marker)
          // state.
          if (markerExists) {
            try { await File(markerPath).delete(); } catch (_) {}
          }
          await tmpFile.rename(dbPath);
          await File(markerPath).writeAsString('v2');
        } catch (_) {
          // Asset missing or unreadable — fall through. Service stays unavailable.
          return;
        }
      }

      _db = await openDatabase(dbPath, readOnly: true);

      // Detect schema features so we can degrade gracefully on old DBs.
      final cols = await _db!.rawQuery("PRAGMA table_info(proverbs)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      _hasV2Schema = colNames.contains('text_de');
      _hasConcept = colNames.contains('concept_key');

      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  // ── language detection ──────────────────────────────────────────────────

  /// Cheap heuristic — returns probable ISO-639-1 code from the script used.
  /// Matches the languages we actually store in the DB.
  String detectLang(String text) {
    if (text.isEmpty) return 'en';
    int cyr = 0, lat = 0;
    for (final c in text.runes) {
      if (c >= 0x0400 && c <= 0x04FF) cyr++;
      else if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) lat++;
    }
    if (cyr > lat) {
      // Crude RU vs UK split: presence of UK-only letters
      const ukOnly = {'і', 'ї', 'є', 'ґ'};
      for (final ch in text.toLowerCase().split('')) {
        if (ukOnly.contains(ch)) return 'uk';
      }
      return 'ru';
    }
    // Latin script — look for Spanish/French diacritics to refine
    final lower = text.toLowerCase();
    if (RegExp(r'[ñ¿¡]').hasMatch(lower)) return 'es';
    if (RegExp(r'[àâçéèêëîïôûüù]').hasMatch(lower) &&
        !RegExp(r'\b(the|of|and|is)\b').hasMatch(lower)) {
      return 'fr';
    }
    if (RegExp(r'[äöüß]').hasMatch(lower)) return 'de';
    return 'en';
  }

  // ── index ────────────────────────────────────────────────────────────────

  Future<void> _ensureIndex() {
    if (_index != null) return Future.value();
    return _indexBuild ??= _buildIndex();
  }

  Future<void> _buildIndex() async {
    final rows = await _db!.rawQuery('SELECT ${_selectCols()} FROM proverbs');
    final index = <_IndexedProverb>[];
    final byConcept = <String, List<_IndexedProverb>>{};
    for (final r in rows) {
      final m = _rowToMatch(r);
      final texts = m.byLang().values.toList();
      if (texts.isEmpty) continue;
      final normTexts = texts.map(normalizeForMatch).toList();
      final tokens = <String>{};
      for (final t in normTexts) {
        tokens.addAll(significantTokens(t));
      }
      final entry = _IndexedProverb(m, tokens.toList(), normTexts);
      index.add(entry);
      final ck = m.conceptKey;
      if (ck != null && ck.isNotEmpty) {
        byConcept.putIfAbsent(ck, () => []).add(entry);
      }
    }
    _index = index;
    _byConcept = byConcept;
  }

  // ── search ──────────────────────────────────────────────────────────────

  /// Search across all stored languages by significant-token overlap.
  ///
  /// The query is normalized the same way as the corpus (stress marks
  /// stripped, ё→е, diacritics folded, punctuation removed) and scored:
  ///   - exact token match: 1.0, inflection-tolerant prefix match: 0.75
  ///   - whole-phrase containment (either direction): strong bonus
  /// Rows must cover at least half of the query's significant tokens.
  /// Sorted by score, then by number of covered languages, then confidence —
  /// NOT by raw confidence alone, which used to surface irrelevant rows.
  Future<List<ProverbMatch>> search(String query, {int limit = 12}) async {
    if (!_available || _db == null) return [];
    final qNorm = normalizeForMatch(query);
    if (qNorm.length < 2) return [];

    await _ensureIndex();
    final index = _index;
    if (index == null || index.isEmpty) return [];

    var qTokens = significantTokens(qNorm);
    // All-stopword queries ("как об...") still deserve a phrase attempt.
    if (qTokens.isEmpty) {
      qTokens = qNorm.split(' ').where((w) => w.length >= 2).toList();
    }
    if (qTokens.isEmpty) return [];

    final scored = <(double, _IndexedProverb)>[];
    for (final entry in index) {
      var matched = 0.0;
      for (final q in qTokens) {
        if (entry.tokens.contains(q)) {
          matched += 1.0;
        } else if (entry.tokens.any((t) => _tokensAlike(q, t))) {
          matched += 0.75;
        }
      }
      var score = matched / qTokens.length;
      // Whole-phrase containment: the user typed the proverb (or a chunk of
      // it), or the proverb is embedded inside a longer typed sentence.
      // Checked BEFORE the threshold — a proverb buried in a long sentence
      // covers only a fraction of the sentence's tokens, yet is exactly what
      // the user wants surfaced.
      var contained = false;
      for (final t in entry.normTexts) {
        if (t.length >= 6 && (t.contains(qNorm) || qNorm.contains(t))) {
          contained = true;
          break;
        }
      }
      if (contained) {
        score += 0.75;
      } else if (score < 0.5) {
        continue;
      }
      scored.add((score, entry));
    }

    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      final byLangs =
          b.$2.match.languageCount.compareTo(a.$2.match.languageCount);
      if (byLangs != 0) return byLangs;
      return b.$2.match.confidence.compareTo(a.$2.match.confidence);
    });

    final seen = <String>{};
    final results = <ProverbMatch>[];
    String keyOf(ProverbMatch m) =>
        '${m.textRu ?? ''}|${m.textEs ?? ''}|${m.textEn ?? ''}';
    for (final (_, entry) in scored) {
      final m = entry.match;
      if (!seen.add(keyOf(m))) continue;
      results.add(m);
      if (results.length >= limit) break;
    }

    // Concept-key expansion (Permyakov invariants): pull in proverbs that
    // share the top matches' concept keys — this is how a Russian query
    // surfaces the Spanish regionalism expressing the same idea even when
    // they share no words.
    final byConcept = _byConcept;
    if (byConcept != null && results.length < limit) {
      final topConcepts = results
          .take(4)
          .map((m) => m.conceptKey)
          .whereType<String>()
          .where((k) => k.isNotEmpty)
          .toSet();
      for (final ck in topConcepts) {
        for (final entry in byConcept[ck] ?? const <_IndexedProverb>[]) {
          if (results.length >= limit) break;
          if (seen.add(keyOf(entry.match))) results.add(entry.match);
        }
      }
    }
    return results;
  }

  /// Find the equivalent of [query] in [targetLang]. Source language is
  /// auto-detected. Returns rows that have a non-null value for the target
  /// language column. Convenience wrapper around [search].
  Future<List<ProverbMatch>> findEquivalent(String query, String targetLang) async {
    final all = await search(query);
    final tgt = targetLang.toLowerCase().substring(0, 2);
    return all.where((m) {
      final t = m.byLang()[tgt];
      return t != null && t.isNotEmpty;
    }).toList();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String _selectCols() {
    if (!_hasV2Schema) return 'text_ru, text_es, text_en, literal_en';
    var cols = 'text_ru, text_es, text_en, text_de, text_fr, text_uk, '
        'text_tr, literal_en, source, confidence';
    if (_hasConcept) cols += ', concept_key, region';
    return cols;
  }

  ProverbMatch _rowToMatch(Map<String, Object?> r) => ProverbMatch(
        textRu: r['text_ru'] as String?,
        textEs: r['text_es'] as String?,
        textEn: r['text_en'] as String?,
        textDe: _hasV2Schema ? r['text_de'] as String? : null,
        textFr: _hasV2Schema ? r['text_fr'] as String? : null,
        textUk: _hasV2Schema ? r['text_uk'] as String? : null,
        textTr: _hasV2Schema ? r['text_tr'] as String? : null,
        literalEn: r['literal_en'] as String?,
        source: _hasV2Schema ? r['source'] as String? : null,
        confidence: _hasV2Schema
            ? ((r['confidence'] as num?)?.toDouble() ?? 0.5)
            : 0.5,
        conceptKey: _hasConcept ? r['concept_key'] as String? : null,
        region: _hasConcept ? r['region'] as String? : null,
      );

  Future<void> close() async => await _db?.close();
}
