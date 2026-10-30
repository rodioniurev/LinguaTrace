/// DB v4: clean capture, legacy import, learner model. Fixtures mirror the
/// user's real data shape (keystroke snapshots, a v2 database next to the
/// exe, mistakes with no construction tag).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:lingua_trace/models/translation_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lt_v4'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A v3 database as the Aug-2026 builds wrote it, with 300 ms snapshots.
  Future<String> buildV3(String name) async {
    final path = '${tmp.path}/$name';
    final db = await databaseFactory.openDatabase(path,
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
                context TEXT DEFAULT '', timestamp DATETIME DEFAULT (datetime('now','localtime')),
                seen_count INTEGER DEFAULT 1, practice_count INTEGER DEFAULT 0,
                last_practiced DATETIME, next_due DATETIME,
                UNIQUE(original, corrected, lang))''');
            await db.execute('''
              CREATE TABLE trainings (id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT (datetime('now','localtime')),
                lang TEXT DEFAULT '', content TEXT NOT NULL)''');
          },
        ));
    Future<void> tr(String text, String ts) => db.insert('translations', {
          'source_text': text,
          'translated_text': 'x',
          'source_lang': 'ru',
          'target_lang': 'es',
          'translator': 'google',
          'context_app': 'mobile',
          'timestamp': ts,
        });
    // Keystroke snapshots of one greeting…
    await tr('добры', '2026-08-24 13:19:02');
    await tr('добрый', '2026-08-24 13:19:03');
    await tr('добрый ден', '2026-08-24 13:19:04');
    await tr('добрый день,', '2026-08-24 13:19:05');
    // …typo fixes in the middle of a phrase (not a prefix)…
    await tr('расходы на ремонт кваритры', '2026-09-26 12:00:00');
    await tr('расходы на ремонт квартиры', '2026-09-26 12:00:04');
    // …and a real repeated short lookup on other days.
    await tr('соседство', '2026-09-20 10:00:00');
    await tr('соседство', '2026-09-26 10:00:00');
    await db.insert('mistakes', {
      'original': 'no me atrevo molestar',
      'corrected': 'no me atrevo a molestar',
      'reason': 'régimen',
      'lang': 'es',
    });
    await db.close();
    return path;
  }

  test('v3 → v4: snapshots marked, patterns rebuilt, mistake becomes an item',
      () async {
    final path = await buildV3('v3.db');
    final db = DatabaseService();
    await db.init(path: path);

    final history = await db.getHistory();
    expect(history.map((e) => e.sourceText),
        ['расходы на ремонт квартиры', 'соседство', 'соседство', 'добрый день,'],
        reason: 'only the final text of each edit survives in history');

    final patterns = await db.getTopPatterns(minCount: 2);
    expect(patterns.single.phrase, 'соседство');
    expect(patterns.single.count, 2);

    final items = await db.getItems();
    expect(items.single.kind, 'mistake');
    expect(items.single.text, 'no me atrevo a molestar');
    expect(items.single.wrongForm, 'no me atrevo molestar');
    await db.close();
  });

  test('legacy import merges once, idempotently, into a fresh database',
      () async {
    final legacy = await buildV3('legacy.db');
    final db = DatabaseService();
    await db.init(path: '${tmp.path}/new.db');

    final added = await db.importLegacyDatabase(legacy);
    expect(added, 9, reason: '8 translations + 1 mistake');
    expect(await db.importLegacyDatabase(legacy), 0,
        reason: 'same file (size+mtime) is not re-read');
    expect((await db.getHistory()).length, 4);
    expect(await db.mistakeCount(), 1);
    await db.close();
  });

  test('settled commits: long letters never become "patterns"', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    await db.addTranslation(const TranslationEntry(
        sourceText: 'добрый день, уважаемые господа, сегодня мы получили '
            'резолюции по внж и хотим уточнить детали',
        translatedText: 'x',
        sourceLang: 'ru',
        targetLang: 'es',
        translator: 'google'));
    await db.addTranslation(const TranslationEntry(
        sourceText: 'Соседство', // capital Cyrillic must still match
        translatedText: 'vecindad',
        sourceLang: 'ru',
        targetLang: 'es',
        translator: 'google'));
    await db.countCachedLookup('соседство', 'ru', 'es');

    final patterns = await db.getTopPatterns(minCount: 1);
    expect(patterns.map((p) => p.phrase), ['соседство']);
    expect(patterns.single.count, 2, reason: 'cache hits count too');

    final hit = await db.cacheLookup(
        sourceText: 'СОСЕДСТВО', sourceLang: 'ru', targetLang: 'es');
    expect(hit?.translatedText, 'vecindad',
        reason: 'normalized key fixes the ASCII-only LOWER() miss');
    await db.close();
  });

  test('replaceTranslation edits the row instead of adding a fragment',
      () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    final id = await db.addTranslation(const TranslationEntry(
        sourceText: 'casa',
        translatedText: 'дом',
        sourceLang: 'es',
        targetLang: 'ru',
        translator: 'google'));
    await db.replaceTranslation(
        id,
        const TranslationEntry(
            sourceText: 'casa grande',
            translatedText: 'большой дом',
            sourceLang: 'es',
            targetLang: 'ru',
            translator: 'google'));
    final h = await db.getHistory();
    expect(h.single.sourceText, 'casa grande');
    final p = await db.getTopPatterns(minCount: 1);
    expect(p.map((e) => e.phrase), ['casa grande']);
    await db.close();
  });

  test('learning items: events move counters; saved → learning; reject',
      () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    final id = await db.upsertItem(
        kind: 'proverb', lang: 'es', text: 'A quien madruga, Dios le ayuda');
    await db.addEvent(id, 'exposure');
    await db.addEvent(id, 'saved');
    final again = await db.upsertItem(
        kind: 'proverb', lang: 'es', text: 'a quien madruga,  dios le ayuda');
    expect(again, id, reason: 'normalized text dedupes');
    final item = (await db.getItems()).single;
    expect(item.status, 'learning');
    expect(item.exposures, 1);

    final mid = await db.addMistake(const Mistake(
      original: 'en autobús',
      corrected: 'en autobús',
      lang: 'es',
      construction: 'es.prep.place',
      backend: 'Claude Opus 5 · подписка',
    ));
    expect((await db.topConstructions()).single, ('es.prep.place', 1));
    await db.rejectMistake(mid);
    expect(await db.topConstructions(), isEmpty,
        reason: 'a rejected fix no longer counts as my mistake');
    expect(await db.mistakeCount(), 0);
    await db.close();
  });

  test('upgrades (style suggestions) are not learning items', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    await db.addMistake(const Mistake(
        original: 'hablar mucho',
        corrected: 'irse de la lengua',
        lang: 'es',
        severity: 'upgrade'));
    expect(await db.getItems(), isEmpty);
    expect(await db.dueMistakeCount(), 0);
    await db.close();
  });

  test('markShown does not move the review ladder', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    final id = await db
        .addMistake(const Mistake(original: 'a', corrected: 'b', lang: 'es'));
    await db.markShown([id]);
    expect(await db.dueMistakeCount(), 1);
    expect((await db.getMistakes()).single.practiceCount, 0);
    await db.close();
  });

  test('AI usage is summed for the month', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    await db.logAiUsage(
        feature: 'correction', provider: 'claude', costUsd: 0.01);
    await db.logAiUsage(
        feature: 'correction', provider: 'claude', ok: false, error: 'x');
    final (n, ok, cost) = await db.aiUsageThisMonth();
    expect((n, ok), (2, 1));
    expect(cost, closeTo(0.01, 1e-9));
    await db.close();
  });

  test('«это не ошибка» sticks even when the model repeats the same fix',
      () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    const m = Mistake(
        original: 'y enseguida', corrected: 'y en seguida', lang: 'es');
    final id = await db.addMistake(m);
    await db.rejectMistake(id);
    final again = await db.addMistake(m);
    expect(again, id);
    expect(await db.mistakeCount(), 0);
    expect(await db.dueMistakeCount(), 0);
    expect(await db.getItems(), isEmpty);
    await db.close();
  });

  test('rejecting one fix keeps the item of another real mistake', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    final bad = await db.addMistake(const Mistake(
        original: 'fue a mi caza', corrected: 'fui a mi casa', lang: 'es'));
    await db.addMistake(const Mistake(
        original: 'fui a mi caza', corrected: 'fui a mi casa', lang: 'es'));
    await db.rejectMistake(bad);
    expect((await db.getItems()).single.text, 'fui a mi casa');
    await db.close();
  });

  test('replacing a row deleted in History inserts a new one', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    const e = TranslationEntry(
        sourceText: 'casa', translatedText: 'дом', sourceLang: 'es',
        targetLang: 'ru', translator: 'google');
    final id = await db.addTranslation(e);
    await db.deleteTranslation(id);
    final newId = await db.replaceTranslation(
        id,
        const TranslationEntry(
            sourceText: 'casa grande', translatedText: 'большой дом',
            sourceLang: 'es', targetLang: 'ru', translator: 'google'));
    expect(newId, isNot(id));
    expect((await db.getHistory()).single.sourceText, 'casa grande');
    await db.close();
  });

  test("snapshot heuristics on the user's real typing sequences", () {
    bool snap(String a, String b, int gap) =>
        DatabaseService.isSnapshotOf(a, b, gap);
    expect(snap('добры', 'добрый', 1), isTrue, reason: 'grew');
    expect(snap('расходы на ремонт кваритры', 'расходы на ремонт квартиры', 4),
        isTrue, reason: 'typo fixed in place');
    expect(snap('jcnfn', 'ос', 2), isTrue, reason: 'wrong keyboard layout');
    expect(snap('хотим н', 'хотим автомат', 1), isTrue);
    expect(snap('доброе соседство межлу', 'доброе соседство между жител', 2),
        isTrue);
    expect(snap('política dispar', 'política', 2), isFalse,
        reason: 'looking up a part of a finished text is a real lookup');
    expect(snap('casa', 'cosa', 30), isFalse);
    expect(snap('soy cansado', 'estoy cansado', 40), isTrue,
        reason: 'the user revised the same sentence');
    expect(snap('una casa bonita', 'un perro grande', 3), isFalse);
  });

  test('marking a training done advances its mistakes once', () async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    final mid = await db
        .addMistake(const Mistake(original: 'a', corrected: 'b', lang: 'es'));
    final tid = await db.addTraining('es', 'session', mistakeIds: [mid]);
    await db.markTrainingDone(tid);
    await db.markTrainingDone(tid); // second tap is a no-op
    expect((await db.getMistakes()).single.practiceCount, 1);
    expect(await db.dueMistakeCount(), 0);
    expect((await db.getTrainings()).single.isDone, isTrue);
    await db.close();
  });
}
