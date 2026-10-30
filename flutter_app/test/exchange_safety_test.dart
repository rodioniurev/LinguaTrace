/// Exchange between the PC and the phone must never undo what the user did
/// on either device (review 2026-09-26): decisions and review progress keep
/// their own clocks, deletions travel as tombstones, a file from another
/// version still merges, counters add up, the later answer wins, exports
/// never collide, and the file carries no more private text than needed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:lingua_trace/models/translation_entry.dart';
import 'package:lingua_trace/services/exchange_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TranslationEntry _tr(String s, {String src = 'es', String tgt = 'ru'}) =>
    TranslationEntry(
        sourceText: s,
        translatedText: 'x',
        sourceLang: src,
        targetLang: tgt,
        translator: 'google');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late DatabaseService pc;
  late DatabaseService phone;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lt_exchange_safety');
    pc = DatabaseService();
    await pc.init(path: '${tmp.path}/pc.db');
    phone = DatabaseService();
    await phone.init(path: '${tmp.path}/phone.db');
  });

  tearDown(() async {
    await pc.close();
    await phone.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // Through JSON, as the real file goes.
  Future<Map<String, dynamic>> bundleOf(DatabaseService d,
          {bool fullHistory = true}) async =>
      jsonDecode(jsonEncode(await ExchangeService(d,
              fullHistory: () => fullHistory)
          .buildBundle())) as Map<String, dynamic>;
  Future<ExchangeReport> pcToPhone() async =>
      ExchangeService(phone).importBundle(await bundleOf(pc));
  Future<ExchangeReport> phoneToPc() async =>
      ExchangeService(pc).importBundle(await bundleOf(phone));

  Future<Map<String, Object?>> itemRow(
          DatabaseService d, String kind, String text) async =>
      (await d.sqlite.query('learning_items',
              where: 'kind = ? AND lang = ? AND norm_key = ?',
              whereArgs: [kind, 'es', DatabaseService.normalize(text)]))
          .single;

  // A touch "later" than anything in the test: lookups and exposures move
  // last_seen, which must not decide status or schedule.
  const later = '2099-01-01 00:00:00';
  Future<void> setClock(DatabaseService d, int id, String col, String ts) =>
      d.sqlite.update('learning_items', {col: ts},
          where: 'id = ?', whereArgs: [id]);

  group('a later touch elsewhere never undoes a decision', () {
    test('«убрать из тетради» on the PC survives a lookup on the phone',
        () async {
      final id = await pc.upsertItem(
          kind: 'idiom', lang: 'es', text: 'a toda costa', status: 'learning');
      await pcToPhone();
      await pc.setItemStatus(id, 'ignored');
      final pid = (await phone.findItem('idiom', 'es', 'a toda costa'))!.id!;
      await phone.addEvent(pid, 'lookup', surface: 'feed');
      await setClock(phone, pid, 'last_seen', later);

      await phoneToPc();
      expect((await itemRow(pc, 'idiom', 'a toda costa'))['status'], 'ignored');
      expect((await pc.feedCandidates('es')).any((c) => c.id == id), isFalse);
      await pcToPhone();
      expect(
          (await itemRow(phone, 'idiom', 'a toda costa'))['status'], 'ignored');
    });

    test('«это не ошибка» on the PC survives an exposure on the phone',
        () async {
      final mid = await pc.addMistake(const Mistake(
          original: 'no me atrevo molestar',
          corrected: 'no me atrevo a molestar',
          lang: 'es'));
      await pcToPhone();
      await pc.rejectMistake(mid);
      final ph =
          (await phone.findItem('mistake', 'es', 'no me atrevo a molestar'))!;
      await phone.addEvent(ph.id, 'exposure', surface: 'feed');
      await setClock(phone, ph.id!, 'last_seen', later);

      await phoneToPc();
      expect(await pc.mistakeCount(), 0);
      expect(
          (await itemRow(pc, 'mistake', 'no me atrevo a molestar'))['status'],
          'ignored');
      await pcToPhone();
      expect(
          (await itemRow(phone, 'mistake', 'no me atrevo a molestar'))[
              'status'],
          'ignored');
      expect(await phone.mistakeCount(), 0);
    });

    test('«В тетрадь» on the PC survives a later lookup on the phone',
        () async {
      await pc.upsertItem(kind: 'word', lang: 'es', text: 'empresario');
      await pcToPhone();
      await pc.upsertItem(
          kind: 'word', lang: 'es', text: 'empresario', status: 'learning');
      final pid = await phone.upsertItem(
          kind: 'word', lang: 'es', text: 'empresario');
      await phone.addEvent(pid, 'lookup', surface: 'translate');
      await setClock(phone, pid, 'last_seen', later);

      await phoneToPc();
      expect((await itemRow(pc, 'word', 'empresario'))['status'], 'learning');
      await pcToPhone();
      expect(
          (await itemRow(phone, 'word', 'empresario'))['status'], 'learning');
    });

    test('review progress on the phone survives a lookup on the PC', () async {
      final id = await pc.upsertItem(
          kind: 'idiom', lang: 'es', text: 'a toda costa', status: 'learning');
      await pcToPhone();
      final pid = (await phone.findItem('idiom', 'es', 'a toda costa'))!.id!;
      await phone.recordRecall(pid, true);
      final before = await itemRow(phone, 'idiom', 'a toda costa');
      expect(before['stage'], 1);
      await pc.addEvent(id, 'lookup', surface: 'feed');
      await setClock(pc, id, 'last_seen', later);

      await phoneToPc();
      await pcToPhone();
      for (final d in [pc, phone]) {
        final r = await itemRow(d, 'idiom', 'a toda costa');
        expect(r['stage'], 1);
        expect(r['next_due'], before['next_due']);
      }
    });
  });

  group('deleted stays deleted', () {
    test('history and trainings deleted on the PC do not come back',
        () async {
      final tid =
          await pc.addTranslation(_tr('Estimado señor, mi NIE es X1234567Z'));
      final trid = await pc.addTraining('es', '# Sesión');
      await pcToPhone();
      expect(await phone.getHistory(), hasLength(1));
      await pc.deleteTranslation(tid);
      await pc.deleteTraining(trid);

      await phoneToPc();
      expect(await pc.getHistory(), isEmpty);
      expect(await pc.getTrainings(), isEmpty);
      // …and the deletion reaches the phone.
      final r = await pcToPhone();
      expect(r.deleted, 2);
      expect(await phone.getHistory(), isEmpty);
      expect(await phone.getTrainings(), isEmpty);
    });

    test('a replaced keystroke fragment does not return', () async {
      final id = await pc.addTranslation(_tr('добры', src: 'ru', tgt: 'es'));
      await pcToPhone();
      await pc.sqlite.update('translations', {'timestamp': '2026-09-26 09:00:00'},
          where: 'id = ?', whereArgs: [id]);
      // The phone has the fragment with the PC's original timestamp; make the
      // PC's copy match before it is replaced.
      final phoneRow = (await phone.sqlite.query('translations')).single;
      await pc.sqlite.update(
          'translations', {'timestamp': phoneRow['timestamp']},
          where: 'id = ?', whereArgs: [id]);
      await pc.replaceTranslation(id, _tr('добрый день,', src: 'ru', tgt: 'es'));

      await phoneToPc();
      expect((await pc.getHistory()).map((t) => t.sourceText),
          ['добрый день,']);
      await pcToPhone();
      expect((await phone.getHistory()).map((t) => t.sourceText),
          ['добрый день,']);
    });
  });

  test('a column this version does not know is dropped, not fatal', () async {
    await pc.addTranslation(_tr('casa'));
    await pc.upsertItem(kind: 'word', lang: 'es', text: 'casa');
    final b = await bundleOf(pc);
    ((b['learning_items'] as List).first as Map)['difficulty'] = 3;
    ((b['translations'] as List).first as Map)['sentiment'] = 'neutral';
    final r = await ExchangeService(phone).importBundle(b);
    expect(r.items, 1);
    expect(await phone.getHistory(), hasLength(1));
  });

  test('counters add up increments made on both devices', () async {
    final id = await pc.upsertItem(kind: 'word', lang: 'es', text: 'casa');
    await pcToPhone();
    await pc.addEvent(id, 'lookup');
    await pc.addEvent(id, 'lookup');
    final pid = (await phone.findItem('word', 'es', 'casa'))!.id!;
    await phone.addEvent(pid, 'lookup');
    await phoneToPc();
    expect((await itemRow(pc, 'word', 'casa'))['lookups'], 3);
    await pcToPhone();
    expect((await itemRow(phone, 'word', 'casa'))['lookups'], 3);
  });

  group('a task answered on both devices', () {
    Future<(int, int)> seedTask() async {
      final ed = await pc.createEdition('es', 1);
      await pc.saveFeedItem(
          FeedItem(editionId: ed, lang: 'es', headline: 'H', body: 'b'),
          const [],
          const [FeedTask(feedItemId: 0, kind: 'retell')]);
      await pcToPhone();
      return (
        (await pc.getFeedItems()).single.tasks.single.id!,
        (await phone.getFeedItems()).single.tasks.single.id!,
      );
    }

    Future<void> answer(
        DatabaseService d, int id, String text, String result, String at) =>
        d.sqlite.update('feed_tasks',
            {'user_answer': text, 'result': result, 'done_at': at},
            where: 'id = ?', whereArgs: [id]);

    test('the later attempt wins on both sides', () async {
      final (pcT, phT) = await seedTask();
      await answer(phone, phT, 'Phone text', 'pending', '2026-09-26 10:00:00');
      await answer(pc, pcT, 'PC text', 'ok', '2026-09-26 11:00:00');
      await pcToPhone();
      await phoneToPc();
      for (final d in [pc, phone]) {
        final t = (await d.getFeedItems()).single.tasks.single;
        expect((t.userAnswer, t.result), ('PC text', 'ok'));
      }
    });

    test('a later phone answer reaches the PC and waits for its grade',
        () async {
      final (pcT, phT) = await seedTask();
      await answer(pc, pcT, 'PC text', 'ok', '2026-09-26 10:00:00');
      await answer(phone, phT, 'Phone text', 'pending', '2026-09-26 11:00:00');
      await phoneToPc();
      final t = (await pc.getFeedItems()).single.tasks.single;
      expect((t.userAnswer, t.result), ('Phone text', 'pending'));
      expect(await pc.pendingFeedTasks(), hasLength(1));
    });

    test('the grade of the same answer replaces «pending»', () async {
      final (pcT, phT) = await seedTask();
      await answer(phone, phT, 'Mi texto', 'pending', '2026-09-26 10:00:00');
      await phoneToPc();
      await answer(pc, pcT, 'Mi texto', 'fixed', '2026-09-26 10:05:00');
      await pcToPhone();
      final t = (await phone.getFeedItems()).single.tasks.single;
      expect((t.userAnswer, t.result), ('Mi texto', 'fixed'));
    });
  });

  test('repeated syncs settle: nothing changes after the first round',
      () async {
    await pc.addMistake(
        const Mistake(original: 'x', corrected: 'y z', lang: 'es'));
    await phone.addMistake(
        const Mistake(original: 'x', corrected: 'y z', lang: 'es'));
    await phone.upsertItem(kind: 'word', lang: 'es', text: 'casa', gloss: 'дом');
    await pc.upsertItem(kind: 'word', lang: 'es', text: 'casa');
    await pc.addTranslation(_tr('casa'));
    final id = await pc.addTranslation(_tr('perro'));
    await pc.deleteTranslation(id);
    await phoneToPc();
    await pcToPhone();
    for (var round = 0; round < 2; round++) {
      expect((await phoneToPc()).total, 0, reason: 'round $round to PC');
      expect((await pcToPhone()).total, 0, reason: 'round $round to phone');
    }
  });

  test('overlapping exports into one folder never collide', () async {
    for (var i = 0; i < 200; i++) {
      await pc.addTranslation(_tr('texto $i'));
    }
    final ex = ExchangeService(pc);
    final dir = '${tmp.path}/exchange';
    final results = await Future.wait([
      for (var i = 0; i < 6; i++) ex.exportTo(dir).then((_) => null, onError: (Object e) => e),
    ]);
    expect(results.whereType<Object>(), isEmpty);
    final files = Directory(dir).listSync().map((f) => f.path).toList();
    expect(files, hasLength(1), reason: 'no temp files left: $files');
    final b = jsonDecode(File(files.single).readAsStringSync()) as Map;
    expect((b['translations'] as List), hasLength(200));
  });

  group('privacy', () {
    test('by default only short lookups travel; long texts stay here',
        () async {
      await pc.addTranslation(_tr('casa'));
      await pc.addTranslation(_tr(
          'Estimado señor: le escribo para solicitar la renovación de mi '
          'tarjeta de residencia, cuyo número es X1234567Z.'));
      final short = await bundleOf(pc, fullHistory: false);
      expect((short['translations'] as List).map((t) => (t as Map)['source_text']),
          ['casa']);
      final full = await bundleOf(pc, fullHistory: true);
      expect(full['translations'] as List, hasLength(2));
    });

    test('a mistake keeps only the sentence it was found in', () async {
      await pc.addMistake(const Mistake(
          original: 'atrevo molestar',
          corrected: 'atrevo a molestar',
          lang: 'es',
          context: 'Mi NIE es X1234567Z. No me atrevo molestar a la vecina. '
              'Vivo en la calle Mayor 5.'));
      final b = await bundleOf(pc);
      expect(((b['mistakes'] as List).single as Map)['context'],
          'No me atrevo molestar a la vecina.');
    });

    test('contextSnippet: nothing when the fragment is not in the text', () {
      expect(ExchangeService.contextSnippet('Hola mundo.', 'adiós'), '');
    });
  });

  test('a huge file is refused before it is read', () async {
    final f = File('${tmp.path}/video.json');
    final raf = f.openSync(mode: FileMode.write);
    raf.truncateSync(ExchangeService.maxFileBytes + 1);
    raf.closeSync();
    await expectLater(ExchangeService(phone).importFile(f.path),
        throwsA(isA<FormatException>()));
  });

  test('a phone database from v3 upgrades, keeps a backup, and merges',
      () async {
    final path = '${tmp.path}/v3phone.db';
    final raw = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE translations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_text TEXT NOT NULL, translated_text TEXT NOT NULL,
                source_lang TEXT NOT NULL, target_lang TEXT NOT NULL,
                translator TEXT NOT NULL, context_app TEXT DEFAULT '',
                timestamp DATETIME DEFAULT (datetime('now','localtime')))''');
            await db.execute('''
              CREATE TABLE patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT, phrase TEXT NOT NULL,
                source_lang TEXT NOT NULL, target_lang TEXT NOT NULL,
                count INTEGER DEFAULT 1, first_seen DATETIME, last_seen DATETIME,
                UNIQUE(phrase, source_lang, target_lang))''');
            await db.execute('''
              CREATE TABLE mistakes (
                id INTEGER PRIMARY KEY AUTOINCREMENT, original TEXT NOT NULL,
                corrected TEXT NOT NULL, reason TEXT DEFAULT '',
                category TEXT DEFAULT '', lang TEXT DEFAULT '',
                context TEXT DEFAULT '',
                timestamp DATETIME DEFAULT (datetime('now','localtime')),
                seen_count INTEGER DEFAULT 1, practice_count INTEGER DEFAULT 0,
                last_practiced DATETIME, next_due DATETIME,
                UNIQUE(original, corrected, lang))''');
            await db.execute('''
              CREATE TABLE trainings (id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT (datetime('now','localtime')),
                lang TEXT DEFAULT '', content TEXT NOT NULL)''');
          },
        ));
    await raw.insert('translations', {
      'source_text': 'hola',
      'translated_text': 'привет',
      'source_lang': 'es',
      'target_lang': 'ru',
      'translator': 'google',
      'timestamp': '2026-08-01 10:00:00',
    });
    await raw.close();

    final old = DatabaseService();
    await old.init(path: path);
    try {
      expect(File('$path.v3.bak').existsSync(), isTrue,
          reason: 'the upgrade deletes fragments: keep the original');
      await pc.addMistake(const Mistake(
          original: 'no me atrevo molestar',
          corrected: 'no me atrevo a molestar',
          lang: 'es'));
      final item =
          await pc.findItem('mistake', 'es', 'no me atrevo a molestar');
      final ed = await pc.createEdition('es', 1);
      await pc.saveFeedItem(
        FeedItem(editionId: ed, lang: 'es', headline: 'H', body: 'x' * 60),
        [
          FeedItemTarget(
              feedItemId: 0, itemId: item!.id!, start: 1, end: 5, form: 'xxxx')
        ],
        [
          FeedTask(feedItemId: 0, itemId: item.id, kind: 'cloze', answer: 'a'),
          const FeedTask(feedItemId: 0, kind: 'retell'),
        ],
      );
      await ExchangeService(old).importBundle(await bundleOf(pc));
      final fi = (await old.getFeedItems()).single;
      final cloze = fi.tasks.firstWhere((t) => t.kind == 'cloze');
      await old.saveTaskResult(cloze.id!, 'a', 'ok');
      final back = await ExchangeService(pc).importBundle(await bundleOf(old));
      expect(back.tasksUpdated, 1);
      expect((await pc.getHistory()).map((t) => t.sourceText), contains('hola'));
    } finally {
      await old.close();
    }
  });
}
