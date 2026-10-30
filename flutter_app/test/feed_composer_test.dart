/// News-feed composer: key forms of the user's mistakes, the prompt the
/// model sees, target planning, and one full compose round-trip through a
/// stub LLM (validation, spans, tasks, persistence).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:lingua_trace/models/news_article.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/feed_composer.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

NewsArticle _article(int id, String outlet, String title, String lead) =>
    NewsArticle(
      id: id,
      url: 'https://example.com/$id',
      urlHash: 'h$id',
      sourceId: outlet.toLowerCase(),
      outlet: outlet,
      lang: 'es',
      variety: 'es-ES',
      title: title,
      lead: lead,
      publishedAt: DateTime.now().toUtc(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('keyForms: the minimal changed fragment of a correction', () {
    test('inserted preposition', () {
      expect(FeedComposer.keyForms(
              'no me atrevo molestar', 'no me atrevo a molestar'),
          ('atrevo molestar', 'atrevo a molestar'));
    });
    test('inserted article', () {
      expect(FeedComposer.keyForms(
              'compro billetes para autobús', 'compro billetes para el autobús'),
          ('para autobús', 'para el autobús'));
    });
    test('replaced word at the start', () {
      expect(FeedComposer.keyForms('a 18 de agosto', 'el 18 de agosto'),
          ('a 18', 'el 18'));
    });
    test('long rewrite keeps the tail', () {
      final (w, r) = FeedComposer.keyForms(
          'para estar a las 14:15 en Santander por autobús',
          'para estar en Santander a las 14:15 en autobús');
      expect(w, 'por autobús');
      expect(r, 'en autobús');
    });
  });

  group('patternWords: which corrections are reusable patterns', () {
    test('added function words are a pattern', () {
      expect(FeedComposer.patternWords('atrevo molestar', 'atrevo a molestar'),
          ['a']);
      expect(FeedComposer.patternWords('a 18', 'el 18'), ['el']);
      expect(FeedComposer.patternWords('por autobús', 'en autobús'), ['en']);
    });
    test('a changed content word is not', () {
      expect(FeedComposer.patternWords('compro', 'compré'), isEmpty);
      expect(FeedComposer.patternWords('más tempranos', 'más temprano'), isEmpty);
    });
  });

  test('user message carries sources, targets and the reader mistake', () {
    final slot = FeedSlot(
      const [
        FeedTargetSpec(
          id: 'T1',
          itemId: 1,
          kind: 'mistake',
          canonical: 'atrevo a molestar',
          wrongForm: 'atrevo molestar',
          construction: 'es.regimen',
          gloss: 'Управление глагола',
        ),
        FeedTargetSpec(
            id: 'T2',
            itemId: 2,
            kind: 'idiom',
            canonical: 'echar leña al fuego',
            gloss: 'подливать масла в огонь'),
      ],
      [
        _article(1, 'El País', 'El Gobierno aprueba la subida del salario mínimo',
            'El Consejo de Ministros ha aprobado este martes una subida del 4%.'),
      ],
    );
    final msg = FeedComposer.buildUserMessage(slot, 'es');
    expect(msg, contains('[S1] El País'));
    expect(msg, contains('Titular: El Gobierno aprueba'));
    expect(msg, contains('[T1] kind=mistake required=yes construction=es.regimen'));
    expect(msg, contains('reader_mistake: «atrevo molestar» → «atrevo a molestar»'));
    expect(msg, contains('canonical: echar leña al fuego — ru: подливать масла в огонь'));
  });

  test('schema is valid for structured outputs (objects closed, required ⊆ properties)',
      () {
    void walk(Map<String, dynamic> s) {
      if (s['type'] == 'object') {
        expect(s['additionalProperties'], isFalse);
        final props = (s['properties'] as Map).keys.toSet();
        expect(props.containsAll(s['required'] as List), isTrue);
        for (final p in (s['properties'] as Map).values) {
          walk(p as Map<String, dynamic>);
        }
      } else if (s['type'] == 'array') {
        walk(s['items'] as Map<String, dynamic>);
      }
    }

    walk(FeedComposer.schema);
  });

  group('compose round-trip with a stub model', () {
    late HttpServer server;
    late DatabaseService db;
    late int mistakeItemId;
    Map<String, dynamic>? nextReply;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(nextReply)}
            }
          ]
        }));
        await req.response.close();
      });
      db = DatabaseService();
      await db.init(path: inMemoryDatabasePath);
      await db.addMistake(const Mistake(
          original: 'no me atrevo molestar',
          corrected: 'no me atrevo a molestar',
          lang: 'es',
          construction: 'es.regimen'));
      mistakeItemId = (await db.getItems()).single.id!;
    });

    tearDown(() async {
      await server.close(force: true);
      await db.close();
    });

    test('a valid draft is stored with spans and tasks', () async {
      final cfg = ConfigService()
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${server.port}/v1'
        ..customModel = 'gemini-2.0-flash';
      final composer =
          FeedComposer(LlmRouter(cfg, ai: AiClient(cfg)), db);

      const body = 'Según informa El País, el Ejecutivo ha dado luz verde este '
          'martes a un aumento del 4% en el salario mínimo. La medida llega tras '
          'meses de negociación con los sindicatos y la patronal.\n\n'
          'Los empresarios no se atrevieron a rechazar el acuerdo en público, '
          'aunque advirtieron de sus efectos sobre el empleo. Los sindicatos, '
          'por su parte, celebraron la decisión y pidieron que la subida llegue '
          'también a los convenios colectivos del sector privado.\n\n'
          'El Ejecutivo defendió que la medida protege el poder adquisitivo de '
          'los trabajadores con menos ingresos, en un contexto de precios '
          'todavía altos en la vivienda y la alimentación básica del país.';
      nextReply = {
        'story_source_ids': ['S1'],
        'headline': 'El salario mínimo sube un 4%',
        'body': body,
        'attribution': 'Según El País',
        'targets_used': [
          {
            'target_id': 'T1',
            'form_used': 'no se atrevieron a rechazar',
            'occurrence': 1,
            'note_ru': 'atreverse a + infinitivo',
          },
        ],
        'skipped': <Object>[],
        'fact_check': [
          {'claim': 'subida del 4%', 'source_id': 'S1'},
        ],
        'tasks': [
          {
            'kind': 'choice',
            'target_id': 'T1',
            'prompt_ru': 'Выберите верный вариант',
            'text': 'Los empresarios no se atrevieron ____ rechazar el acuerdo en público, aunque advirtieron de sus efectos sobre el empleo.',
            'options': ['a', '—'],
            'answer': 'a',
          },
          {
            'kind': 'retell',
            'target_id': '',
            'prompt_ru': 'Перескажите новость в двух предложениях',
            'text': '',
            'options': <String>[],
            'answer': 'El Gobierno sube el salario mínimo un 4%.',
          },
        ],
      };

      final slot = FeedSlot(
        [
          FeedTargetSpec(
            id: 'T1',
            itemId: mistakeItemId,
            kind: 'mistake',
            canonical: 'atrevo a molestar',
            wrongForm: 'atrevo molestar',
            construction: 'es.regimen',
          ),
        ],
        [
          _article(
              7,
              'El País',
              'El Gobierno aprueba la subida del salario mínimo',
              'El Consejo de Ministros ha aprobado este martes una subida del '
                  'salario mínimo del 4% tras meses de negociación.'),
        ],
      );
      final editionId = await db.createEdition('es', 1);
      final id = await composer.composeOne(slot, editionId, 'es');
      expect(id, isNotNull,
          reason: 'the stub draft satisfies every validation rule');

      final item = (await db.getFeedItems()).single;
      expect(item.outlet, 'El País');
      expect(item.targets.single.form, 'no se atrevieron a rechazar');
      expect(
          item.body.substring(item.targets.single.start, item.targets.single.end),
          'no se atrevieron a rechazar');
      expect(item.tasks.map((t) => t.kind), ['choice', 'retell']);
      expect(item.tasks.first.itemId, mistakeItemId);

      // Reading, then a correct answer, moves the schedule.
      await db.markFeedItemRead(item.id!);
      await db.recordRecall(mistakeItemId, true);
      final it = (await db.getItems()).single;
      expect(it.exposures, 1);
      expect(it.recallOk, 1);
      expect(it.stage, 1);
    });
  });
}
