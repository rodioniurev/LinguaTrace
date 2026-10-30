/// «Подбор слова»: the machine translation is grammatical but not what the
/// user means — «что я должен привнести в проект?» came out as «qué yo debo
/// llevar al proyecto?» while the user was after «aportar». Here the user
/// points at the word, Claude lists the real options for THIS sentence —
/// meaning, register, fit, typical collocations — each with the sentence
/// rewritten, and the user takes the one that says what they mean.
///
/// Without a checker (a phone with no AI) the dictionary alternatives of
/// the free translator are shown instead, with their back-translations.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_types.dart';
import 'llm_router.dart';

class WordOption {
  final String word; // aportar
  final String pattern; // aportar algo a algo
  final String glossRu;
  final String register; // нейтр. | книжн. | разг.
  final String fit; // best | good | possible | wrong
  final String whyRu;
  final String sentence; // the whole sentence with this word
  final List<String> collocations;

  const WordOption({
    required this.word,
    this.pattern = '',
    this.glossRu = '',
    this.register = '',
    this.fit = 'possible',
    this.whyRu = '',
    this.sentence = '',
    this.collocations = const [],
  });

  bool get fits => fit == 'best' || fit == 'good';
}

class WordChoice {
  final String focus; // the word the user pointed at ('' = whole sentence)
  final String meaningRu; // which sense is meant here
  final List<String> issuesRu; // other problems of the machine translation
  final List<WordOption> options;
  final String bestSentence;
  final String backend; // '' = dictionary fallback
  const WordChoice({
    required this.focus,
    this.meaningRu = '',
    this.issuesRu = const [],
    this.options = const [],
    this.bestSentence = '',
    this.backend = '',
  });

  bool get fromDictionary => backend.isEmpty;

  static String _s(Object? v) => v == null ? '' : v.toString().trim();

  factory WordChoice.fromJson(Map<String, dynamic> j,
          {required String focus, String backend = ''}) =>
      WordChoice(
        focus: focus,
        meaningRu: _s(j['meaning_ru']),
        issuesRu: [
          for (final i in (j['issues_ru'] is List ? j['issues_ru'] as List : const []))
            if (_s(i).isNotEmpty) _s(i),
        ],
        options: [
          for (final o in (j['options'] is List ? j['options'] as List : const []))
            if (o is Map && _s(o['word']).isNotEmpty)
              WordOption(
                word: _s(o['word']),
                pattern: _s(o['pattern']),
                glossRu: _s(o['gloss_ru']),
                register: _s(o['register']),
                fit: const {'best', 'good', 'possible', 'wrong'}
                        .contains(_s(o['fit']))
                    ? _s(o['fit'])
                    : 'possible',
                whyRu: _s(o['why_ru']),
                sentence: _s(o['sentence']),
                collocations: [
                  for (final c
                      in (o['collocations'] is List ? o['collocations'] as List : const []))
                    if (_s(c).isNotEmpty) _s(c),
                ],
              ),
        ],
        bestSentence: _s(j['best_sentence']),
        backend: backend,
      );
}

class WordChoiceService {
  WordChoiceService(this._llm, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final LlmRouter _llm;
  final http.Client _http;

  bool get canExplain => _llm.hasQualityBackend;

  /// Options for [focus] (a word or phrase of [source], '' = the whole
  /// sentence) when [source] ([srcLang]) is translated into [tgtLang].
  /// [hint] is what the user wants to say, in their own words.
  Future<WordChoice> suggest({
    required String source,
    required String translation,
    required String focus,
    required String srcLang,
    required String tgtLang,
    String hint = '',
  }) async {
    if (!canExplain) {
      return dictionaryOptions(focus.isEmpty ? source : focus, srcLang, tgtLang);
    }
    final r = await _llm.completeResult(
      system: systemPrompt,
      user: buildUserMessage(
          source: source,
          translation: translation,
          focus: focus,
          srcLang: srcLang,
          tgtLang: tgtLang,
          hint: hint),
      maxTokens: 6000,
      effort: 'low',
      jsonSchema: schema,
      timeout: const Duration(minutes: 2),
      allowOnDevice: false,
      tier: 'fast',
      feature: 'word_choice',
    );
    final j = r.json;
    if (j == null) {
      throw AiException('ИИ вернул варианты не в том формате', detail: r.text);
    }
    return WordChoice.fromJson(j, focus: focus, backend: r.backend);
  }

  /// The free translator's dictionary: translations of the word by part of
  /// speech, each with its back-translations (which reveal the sense).
  Future<WordChoice> dictionaryOptions(
      String word, String srcLang, String tgtLang) async {
    final uri = Uri.parse('https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=${Uri.encodeComponent(srcLang)}'
        '&tl=${Uri.encodeComponent(tgtLang)}&dt=t&dt=bd'
        '&q=${Uri.encodeComponent(word)}');
    final resp = await _http
        .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw AiException('Словарь не ответил (${resp.statusCode})');
    }
    return parseDictionary(jsonDecode(utf8.decode(resp.bodyBytes)), word);
  }

  /// Visible for tests: Google's `dt=bd` block →
  /// [[pos, [terms], [[term, [back-translations], null, score], …]], …].
  static WordChoice parseDictionary(Object? data, String word) {
    final options = <WordOption>[];
    if (data is List && data.length > 1 && data[1] is List) {
      for (final group in data[1] as List) {
        if (group is! List || group.length < 3) continue;
        final pos = group[0]?.toString() ?? '';
        for (final entry in (group[2] is List ? group[2] as List : const [])) {
          if (entry is! List || entry.isEmpty) continue;
          final term = entry[0]?.toString() ?? '';
          if (term.isEmpty || options.any((o) => o.word == term)) continue;
          final back = entry.length > 1 && entry[1] is List
              ? (entry[1] as List).map((e) => '$e').take(5).join(', ')
              : '';
          options.add(WordOption(
            word: term,
            register: pos,
            glossRu: back,
          ));
          if (options.length >= 12) break;
        }
      }
    }
    return WordChoice(focus: word, options: options);
  }

  static String buildUserMessage({
    required String source,
    required String translation,
    required String focus,
    required String srcLang,
    required String tgtLang,
    String hint = '',
  }) {
    final b = StringBuffer()
      ..writeln('SOURCE ($srcLang): $source')
      ..writeln('MACHINE TRANSLATION ($tgtLang): $translation')
      ..writeln(focus.isEmpty
          ? 'FOCUS: the whole sentence (find the word or words that most need a better choice)'
          : 'FOCUS: «$focus»');
    if (hint.trim().isNotEmpty) {
      b.writeln('WHAT THE READER MEANS (their own words): ${hint.trim()}');
    }
    return b.toString();
  }

  static const systemPrompt = '''
You help ONE reader — an adult native speaker of Russian who writes in Spanish — find the word that says exactly what they mean. They give a sentence in the SOURCE language, the machine translation, and the word (FOCUS) they are unhappy with, sometimes with a hint of what they mean.

Return JSON matching the schema; every explanation in RUSSIAN, words and sentences in the TARGET language.
- meaning_ru: which sense of the FOCUS is meant in this sentence (one sentence). Use the whole sentence and the hint to decide.
- issues_ru: other real problems of the machine translation in this sentence, each «было» → «надо»: why (missing ¿ ?, a needless subject pronoun, a wrong preposition…). [] if none. Do not invent problems.
- options: 4–7 real candidates for the FOCUS in this context, the best first. For each:
  word — the dictionary form; pattern — how it is built ("aportar algo a algo"); gloss_ru — its meaning in Russian; register — нейтр. / книжн. / разг. / офиц.; fit — best | good | possible | wrong for THIS sentence (include the machine's own choice and, when useful, a tempting wrong option, marked wrong); why_ru — one sentence on the nuance and why it fits or not; sentence — the whole target-language sentence rewritten with this word, grammatical and natural (fix the other issues too); collocations — 2–4 typical combinations.
- best_sentence: the most natural full translation that says what the reader means.
Only real, current words of the variety used in Spain unless the input shows another variety.''';

  static final Map<String, dynamic> schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['meaning_ru', 'issues_ru', 'options', 'best_sentence'],
    'properties': {
      'meaning_ru': {'type': 'string'},
      'issues_ru': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'options': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'word', 'pattern', 'gloss_ru', 'register', 'fit', 'why_ru',
            'sentence', 'collocations',
          ],
          'properties': {
            'word': {'type': 'string'},
            'pattern': {'type': 'string'},
            'gloss_ru': {'type': 'string'},
            'register': {'type': 'string'},
            'fit': {
              'type': 'string',
              'enum': ['best', 'good', 'possible', 'wrong'],
            },
            'why_ru': {'type': 'string'},
            'sentence': {'type': 'string'},
            'collocations': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
      'best_sentence': {'type': 'string'},
    },
  };
}
