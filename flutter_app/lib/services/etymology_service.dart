/// «Происхождение и история»: why a word or an expression means what it
/// means — its path from Latin (or Arabic, Greek, Germanic…), the image
/// behind an idiom, its relatives in Spanish, Russian and English, and a
/// hook to remember it by.
///
/// Claude writes the page, grounded in the Wiktionary etymology sections
/// (en + es, or ru for Russian words) fetched here, and marks how certain
/// it is — a folk etymology is named as such. A page is stored and travels
/// with the exchange file: written once on the PC, read on the phone.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/database.dart';
import 'ai_types.dart';
import 'llm_router.dart';

class EtymologyStep {
  final String langRu; // «латынь», «староиспанский»
  final String form;
  final String meaningRu;
  final String period;
  const EtymologyStep(this.langRu, this.form, this.meaningRu, this.period);
}

class EtymologyRelative {
  final String lang; // es | ru | en | fr | it | de | la | other
  final String word;
  final String meaningRu;
  final String noteRu;
  const EtymologyRelative(this.lang, this.word, this.meaningRu, this.noteRu);
}

class EtymologyPage {
  final String term;
  final String lang;
  final String headword;
  final String kind; // word | idiom | proverb | phrase
  final String summaryRu;
  final List<EtymologyStep> chain;
  final String whyRu;
  final String historyRu;
  final String idiomStoryRu;
  final List<EtymologyRelative> relatives;
  final String falseFriendsRu;
  final String mnemonicRu;
  final String certainty; // documented | probable | disputed | folk
  final String certaintyNoteRu;
  final bool grounded;
  final List<String> sources; // 'en.wiktionary', …
  final String backend;
  final String createdAt;

  const EtymologyPage({
    required this.term,
    required this.lang,
    required this.headword,
    this.kind = 'word',
    this.summaryRu = '',
    this.chain = const [],
    this.whyRu = '',
    this.historyRu = '',
    this.idiomStoryRu = '',
    this.relatives = const [],
    this.falseFriendsRu = '',
    this.mnemonicRu = '',
    this.certainty = 'probable',
    this.certaintyNoteRu = '',
    this.grounded = false,
    this.sources = const [],
    this.backend = '',
    this.createdAt = '',
  });

  static String _s(Object? v) => v == null ? '' : v.toString().trim();

  factory EtymologyPage.fromJson(Map<String, dynamic> j,
          {required String term,
          required String lang,
          List<String> sources = const [],
          String backend = '',
          String createdAt = ''}) =>
      EtymologyPage(
        term: term,
        lang: lang,
        headword: _s(j['headword']).isEmpty ? term : _s(j['headword']),
        kind: _s(j['kind']).isEmpty ? 'word' : _s(j['kind']),
        summaryRu: _s(j['summary_ru']),
        chain: [
          for (final c in (j['chain'] is List ? j['chain'] as List : const []))
            if (c is Map)
              EtymologyStep(_s(c['lang_ru']), _s(c['form']),
                  _s(c['meaning_ru']), _s(c['period'])),
        ],
        whyRu: _s(j['why_ru']),
        historyRu: _s(j['history_ru']),
        idiomStoryRu: _s(j['idiom_story_ru']),
        relatives: [
          for (final r
              in (j['relatives'] is List ? j['relatives'] as List : const []))
            if (r is Map && _s(r['word']).isNotEmpty)
              EtymologyRelative(_s(r['lang']), _s(r['word']),
                  _s(r['meaning_ru']), _s(r['note_ru'])),
        ],
        falseFriendsRu: _s(j['false_friends_ru']),
        mnemonicRu: _s(j['mnemonic_ru']),
        certainty: _s(j['certainty']).isEmpty ? 'probable' : _s(j['certainty']),
        certaintyNoteRu: _s(j['certainty_note_ru']),
        grounded: j['grounded'] == true,
        sources: sources.isNotEmpty
            ? sources
            : [
                for (final x
                    in (j['_sources'] is List ? j['_sources'] as List : const []))
                  _s(x)
              ],
        backend: backend,
        createdAt: createdAt,
      );

  bool get isEmpty => summaryRu.isEmpty && chain.isEmpty && whyRu.isEmpty;
}

/// A dictionary excerpt the page is grounded in.
class EtymologySource {
  final String label; // 'en.wiktionary'
  final String url;
  final String text;
  const EtymologySource(this.label, this.url, this.text);
}

class EtymologyService {
  EtymologyService(this._llm, this._db, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final LlmRouter _llm;
  final DatabaseService _db;
  final http.Client _http;

  bool get isAvailable => _llm.hasQualityBackend;
  String get unavailableReason => _llm.unavailableReason;

  /// A stored page, if any (no network).
  Future<EtymologyPage?> cached(String term, String lang) async {
    final row = await _db.etymologyPage(lang, term);
    if (row == null) return null;
    try {
      return EtymologyPage.fromJson(
          (jsonDecode(row['json'] as String) as Map).cast<String, dynamic>(),
          term: row['term'] as String? ?? term,
          lang: lang,
          backend: row['backend'] as String? ?? '',
          createdAt: row['created_at'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Build (or rebuild) the page with Claude.
  Future<EtymologyPage> build(String term, String lang) async {
    final t = term.trim();
    final sources = await fetchSources(t, lang);
    final r = await _llm.completeResult(
      system: systemPrompt,
      user: buildUserMessage(t, lang, sources),
      maxTokens: 6000,
      effort: 'low',
      jsonSchema: schema,
      timeout: const Duration(minutes: 2),
      allowOnDevice: false,
      tier: 'fast',
      feature: 'etymology',
    );
    final j = r.json;
    if (j == null) {
      throw AiException('ИИ вернул страницу не в том формате', detail: r.text);
    }
    final stored = {
      ...j,
      '_sources': [for (final s in sources) s.label],
    };
    await _db.saveEtymologyPage(lang, t, jsonEncode(stored), r.backend);
    return EtymologyPage.fromJson(j,
        term: t,
        lang: lang,
        sources: [for (final s in sources) s.label],
        backend: r.backend);
  }

  // ─────────────────────────────────────────── Wiktionary

  static const _langNames = {
    'es': ('Spanish', 'Español'),
    'ru': ('Russian', 'Русский'),
    'en': ('English', 'Inglés'),
  };

  /// Etymology sections from en.wiktionary (the language's section) and
  /// the word's own-language Wiktionary. Empty when offline or not found.
  Future<List<EtymologySource>> fetchSources(String term, String lang) async {
    final names = _langNames[lang];
    if (names == null) return const [];
    final futures = <Future<EtymologySource?>>[
      _section('en', term, names.$1, const ['Etymology']),
      if (lang == 'es')
        _section('es', term, names.$2, const ['Etimología']),
      if (lang == 'ru')
        _section('ru', term, 'Русский', const ['Этимология']),
    ];
    final got = await Future.wait(futures);
    return got.whereType<EtymologySource>().toList();
  }

  Future<EtymologySource?> _section(
      String wiki, String term, String language, List<String> headings) async {
    for (final title in {term, term.toLowerCase()}) {
      try {
        final uri = Uri.https('$wiki.wiktionary.org', '/w/api.php', {
          'action': 'query',
          'prop': 'extracts',
          'explaintext': '1',
          'exsectionformat': 'wiki',
          'redirects': '1',
          'format': 'json',
          'titles': title,
        });
        final resp = await _http
            .get(uri, headers: {'User-Agent': 'LinguaTrace/2.1 (learning app)'})
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        final pages = ((jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['query']
            as Map?)?['pages'] as Map?;
        if (pages == null || pages.isEmpty) continue;
        final page = pages.values.first as Map;
        if (page.containsKey('missing')) continue;
        final text = extractSection(
            (page['extract'] ?? '').toString(), language, headings);
        if (text.isEmpty) continue;
        return EtymologySource('$wiki.wiktionary',
            'https://$wiki.wiktionary.org/wiki/${Uri.encodeComponent(title)}',
            text);
      } catch (_) {
        // offline or blocked: the page is written from general knowledge
      }
    }
    return null;
  }

  static final _heading = RegExp(r'^(=+)\s*(.*?)\s*=+\s*$');

  /// The first etymology section inside [language]'s section of a plain
  /// "wiki"-formatted extract ("== Spanish ==" / "=== Etymology 1 ==="),
  /// at most 1500 characters. Visible for tests.
  static String extractSection(
      String extract, String language, List<String> headings) {
    final lines = extract.split('\n');
    int? langLevel;
    int? etyLevel;
    final out = <String>[];
    for (final raw in lines) {
      final m = _heading.firstMatch(raw.trim());
      if (m != null) {
        final level = m.group(1)!.length;
        final title = m.group(2)!.toLowerCase();
        if (langLevel == null) {
          if (title.contains(language.toLowerCase())) langLevel = level;
          continue;
        }
        if (level <= langLevel) break; // next language
        // Any heading ends the etymology text — on es.wiktionary the
        // definitions are sub-sections of «Etimología 1».
        if (etyLevel != null) break;
        if (headings.any((h) => title.startsWith(h.toLowerCase()))) {
          etyLevel = level;
        }
        continue;
      }
      if (etyLevel != null && raw.trim().isNotEmpty) out.add(raw.trim());
    }
    final text = out.join('\n').trim();
    return text.length <= 1500 ? text : '${text.substring(0, 1500)}…';
  }

  // ─────────────────────────────────────────── prompt

  static String buildUserMessage(
      String term, String lang, List<EtymologySource> sources) {
    final b = StringBuffer()
      ..writeln('TERM: $term')
      ..writeln('LANGUAGE: $lang')
      ..writeln('DICTIONARY EXCERPTS:');
    if (sources.isEmpty) b.writeln('(none found)');
    for (final s in sources) {
      b
        ..writeln('[${s.label}]')
        ..writeln(s.text);
    }
    return b.toString();
  }

  static const systemPrompt = '''
You are a historical linguist writing a short, vivid page "Origin and history" for ONE reader: an adult native speaker of Russian learning Spanish. The page answers: where does this word or expression come from, WHY does it mean what it means, and what does it share with words the reader already knows.

Sources and honesty
1. DICTIONARY EXCERPTS (Wiktionary) are your primary source. Where your knowledge conflicts with them, follow the excerpts. When they are empty, rely only on standard scholarship (RAE/DLE, Corominas & Pascual, standard Latin and Indo-European dictionaries).
2. Never invent dates, first attestations, authors or anecdotes. If a date is unknown, say so ("точная дата неизвестна") or leave "period" empty.
3. If the popular story of an idiom is a legend, say it plainly, and choose certainty "folk" or "disputed".

What to write (JSON matching the schema; every explanation in RUSSIAN; word forms in their own languages)
- headword: the dictionary form (infinitive, singular) or the expression.
- kind: word | idiom | proverb | phrase.
- summary_ru: one or two sentences — the origin in brief ("от лат. apportāre «приносить к»: ad- «к» + portāre «нести»").
- chain: 2–6 steps from the oldest reliable stage to modern Spanish (PIE root only if standard; Latin/Greek/Arabic/Germanic forms; Old Spanish if it matters). lang_ru = language name in Russian ("латынь", "староиспанский"), form, meaning_ru, period (century or "").
- why_ru: the heart of the page — WHY it is named so: the parts of the word (prefix, root, suffix) and how the literal image turned into today's meaning (metaphor, metonymy, narrowing…). 2–4 sentences.
- history_ru: 2–4 sentences on how the meaning and use changed; for a loanword, when and how it entered Spanish.
- idiom_story_ru: for idioms and proverbs, where the image comes from (bullfighting, the sea, the church, the court…) and what it literally depicts; "" for single words.
- relatives: 3–8 REAL cognates only, never look-alikes: Spanish words of the same root; Russian words of the same root (usually loanwords via Latin/French/Greek: порт, импорт, транспорт…) or genuine Indo-European cognates; a few English ones. note_ru: how it is related ("через франц.", "тот же корень port-"). If unsure a word is related, leave it out.
- false_friends_ru: Spanish↔Russian look-alikes with a different meaning, if any; "" otherwise.
- mnemonic_ru: one sentence that ties the word to something the reader knows (a Russian word with the same root, the literal image).
- certainty: documented (standard dictionaries agree) | probable | disputed | folk; certainty_note_ru: one sentence why.
- grounded: true only if the chain is supported by the excerpts.
Keep the whole page under 350 words.''';

  static final Map<String, dynamic> schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'headword', 'kind', 'summary_ru', 'chain', 'why_ru', 'history_ru',
      'idiom_story_ru', 'relatives', 'false_friends_ru', 'mnemonic_ru',
      'certainty', 'certainty_note_ru', 'grounded',
    ],
    'properties': {
      'headword': {'type': 'string'},
      'kind': {
        'type': 'string',
        'enum': ['word', 'idiom', 'proverb', 'phrase'],
      },
      'summary_ru': {'type': 'string'},
      'chain': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['lang_ru', 'form', 'meaning_ru', 'period'],
          'properties': {
            'lang_ru': {'type': 'string'},
            'form': {'type': 'string'},
            'meaning_ru': {'type': 'string'},
            'period': {'type': 'string'},
          },
        },
      },
      'why_ru': {'type': 'string'},
      'history_ru': {'type': 'string'},
      'idiom_story_ru': {'type': 'string'},
      'relatives': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['lang', 'word', 'meaning_ru', 'note_ru'],
          'properties': {
            'lang': {
              'type': 'string',
              'enum': ['es', 'ru', 'en', 'fr', 'it', 'de', 'la', 'other'],
            },
            'word': {'type': 'string'},
            'meaning_ru': {'type': 'string'},
            'note_ru': {'type': 'string'},
          },
        },
      },
      'false_friends_ru': {'type': 'string'},
      'mnemonic_ru': {'type': 'string'},
      'certainty': {
        'type': 'string',
        'enum': ['documented', 'probable', 'disputed', 'folk'],
      },
      'certainty_note_ru': {'type': 'string'},
      'grounded': {'type': 'boolean'},
    },
  };
}
