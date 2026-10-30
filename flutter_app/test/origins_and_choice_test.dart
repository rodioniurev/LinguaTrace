/// «Происхождение и история» and «Подбор слова»: Wiktionary sections are
/// cut out correctly, pages are built through the model and stored (and
/// travel with the exchange file), word options parse — from the model and
/// from the free dictionary — and the translation cache serves an
/// auto-detected source.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/translation_entry.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/etymology_service.dart';
import 'package:lingua_trace/services/exchange_service.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:lingua_trace/services/translator_service.dart';
import 'package:lingua_trace/services/word_choice_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _enExtract = '''
== Spanish ==

=== Etymology ===
Inherited from Latin apportāre, from ad- + portāre (“to carry”).

=== Pronunciation ===
IPA: /apoɾˈtaɾ/

=== Verb ===
aportar (first-person singular present aporto)
to contribute

== Portuguese ==

=== Etymology ===
From Latin apportāre.
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Wiktionary etymology sections', () {
    test('the right language, only the etymology', () {
      expect(
          EtymologyService.extractSection(
              _enExtract, 'Spanish', const ['Etymology']),
          'Inherited from Latin apportāre, from ad- + portāre (“to carry”).');
    });
    test('numbered etymologies and other wikis', () {
      const es = '''
== Español ==
=== Etimología 1 ===
Del latín apportare.
==== Verbo transitivo ====
contribuir
''';
      expect(EtymologyService.extractSection(es, 'Español', const ['Etimología']),
          'Del latín apportare.');
      expect(EtymologyService.extractSection(es, 'Russian', const ['Etymology']),
          '');
    });
  });

  group('an origin page', () {
    late HttpServer model;
    late DatabaseService db;
    Map<String, dynamic>? reply;
    String? lastPrompt;

    setUp(() async {
      model = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      model.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        lastPrompt = ((body['messages'] as List).last as Map)['content'] as String;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(reply)}
            }
          ]
        }));
        await req.response.close();
      });
      db = DatabaseService();
      await db.init(path: inMemoryDatabasePath);
    });
    tearDown(() async {
      await model.close(force: true);
      await db.close();
    });

    EtymologyService service() {
      final cfg = ConfigService()
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${model.port}/v1'
        ..customModel = 'gemini-2.0-flash';
      // Wiktionary answers from a fixture, never the network.
      final wiki = MockClient((req) async => http.Response(
          jsonEncode({
            'query': {
              'pages': {
                '1': {
                  'extract': req.url.host.startsWith('en.') ? _enExtract : '',
                }
              }
            }
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      return EtymologyService(LlmRouter(cfg, ai: AiClient(cfg)), db,
          httpClient: wiki);
    }

    test('grounded in Wiktionary, parsed, stored, read back', () async {
      reply = {
        'headword': 'aportar',
        'kind': 'word',
        'summary_ru': 'От лат. apportāre «приносить к».',
        'chain': [
          {'lang_ru': 'латынь', 'form': 'portāre', 'meaning_ru': 'нести', 'period': ''},
          {'lang_ru': 'латынь', 'form': 'apportāre', 'meaning_ru': 'приносить к', 'period': ''},
          {'lang_ru': 'испанский', 'form': 'aportar', 'meaning_ru': 'вносить, привносить', 'period': 'XIII в.'},
        ],
        'why_ru': 'ad- «к» + portāre «нести»: принести к чему-то → внести вклад.',
        'history_ru': 'Сначала — «прибыть в порт», затем «внести».',
        'idiom_story_ru': '',
        'relatives': [
          {'lang': 'es', 'word': 'aporte', 'meaning_ru': 'вклад', 'note_ru': ''},
          {'lang': 'ru', 'word': 'импорт', 'meaning_ru': 'ввоз', 'note_ru': 'тот же корень port-'},
          {'lang': 'en', 'word': 'support', 'meaning_ru': 'поддержка', 'note_ru': ''},
        ],
        'false_friends_ru': '',
        'mnemonic_ru': 'aportar — как «импорт»: внести внутрь.',
        'certainty': 'documented',
        'certainty_note_ru': 'Словари сходятся.',
        'grounded': true,
      };
      final svc = service();
      final p = await svc.build('aportar', 'es');
      expect(p.chain.map((c) => c.form), ['portāre', 'apportāre', 'aportar']);
      expect(p.relatives.where((r) => r.lang == 'ru').single.word, 'импорт');
      expect(p.sources, ['en.wiktionary']);
      expect(lastPrompt, contains('Inherited from Latin apportāre'),
          reason: 'the dictionary excerpt goes to the model');

      final again = await svc.cached('Aportar', 'es');
      expect(again?.whyRu, contains('ad-'));
      expect(again?.sources, ['en.wiktionary']);
    });

    test('pages written on the PC reach the phone', () async {
      await db.saveEtymologyPage('es', 'dar luz verde',
          jsonEncode({'headword': 'dar luz verde', 'summary_ru': 'Образ светофора.'}),
          'Claude');
      // A real second file: two in-memory databases would be the same one.
      final tmp = Directory.systemTemp.createTempSync('lt_ety_x');
      final phone = DatabaseService();
      await phone.init(path: '${tmp.path}/phone.db');
      expect(await phone.etymologyPage('es', 'dar luz verde'), isNull);
      final bundle = jsonDecode(jsonEncode(
          await ExchangeService(db).buildBundle())) as Map<String, dynamic>;
      await ExchangeService(phone).importBundle(bundle);
      final row = await phone.etymologyPage('es', 'Dar luz verde');
      expect(row?['json'], contains('Образ светофора'));
      await phone.close();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  group('word choice', () {
    test('model options parse, best first, with the rewritten sentence', () {
      final c = WordChoice.fromJson({
        'meaning_ru': 'внести вклад',
        'issues_ru': ['«qué yo debo» → «¿Qué debo…?»: yo лишнее'],
        'options': [
          {
            'word': 'aportar', 'pattern': 'aportar algo a algo',
            'gloss_ru': 'вносить (вклад)', 'register': 'нейтр.', 'fit': 'best',
            'why_ru': 'именно вклад', 'sentence': '¿Qué debo aportar al proyecto?',
            'collocations': ['aportar ideas'],
          },
          {
            'word': 'llevar', 'pattern': 'llevar algo a', 'gloss_ru': 'отнести',
            'register': 'нейтр.', 'fit': 'wrong', 'why_ru': 'физически',
            'sentence': '¿Qué debo llevar al proyecto?', 'collocations': [],
          },
        ],
        'best_sentence': '¿Qué debo aportar al proyecto?',
      }, focus: 'привнести', backend: 'Claude');
      expect(c.options.first.fits, isTrue);
      expect(c.options.last.fit, 'wrong');
      expect(c.bestSentence, '¿Qué debo aportar al proyecto?');
      expect(c.fromDictionary, isFalse);
    });

    test('the free dictionary gives options with back-translations', () {
      final data = [
        [
          ['aportar', 'привнести', null, null, 1]
        ],
        [
          [
            'глагол',
            ['aportar', 'introducir', 'traer'],
            [
              ['aportar', ['внести', 'привнести', 'вложить'], null, 0.3],
              ['introducir', ['ввести', 'внедрить'], null, 0.1],
              ['traer', ['принести', 'привезти'], null, 0.05],
            ],
            'привнести',
            2
          ]
        ],
        'ru'
      ];
      final c = WordChoiceService.parseDictionary(data, 'привнести');
      expect(c.options.map((o) => o.word), ['aportar', 'introducir', 'traer']);
      expect(c.options.first.glossRu, 'внести, привнести, вложить');
      expect(c.fromDictionary, isTrue);
    });

    test('the prompt names the focus word and the reader hint', () {
      final m = WordChoiceService.buildUserMessage(
          source: 'что я должен привнести в проект?',
          translation: 'qué yo debo llevar al proyecto?',
          focus: 'привнести',
          srcLang: 'ru',
          tgtLang: 'es',
          hint: 'внести вклад');
      expect(m, contains('FOCUS: «привнести»'));
      expect(m, contains('внести вклад'));
    });
  });

  test('an auto-detected source is served from the cache', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    await db.addTranslation(const TranslationEntry(
        sourceText: 'Привнести в проект',
        translatedText: 'Aportar al proyecto',
        sourceLang: 'ru',
        targetLang: 'es',
        translator: 'claude-choice'));
    final r = await TranslatorService(ConfigService()).translateWithCache(
        'привнести в проект', db,
        targetLang: 'es', sourceLang: 'auto');
    expect(r.text, 'Aportar al proyecto');
    expect(r.sourceLang, 'ru', reason: 'the detected language comes back');
    expect(r.translator, contains('cached'));
    await db.close();
  });

  test('the exchange file is not rebuilt when nothing changed', () async {
    final tmp = Directory.systemTemp.createTempSync('lt_fp');
    final db = DatabaseService();
    await db.init(path: '${tmp.path}/a.db');
    await db.addTranslation(const TranslationEntry(
        sourceText: 'casa', translatedText: 'дом', sourceLang: 'es',
        targetLang: 'ru', translator: 'google'));
    final ex = ExchangeService(db);
    final path = await ex.exportTo('${tmp.path}/x');
    final first = File(path).lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await ex.exportTo('${tmp.path}/x');
    expect(File(path).lastModifiedSync(), first, reason: 'nothing new');
    await db.addTranslation(const TranslationEntry(
        sourceText: 'perro', translatedText: 'собака', sourceLang: 'es',
        targetLang: 'ru', translator: 'google'));
    await ex.exportTo('${tmp.path}/x');
    expect(File(path).lastModifiedSync().isAfter(first), isTrue);
    await db.close();
    tmp.deleteSync(recursive: true);
  });
}
