/// Linguistic analysis: gender, PoS, meanings, etymology for single words.
///
/// Data sources (in priority order):
///   1. Offline Spanish dictionary (Wiktionary SQLite)
///   2. Native-language Wiktionary API (ru.wiktionary for Russian words, etc.)
///   3. English Wiktionary REST API (fallback — gives English definitions)
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'dictionary_service.dart';

// ── model ─────────────────────────────────────────────────────────────────────

class LinguisticInfo {
  final String word;
  final String lang;
  final String partOfSpeech;
  final String gender;
  final String plural;
  final List<String> meanings;
  final String etymology;
  final List<String> examples;
  final String note;
  final String source;

  const LinguisticInfo({
    required this.word,
    required this.lang,
    this.partOfSpeech = '',
    this.gender = '',
    this.plural = '',
    this.meanings = const [],
    this.etymology = '',
    this.examples = const [],
    this.note = '',
    this.source = '',
  });

  bool get isEmpty =>
      partOfSpeech.isEmpty &&
      gender.isEmpty &&
      meanings.isEmpty &&
      etymology.isEmpty;
}

// ── language helpers ──────────────────────────────────────────────────────────

const _langNames = <String, String>{
  'ar': 'Arabic',     'ca': 'Catalan',    'cs': 'Czech',
  'da': 'Danish',     'de': 'German',     'el': 'Greek',
  'en': 'English',    'es': 'Spanish',    'et': 'Estonian',
  'fi': 'Finnish',    'fr': 'French',     'he': 'Hebrew',
  'hi': 'Hindi',      'hr': 'Croatian',   'hu': 'Hungarian',
  'id': 'Indonesian', 'it': 'Italian',    'ja': 'Japanese',
  'ko': 'Korean',     'la': 'Latin',      'lt': 'Lithuanian',
  'lv': 'Latvian',    'nl': 'Dutch',      'no': 'Norwegian',
  'pl': 'Polish',     'pt': 'Portuguese', 'ro': 'Romanian',
  'ru': 'Russian',    'sk': 'Slovak',     'sl': 'Slovenian',
  'sr': 'Serbian',    'sv': 'Swedish',    'th': 'Thai',
  'tr': 'Turkish',    'uk': 'Ukrainian',  'vi': 'Vietnamese',
  'zh': 'Chinese',
};

/// Wiktionary editions that have good coverage and parse-friendly content.
const _wiktionaryEditions = <String, String>{
  'ru': 'ru',
  'es': 'es',
  'fr': 'fr',
  'de': 'de',
  'en': 'en',
};

String _stripHtml(String html) =>
    html.replaceAll(RegExp(r'<[^>]+>'), '').trim();

String _langCode(String lang) =>
    lang.length >= 2 ? lang.substring(0, 2).toLowerCase() : lang;

bool isSingleWord(String text) => text.trim().split(' ').length <= 2;

// ── service ───────────────────────────────────────────────────────────────────

class LinguisticsService {
  final ConfigService _config;
  DictionaryService? _dictionary;

  final _cache = <String, LinguisticInfo>{};

  LinguisticsService(this._config, {DictionaryService? dictionary})
      : _dictionary = dictionary;

  set dictionary(DictionaryService? svc) => _dictionary = svc;

  Future<LinguisticInfo?> analyze(String word, String sourceLang) async {
    word = word.trim();
    if (!isSingleWord(word)) return null;

    final key = '${word.toLowerCase()}|$sourceLang';
    if (_cache.containsKey(key)) return _cache[key];

    final lc = _langCode(sourceLang);

    // 1. Offline dictionary for Spanish
    if (lc == 'es' && _dictionary != null && _dictionary!.isAvailable) {
      final entry = await _dictionary!.lookup(word);
      if (entry != null) {
        final meanings = entry.definition.isNotEmpty
            ? entry.definition.split(' | ')
            : <String>[];
        final info = LinguisticInfo(
          word: entry.word,
          lang: sourceLang,
          partOfSpeech: entry.pos,
          gender: entry.gender,
          meanings: meanings,
          etymology: entry.etymology,
          examples: entry.examples,
          source: 'offline dictionary',
        );
        if (!info.isEmpty) {
          _cache[key] = info;
          return info;
        }
      }
    }

    // 2. Native-language Wiktionary (definitions in the word's own language)
    var info = await _nativeWiktionary(word, sourceLang);

    // 3. English Wiktionary fallback (definitions in English)
    if (info == null || info.isEmpty) {
      info = await _enWiktionary(word, sourceLang);
    }

    // 4. Ollama fallback
    if (info == null || info.isEmpty) {
      info = await _ollama(word, sourceLang);
    }

    if (info != null) _cache[key] = info;
    return info;
  }

  // ── Native Wiktionary (MediaWiki API) ───────────────────────────────────────
  // Uses the MediaWiki API to get page extract in the word's own language.
  // e.g. ru.wiktionary.org for Russian words → definitions in Russian.

  Future<LinguisticInfo?> _nativeWiktionary(String word, String lang) async {
    final lc = _langCode(lang);
    final edition = _wiktionaryEditions[lc];
    if (edition == null || edition == 'en') return null; // skip, en handled separately

    try {
      final encoded = Uri.encodeComponent(word);
      // Use MediaWiki API to get page content as plain text
      final url = Uri.parse(
        'https://$edition.wiktionary.org/w/api.php'
        '?action=query&titles=$encoded&prop=extracts'
        '&explaintext=1&exsectionformat=plain&format=json',
      );

      final resp = await http.get(url, headers: {
        'User-Agent': 'LinguaTrace/2.0',
      }).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final pages = data['query']?['pages'] as Map<String, dynamic>?;
      if (pages == null) return null;

      // Get first page (there's usually just one)
      final page = pages.values.first as Map<String, dynamic>;
      if (page.containsKey('missing')) return null;

      final extract = (page['extract'] as String? ?? '').trim();
      if (extract.isEmpty) return null;

      // Parse the extract text to find useful info
      return _parseWiktionaryExtract(extract, word, lang, edition);
    } catch (_) {
      return null;
    }
  }

  /// Parse plain-text Wiktionary extract to find PoS, gender, meanings.
  LinguisticInfo? _parseWiktionaryExtract(
      String text, String word, String lang, String edition) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return null;

    String pos = '';
    String gender = '';
    final meanings = <String>[];
    final examples = <String>[];
    String etymology = '';

    // Language-specific section headers for PoS
    final posPatterns = _getPosPatterns(edition);

    for (int i = 0; i < lines.length && meanings.length < 5; i++) {
      final line = lines[i].trim();

      // Detect part of speech from section headers
      if (pos.isEmpty) {
        for (final entry in posPatterns.entries) {
          if (line.toLowerCase().contains(entry.key)) {
            pos = entry.value;
            break;
          }
        }
      }

      // Detect gender markers
      if (gender.isEmpty) {
        if (RegExp(r'\bм\.?\s*р|мужской', caseSensitive: false).hasMatch(line)) {
          gender = 'm';
        } else if (RegExp(r'\bж\.?\s*р|женский', caseSensitive: false).hasMatch(line)) {
          gender = 'f';
        } else if (RegExp(r'\bс\.?\s*р|средний', caseSensitive: false).hasMatch(line)) {
          gender = 'n';
        } else if (RegExp(r'\bmasculino\b', caseSensitive: false).hasMatch(line)) {
          gender = 'm';
        } else if (RegExp(r'\bfemenino\b', caseSensitive: false).hasMatch(line)) {
          gender = 'f';
        }
      }

      // Lines that look like definitions (start with number or bullet)
      final defMatch = RegExp(r'^\d+[\.\)]\s*(.+)').firstMatch(line);
      if (defMatch != null) {
        final def = defMatch.group(1)!.trim();
        if (def.isNotEmpty && def.length > 3 && def.length < 200) {
          meanings.add(def);
        }
      }

      // Etymology detection
      if (etymology.isEmpty) {
        if (line.toLowerCase().contains('этимолог') ||
            line.toLowerCase().contains('etimolog')) {
          if (i + 1 < lines.length) {
            etymology = lines[i + 1].trim();
            if (etymology.length > 200) etymology = etymology.substring(0, 200);
          }
        }
      }
    }

    // If no numbered definitions found, try taking first meaningful lines
    if (meanings.isEmpty) {
      for (final line in lines.skip(1).take(5)) {
        final trimmed = line.trim();
        if (trimmed.length > 10 &&
            trimmed.length < 200 &&
            !trimmed.contains('==') &&
            !trimmed.startsWith('{{')) {
          meanings.add(trimmed);
          if (meanings.length >= 3) break;
        }
      }
    }

    if (meanings.isEmpty && pos.isEmpty) return null;

    return LinguisticInfo(
      word: word,
      lang: lang,
      partOfSpeech: pos,
      gender: gender,
      meanings: meanings.take(4).toList(),
      etymology: etymology,
      examples: examples,
      source: '$edition.wiktionary',
    );
  }

  Map<String, String> _getPosPatterns(String edition) {
    switch (edition) {
      case 'ru':
        return {
          'существительное': 'сущ.',
          'глагол': 'глагол',
          'прилагательное': 'прил.',
          'наречие': 'нареч.',
          'предлог': 'предлог',
          'местоимение': 'местоим.',
          'союз': 'союз',
        };
      case 'es':
        return {
          'sustantivo': 'sustantivo',
          'verbo': 'verbo',
          'adjetivo': 'adjetivo',
          'adverbio': 'adverbio',
          'preposición': 'preposición',
          'pronombre': 'pronombre',
          'conjunción': 'conjunción',
        };
      default:
        return {
          'noun': 'noun',
          'verb': 'verb',
          'adjective': 'adj',
          'adverb': 'adv',
        };
    }
  }

  // ── English Wiktionary REST API (fallback) ──────────────────────────────────

  Future<LinguisticInfo?> _enWiktionary(String word, String lang) async {
    try {
      final encoded = Uri.encodeComponent(word.toLowerCase());
      final url = Uri.parse(
          'https://en.wiktionary.org/api/rest_v1/page/definition/$encoded');

      final resp = await http.get(url, headers: {
        'User-Agent': 'LinguaTrace/2.0',
      }).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // The REST definition API keys sections by ISO code ("es", "ru",
      // "other"), NOT by full language names — comparing against
      // "Spanish"/"Russian" never matched and we fell into a random section.
      // Same bug was fixed in legacy/core/linguistics.py on 2026-05-29.
      final code = _langCode(lang).toLowerCase();

      List<dynamic>? entries;
      if (data[code] is List) {
        entries = data[code] as List;
      } else {
        // Google auto-detect reports "en" for many ambiguous single words —
        // prefer the languages the user actually studies.
        for (final k in const ['es', 'ru', 'en', 'de', 'fr', 'it', 'pt', 'uk']) {
          if (data[k] is List) {
            entries = data[k] as List;
            break;
          }
        }
      }
      entries ??= data.isNotEmpty ? (data.values.first as List) : null;
      if (entries == null || entries.isEmpty) return null;

      String pos = '';
      final meanings = <String>[];
      final examples = <String>[];

      for (final entry in entries) {
        final entryPos = (entry['partOfSpeech'] ?? '').toString().toLowerCase();
        if (pos.isEmpty && entryPos.isNotEmpty) pos = entryPos;

        for (final defn in (entry['definitions'] as List? ?? []).take(4)) {
          final txt = _stripHtml(defn['definition']?.toString() ?? '');
          if (txt.isNotEmpty && !meanings.contains(txt)) {
            meanings.add(txt.length > 140 ? txt.substring(0, 140) : txt);
          }
          for (final ex in (defn['parsedExamples'] as List? ?? []).take(1)) {
            final exTxt = _stripHtml(ex['example']?.toString() ?? '');
            if (exTxt.isNotEmpty && examples.length < 2) {
              examples.add(exTxt.length > 120 ? exTxt.substring(0, 120) : exTxt);
            }
          }
        }
      }

      return LinguisticInfo(
        word: word,
        lang: lang,
        partOfSpeech: pos,
        meanings: meanings,
        examples: examples,
        source: 'en.wiktionary',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Ollama (LAN) ────────────────────────────────────────────────────────────

  Future<LinguisticInfo?> _ollama(String word, String lang) async {
    if (!_config.ollamaEnabled) return null;

    final langName = _langNames[_langCode(lang)] ?? lang;

    final prompt = 'Analyze the $langName word "$word". '
        'Reply with ONLY valid JSON (no markdown, no explanation):\n'
        '{"part_of_speech":"noun/verb/adj/adv/etc",'
        '"gender":"m or f or n or m/f or empty string",'
        '"plural":"plural form or empty string",'
        '"meanings":["definition 1","definition 2"],'
        '"etymology":"brief origin or empty string",'
        '"examples":["short example phrase"],'
        '"note":"irregular/formal/colloquial or empty string"}';

    try {
      final resp = await http.post(
        Uri.parse('${_config.ollamaUrl}/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _config.ollamaModel,
          'prompt': prompt,
          'stream': false,
          'options': {'temperature': 0.1},
        }),
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) return null;

      final respText =
          (jsonDecode(resp.body)['response'] as String? ?? '').trim();
      final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(respText);
      if (match == null) return null;

      final d = jsonDecode(match.group(0)!) as Map<String, dynamic>;

      return LinguisticInfo(
        word: word,
        lang: lang,
        partOfSpeech: d['part_of_speech']?.toString() ?? '',
        gender: d['gender']?.toString() ?? '',
        plural: d['plural']?.toString() ?? '',
        meanings: List<String>.from(d['meanings'] ?? []).take(4).toList(),
        etymology: d['etymology']?.toString() ?? '',
        examples: List<String>.from(d['examples'] ?? []).take(2).toList(),
        note: d['note']?.toString() ?? '',
        source: 'ollama',
      );
    } catch (_) {
      return null;
    }
  }
}
