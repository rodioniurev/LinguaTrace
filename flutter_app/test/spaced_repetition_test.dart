/// Error memory + spaced repetition: mistakes recorded by the Correct screen
/// must come back for review on schedule, and an existing v2 database must
/// survive the upgrade with its data intact.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<DatabaseService> freshDb() async {
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    return db;
  }

  test('a new mistake is due immediately', () async {
    final db = await freshDb();
    await db.addMistake(const Mistake(
        original: 'yo tengo hambre mucho',
        corrected: 'yo tengo mucha hambre',
        lang: 'es'));

    expect(await db.dueMistakeCount(), 1);
    expect((await db.getDueMistakes()).single.practiceCount, 0);
    await db.close();
  });

  test('repeating the same mistake bumps seen_count, not the row count',
      () async {
    final db = await freshDb();
    const m = Mistake(original: 'el agua', corrected: 'el agua', lang: 'es');
    await db.addMistake(m);
    await db.addMistake(m);
    await db.addMistake(m);

    expect(await db.mistakeCount(), 1);
    expect((await db.getMistakes()).single.seenCount, 3);
    await db.close();
  });

  test('practising schedules the next review and clears the due list',
      () async {
    final db = await freshDb();
    await db.addMistake(
        const Mistake(original: 'a', corrected: 'b', lang: 'es'));

    final due = await db.getDueMistakes();
    await db.markPracticed(due.map((m) => m.id!));

    // First step of the ladder is +1 day, so nothing is due right now.
    expect(await db.dueMistakeCount(), 0);
    final after = (await db.getMistakes()).single;
    expect(after.practiceCount, 1);
    expect(after.nextDue, isNotEmpty);
    await db.close();
  });

  test('the ladder lengthens: 1 → 3 → 7 days', () async {
    final db = await freshDb();
    await db.addMistake(
        const Mistake(original: 'a', corrected: 'b', lang: 'es'));
    final id = (await db.getMistakes()).single.id!;

    final dues = <String>[];
    for (var i = 0; i < 3; i++) {
      await db.markPracticed([id]);
      dues.add((await db.getMistakes()).single.nextDue);
    }

    // Each review must land strictly further out than the previous one.
    expect(dues[0].compareTo(dues[1]) < 0, isTrue, reason: '1d < 3d');
    expect(dues[1].compareTo(dues[2]) < 0, isTrue, reason: '3d < 7d');
    expect((await db.getMistakes()).single.practiceCount, 3);
    await db.close();
  });

  test('markPracticed on an empty list is a no-op', () async {
    final db = await freshDb();
    await db.markPracticed(const <int>[]);
    expect(await db.mistakeCount(), 0);
    await db.close();
  });

  test('a v2 database upgrades to v3 keeping its mistakes', () async {
    final dir = Directory.systemTemp.createTempSync('lt_dbtest');
    final path = '${dir.path}/translations.db';

    // Build a v2 database by hand — the schema as it shipped before the
    // spaced-repetition columns existed.
    final legacy = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE mistakes (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                original   TEXT    NOT NULL,
                corrected  TEXT    NOT NULL,
                reason     TEXT    DEFAULT '',
                category   TEXT    DEFAULT '',
                lang       TEXT    DEFAULT '',
                context    TEXT    DEFAULT '',
                timestamp  DATETIME DEFAULT (datetime('now','localtime')),
                seen_count INTEGER DEFAULT 1,
                UNIQUE(original, corrected, lang)
              )
            ''');
            await db.execute('''
              CREATE TABLE trainings (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT (datetime('now','localtime')),
                lang      TEXT DEFAULT '',
                content   TEXT NOT NULL
              )
            ''');
          },
        ));
    await legacy.insert('mistakes', {
      'original': 'vieja mistake',
      'corrected': 'old mistake',
      'lang': 'es',
      'seen_count': 4,
    });
    await legacy.close();

    final db = DatabaseService();
    await db.init(path: path); // triggers _onUpgrade 2 → 4

    final rows = await db.getMistakes();
    expect(rows.length, 1, reason: 'existing data must survive the upgrade');
    expect(rows.single.seenCount, 4);
    expect(rows.single.practiceCount, 0, reason: 'new column defaults to 0');
    expect(await db.dueMistakeCount(), 1,
        reason: 'a never-practised mistake is due');

    await db.close();
    dir.deleteSync(recursive: true);
  });
}
