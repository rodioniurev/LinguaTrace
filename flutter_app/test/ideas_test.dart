/// «Идеи»: long dictation keeps going and saves every sentence, voice
/// commands work, notes are researched in the background (with web search
/// on the API), articles come in from pages and files, and everything
/// travels between the phone and the PC.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/idea.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/ai_types.dart';
import 'package:lingua_trace/services/exchange_service.dart';
import 'package:lingua_trace/services/idea_enricher.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:lingua_trace/services/long_dictation.dart';
import 'package:lingua_trace/services/source_ingest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A recogniser driven by the test.
class _FakeEngine implements SpeechEngine {
  int starts = 0;
  int flushes = 0;
  void Function(String, bool)? result;
  void Function()? end;
  void Function(String, bool)? error;
  void Function(String?)? trouble;
  bool refuse = false;
  /// What the recogniser still delivers while being stopped / flushed.
  String? lastWordsOnStop;
  String? lastWordsOnFlush;

  @override
  Future<bool> startSegment({
    required String lang,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onEnd,
    required void Function(String code, bool permanent) onError,
    void Function(String? trouble)? onTrouble,
    void Function(String line)? onLog,
  }) async {
    if (refuse) return false;
    starts++;
    result = onResult;
    end = onEnd;
    error = onError;
    trouble = onTrouble;
    return true;
  }

  @override
  Future<void> stopSegment() async {
    final w = lastWordsOnStop;
    if (w != null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      result?.call(w, true);
    }
  }

  @override
  Future<void> flush() async {
    flushes++;
    final w = lastWordsOnFlush;
    if (w != null) {
      Future<void>.delayed(
          const Duration(milliseconds: 20), () => result?.call(w, true));
    }
  }
}

Future<void> _tick([int ms = 30]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('long dictation', () {
    late _FakeEngine engine;
    late LongDictation d;
    var committed = '';
    final commands = <DictationCommand>[];
    final troubles = <String?>[];
    String? fatal;

    setUp(() async {
      engine = _FakeEngine();
      commands.clear();
      troubles.clear();
      fatal = null;
      d = LongDictation(engine,
          lang: 'ru',
          onUpdate: (c, _) => committed = c,
          onCommand: commands.add,
          onFatal: (c) => fatal = c,
          onTrouble: troubles.add,
          restartDelay: const Duration(milliseconds: 5));
      await d.start();
    });

    test('segments are joined and the recogniser restarts after a pause', () async {
      engine.result!('первая мысль о проекте', true);
      engine.end!();
      await _tick();
      expect(engine.starts, 2, reason: 'a new segment starts at once');
      engine.result!('вторая часть', true);
      expect(committed, 'Первая мысль о проекте. Вторая часть');
    });

    test('silence and "not recognised" just restart, without counting', () async {
      for (var i = 0; i < 12; i++) {
        engine.error!('error_no_match', false);
        await _tick();
      }
      expect(fatal, isNull);
      expect(d.active, isTrue);
    });

    test('a segment cut off before its final result keeps its words', () async {
      engine.result!('незаконченная фраза', false);
      engine.end!();
      await _tick();
      expect(committed, 'Незаконченная фраза');
    });

    test('«новая мысль» at the end of a segment', () async {
      engine.result!('последнее про батарею новая мысль', true);
      expect(committed, 'Последнее про батарею');
      expect(commands, [DictationCommand.newNote]);
      expect(d.takeText(), 'Последнее про батарею');
      engine.end!();
      await _tick();
      engine.result!('следующая идея', true);
      expect(committed, 'Следующая идея');
    });

    test('«стоп запись» and a stop keep unfinished words', () async {
      engine.result!('стоп запись', true);
      expect(commands, [DictationCommand.stop]);
      engine.result!('ещё немного', false);
      expect(await d.stop(), 'Ещё немного');
      expect(d.active, isFalse);
    });

    test('a failing recogniser never ends the dictation by itself', () async {
      // error_client is what a too early restart got — it ended everything.
      for (var i = 0; i < 3; i++) {
        engine.error!(i.isEven ? 'error_client' : 'error_network', false);
        await _tick(i == 0 ? 450 : 1300);
      }
      expect(fatal, isNull);
      expect(d.active, isTrue);
      expect(troubles.first, 'error_client');
      expect(engine.starts, greaterThan(1), reason: 'it keeps restarting');
      engine.result!('снова слышно', true);
      expect(troubles.last, isNull, reason: 'hearing again clears the warning');
      expect(committed, 'Снова слышно');
    });

    test('a native engine reports what it waits out', () async {
      engine.trouble!('error_background');
      engine.trouble!(null);
      expect(troubles, ['error_background', null]);
      expect(d.active, isTrue);
    });

    test('the phrase spoken at «Стоп» is kept', () async {
      engine.result!('первая фраза', true);
      engine.result!('последние сло', false);
      engine.lastWordsOnStop = 'последние слова перед стопом';
      expect(await d.stop(), 'Первая фраза. Последние слова перед стопом');
    });

    test('«Новая мысль» mid-phrase waits for the phrase to finish', () async {
      engine.result!('про аккумулятор', true);
      engine.result!('и про вес', false);
      engine.lastWordsOnFlush = 'и про вес рюкзака';
      final note = await d.takeFinishedText();
      expect(engine.flushes, 1);
      expect(note, 'Про аккумулятор. И про вес рюкзака');
      engine.result!('следующая мысль про цену', true);
      expect(committed, 'Следующая мысль про цену');
    });

    test('a late final does not repeat words already taken', () async {
      engine.result!('начало фразы', false);
      final note =
          await d.takeFinishedText(wait: const Duration(milliseconds: 30));
      expect(note, 'Начало фразы');
      engine.result!('начало фразы и её конец', true);
      expect(committed, 'И её конец');
    });

    test('no permission ends the dictation and says why', () async {
      engine.result!('успел сказать', false);
      engine.error!('error_insufficient_permissions', true);
      expect(fatal, 'error_insufficient_permissions');
      expect(committed, 'Успел сказать');
      expect(d.active, isFalse);
    });

    test('«что думаешь?» hands the thought to Claude', () async {
      engine.result!('батарея на клапане рюкзака что думаешь', true);
      expect(committed, 'Батарея на клапане рюкзака');
      expect(commands, [DictationCommand.discuss]);
      expect(LongDictation.splitCommand('Qué opinas', 'es'),
          ('', DictationCommand.discuss));
    });

    test('commands in other languages; plain text untouched', () {
      expect(LongDictation.splitCommand('Nueva idea', 'es'),
          ('', DictationCommand.newNote));
      expect(LongDictation.splitCommand('so that is it. Stop recording', 'en'),
          ('so that is it.', DictationCommand.stop));
      expect(LongDictation.splitCommand('мысль о новом мысль', 'ru'),
          ('мысль о новом мысль', null));
      expect(LongDictation.joinSegments('Уже есть точка.', 'дальше'),
          'Уже есть точка. Дальше');
    });
  });

  group('projects, notes, sources and the exchange', () {
    late DatabaseService db;
    setUp(() async {
      db = DatabaseService();
      await db.init(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    test('a dictated note grows, waits for research, then shows its result', () async {
      final p = await db.addIdeaProject('Солнечный рюкзак',
          context: 'Рюкзак с панелями для туристов', kind: 'invention');
      final n = await db.addIdeaNote(p, 'панели на клапане');
      await db.updateIdeaNoteText(n, 'панели на клапане и на лямках');
      await db.setIdeaNoteStatus(n, 'queued');
      expect((await db.pendingIdeaNotes()).single.text, 'панели на клапане и на лямках');
      await db.addIdeaInsight(p, noteId: n, text: '### Суть\nПанели…', links: '- [Goal Zero](https://example.com/gz) — аналог');
      await db.setIdeaNoteStatus(n, 'done', cleanText: 'Панели на клапане и на лямках.');
      expect(await db.pendingIdeaNotes(), isEmpty);
      final i = (await db.ideaInsights(p)).single;
      expect(i.links.single.url, 'https://example.com/gz');
      expect((await db.ideaProjects()).single.notes, 1);
    });

    test('the same link is stored once per project', () async {
      final p = await db.addIdeaProject('X');
      final a = await db.addIdeaSource(p, kind: 'found', url: 'https://a.example/1');
      final b = await db.addIdeaSource(p, kind: 'found', url: 'https://a.example/1');
      expect(a, b);
    });

    test('dictated on the phone, researched on the PC, back on the phone', () async {
      // Two real files: two in-memory databases would be one and the same.
      final tmp = Directory.systemTemp.createTempSync('lt_ideas_x');
      final pc = DatabaseService();
      await pc.init(path: '${tmp.path}/pc.db');
      final db = pc;
      final phone = DatabaseService();
      await phone.init(path: '${tmp.path}/phone.db');
      final p = await phone.addIdeaProject('Статья о памяти');
      final n = await phone.addIdeaNote(p, 'мысль про интервальные повторения');
      await phone.setIdeaNoteStatus(n, 'queued');
      Future<Map<String, dynamic>> bundle(DatabaseService d) async =>
          jsonDecode(jsonEncode(await ExchangeService(d).buildBundle()))
              as Map<String, dynamic>;

      final toPc = await ExchangeService(db).importBundle(await bundle(phone));
      expect(toPc.ideas, 2);
      final pcNote = (await db.pendingIdeaNotes()).single;
      // The PC researches it (a newer update).
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await db.setIdeaNoteStatus(pcNote.id!, 'done', cleanText: 'Мысль про интервальные повторения.');
      await db.addIdeaInsight(pcNote.projectId, noteId: pcNote.id, text: 'Разбор');

      await ExchangeService(phone).importBundle(await bundle(db));
      final back = (await phone.ideaNotes(p)).single;
      expect(back.status, 'done');
      expect(back.cleanText, 'Мысль про интервальные повторения.');
      expect((await phone.ideaInsights(p)).single.noteId, back.id);

      // Deleting the project on the phone deletes it on the PC too.
      await phone.deleteIdeaProject(p);
      await ExchangeService(db).importBundle(await bundle(phone));
      expect(await db.ideaProjects(), isEmpty);
      expect(await db.pendingIdeaNotes(), isEmpty);
      await phone.close();
      await pc.close();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  group('background research', () {
    late HttpServer model;
    late DatabaseService db;
    final prompts = <String>[];
    String reply = '';
    Future<void> Function()? onRequest;

    setUp(() async {
      prompts.clear();
      onRequest = null;
      model = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      model.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        prompts.add(((body['messages'] as List).last as Map)['content'] as String);
        await onRequest?.call();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {
              'message': {'content': reply}
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

    IdeaEnricher enricher() {
      final cfg = ConfigService()
        ..aiProvider = 'custom'
        ..customApiBaseUrl = 'http://127.0.0.1:${model.port}/v1'
        ..customModel = 'gemini-2.0-flash';
      return IdeaEnricher(LlmRouter(cfg, ai: AiClient(cfg)), db, cfg);
    }

    test('a note is cleaned, analysed and its links kept as found sources', () async {
      final p = await db.addIdeaProject('Рюкзак', context: 'для походов', kind: 'invention');
      await db.addIdeaSource(p, kind: 'text', title: 'Моя заметка',
          content: 'Длинный текст статьи', summary: '- главное: вес');
      final n = await db.addIdeaNote(p, 'панели на клапане рюкзака эээ на клапане');
      await db.setIdeaNoteStatus(n, 'queued');
      reply = '===CLEAN===\nПанели на клапане рюкзака.\n'
          '===INSIGHT===\n### Суть\nПанели там, где солнце.\n'
          '===SOURCES===\n- [Goal Zero Nomad](https://example.com/nomad) — готовый аналог\n';
      expect(await enricher().processPending(), 1);
      final note = await db.ideaNote(n);
      expect(note!.status, 'done');
      expect(note.cleanText, 'Панели на клапане рюкзака.');
      expect((await db.ideaInsights(p)).single.text, contains('Панели там, где солнце'));
      expect((await db.ideaSources(p)).where((s) => s.kind == 'found').single.url,
          'https://example.com/nomad');
      expect(prompts.last, contains('CONTEXT (the author\'s words): для походов'));
      expect(prompts.last, contains('- главное: вес'), reason: 'sources are context');
    });

    test('without AI the note waits; a failing AI keeps it for later', () async {
      final p = await db.addIdeaProject('X');
      final n = await db.addIdeaNote(p, 'мысль');
      await db.setIdeaNoteStatus(n, 'queued');
      final off = IdeaEnricher(LlmRouter(ConfigService()), db, ConfigService());
      expect(await off.processPending(), 0);
      expect((await db.ideaNote(n))!.status, 'queued');

      final configured = enricher();
      await model.close(force: true); // the AI is configured but unreachable
      expect(await configured.processPending(), 0);
      expect((await db.ideaNote(n))!.status, 'offline');
      expect(await db.pendingIdeaNotes(), hasLength(1), reason: 'retried later');
    });

    test('a thought dictated while another is researched is not left waiting',
        () async {
      final p = await db.addIdeaProject('X');
      final a = await db.addIdeaNote(p, 'первая мысль');
      final b = await db.addIdeaNote(p, 'вторая мысль');
      reply = '===CLEAN===\nМысль.\n===INSIGHT===\n### Суть\nДа.\n===SOURCES===\n';
      final e = enricher();
      onRequest = () async {
        onRequest = null;
        await e.enqueue(b); // spoken while the first one is being researched
      };
      await db.setIdeaNoteStatus(a, 'queued');
      expect(await e.processPending(), 2);
      expect((await db.ideaNote(b))!.status, 'done');
    });

    test('a discussion turn: Claude answers, the turn is kept, not researched',
        () async {
      final p = await db.addIdeaProject('Рюкзак', context: 'для походов');
      await db.addIdeaNote(p, 'панели на клапане рюкзака', status: 'queued');
      reply = 'Сильная идея про клапан. А как панель переживёт дождь?';
      final (id, text) = await enricher().discuss(p);
      expect(text, contains('дождь'));
      final turn = (await db.ideaNote(id))!;
      expect(turn.source, 'claude');
      expect(turn.status, 'done');
      expect((await db.pendingIdeaNotes()).map((n) => n.source),
          isNot(contains('claude')), reason: 'Claude\'s turn is not researched');
      expect(prompts.last, contains('AUTHOR: панели на клапане рюкзака'));
      expect(prompts.last, contains('CONTEXT (the author\'s words): для походов'));

      // Its question is context for the research of the author's answer.
      final answer = await db.addIdeaNote(p, 'плёнка ETFE не боится воды');
      final msg = IdeaEnricher.buildEnrichMessage(
          (await db.ideaProject(p))!,
          const [],
          await db.ideaNotes(p),
          (await db.ideaNote(answer))!);
      expect(msg, contains('(Claude asked) Сильная идея'));
    });

    test('answers without the markers become the analysis', () {
      final e = IdeaEnricher.parseEnrichment('Просто текст https://x.example/a.');
      expect(e.clean, '');
      expect(e.insight, 'Просто текст https://x.example/a.');
      expect(e.links.single.url, 'https://x.example/a');
    });
  });

  group('web search on the Claude API', () {
    late HttpServer api;
    final bodies = <Map<String, dynamic>>[];

    setUp(() async {
      bodies.clear();
      api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        bodies.add(body);
        req.response.headers.contentType = ContentType.json;
        // First a paused server turn, then the answer with a citation.
        req.response.write(jsonEncode(bodies.length == 1
            ? {
                'stop_reason': 'pause_turn',
                'content': [
                  {'type': 'server_tool_use', 'id': 's1', 'name': 'web_search', 'input': {'query': 'solar backpack'}},
                  {
                    'type': 'web_search_tool_result',
                    'tool_use_id': 's1',
                    'content': [
                      {'type': 'web_search_result', 'url': 'https://example.com/b', 'title': 'Other result'},
                    ],
                  },
                ],
                'usage': {'input_tokens': 1000, 'output_tokens': 10},
              }
            : {
                'stop_reason': 'end_turn',
                'content': [
                  {
                    'type': 'text',
                    'text': 'Такие рюкзаки уже есть.',
                    'citations': [
                      {'type': 'web_search_result_location', 'url': 'https://example.com/a', 'title': 'Cited'},
                    ],
                  },
                ],
                'usage': {'input_tokens': 2000, 'output_tokens': 50},
              }));
        await req.response.close();
      });
    });
    tearDown(() => api.close(force: true));

    AiClient client() {
      final cfg = ConfigService()
        ..aiProvider = 'claude'
        ..anthropicApiKey = 'sk-ant-api03-test'
        ..fastModel = 'claude-sonnet-5';
      return AiClient(cfg, anthropicBaseUrl: 'http://127.0.0.1:${api.port}');
    }

    test('the tool is declared, a paused turn is resumed, sources collected', () async {
      final r = await client().completeResult(
          system: 's', user: 'u', tier: 'fast', webSearch: true);
      expect(bodies.first['tools'], [
        {'type': 'web_search_20260209', 'name': 'web_search', 'max_uses': 5}
      ]);
      expect(bodies, hasLength(2));
      final resumed = bodies.last['messages'] as List;
      expect((resumed.last as Map)['role'], 'assistant',
          reason: 'the paused turn goes back unchanged');
      expect(r.text, 'Такие рюкзаки уже есть.');
      expect(r.sources.map((s) => s.url),
          ['https://example.com/a', 'https://example.com/b'],
          reason: 'cited pages first');
      expect(r.searchedWeb, isTrue);
      expect(r.inputTokens, 3000);
    });

    test('a PDF goes as a document block before the request text', () async {
      await client().completeResult(
          system: 's',
          user: 'Summarize',
          tier: 'fast',
          documents: [AiDocument('application/pdf', Uint8List.fromList([1, 2, 3]), 'a.pdf')]);
      final content = ((bodies.first['messages'] as List).first as Map)['content'] as List;
      expect((content.first as Map)['type'], 'document');
      expect(((content.first as Map)['source'] as Map)['data'], base64Encode([1, 2, 3]));
      expect((content.last as Map)['text'], 'Summarize');
    });

    test('Haiku uses the basic search tool', () {
      expect(AiClient.webSearchToolType('claude-haiku-4-5'), 'web_search_20250305');
      expect(AiClient.webSearchToolType('claude-haiku-5-5'), 'web_search_20250305');
      expect(AiClient.webSearchToolType('claude-opus-5'), 'web_search_20260209');
      expect(AiClient.webSearchToolType('claude-opus-5-5'), 'web_search_20260209');
      expect(AiClient.webSearchToolType('claude-sonnet-5-5'), 'web_search_20260209');
    });
  });

  test('a web page becomes its readable text', () {
    const html = '''
<html><head><title>Солнечные &amp; рюкзаки</title><script>var x = 1;</script></head>
<body><nav>Меню</nav><article><h1>Заголовок</h1><p>Первый абзац&nbsp;текста.</p>
<p>Второй &laquo;абзац&raquo;.</p></article><footer>Подвал</footer></body></html>''';
    final (title, text) = SourceIngest.htmlToText(html);
    expect(title, 'Солнечные & рюкзаки');
    expect(text, 'Заголовок\nПервый абзац текста.\nВторой «абзац».');
  });

  test('the model\'s link list: titled lines, bare addresses, no repeats', () {
    final links = IdeaInsight.parseLinks('''
- [Goal Zero](https://example.com/gz) — готовый аналог
* [Патент US123](https://patents.example/US123)
Ещё см. https://example.com/gz и https://blog.example/post.
''');
    expect(links.map((l) => l.url), [
      'https://example.com/gz',
      'https://patents.example/US123',
      'https://blog.example/post',
    ]);
    expect(links.first.title, 'Goal Zero');
    expect(links.first.why, 'готовый аналог');
    expect(links[1].why, '');
  });
}
