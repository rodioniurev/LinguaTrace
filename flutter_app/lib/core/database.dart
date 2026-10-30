/// SQLite service — same core schema as the desktop Python app, plus the
/// learner model (v4): learning items, an append-only event log, AI usage.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../models/feed.dart';
import '../models/idea.dart';
import '../models/learning_item.dart';
import '../models/news_article.dart';
import '../models/translation_entry.dart';
import '../models/pattern_entry.dart';
import '../models/mistake.dart';
import 'mistake_forms.dart';

class DatabaseService {
  static const _version = 8;

  /// A lookup counts toward "words I keep looking up" only if it is this
  /// short — paragraph-long letters are not learnable patterns.
  static const maxPatternTokens = 6;

  Database? _db;

  /// Raw handle for services that need whole-table access (exchange files).
  Database get sqlite => _db!;

  /// Stable id of this device for provenance ('windows:<host>' / 'android').
  static String get deviceId {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      return '${Platform.operatingSystem}:${Platform.localHostname}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// [path] is required: AppPaths decides where the file lives (tests pass
  /// a temp file or [inMemoryDatabasePath]).
  Future<void> init({required String path}) async {
    await _backupBeforeUpgrade(path);
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    try {
      await _postOpenMaintenance();
    } catch (_) {
      // The clean-up is not needed to run the app; its flag stays unset,
      // so it is retried on the next launch instead of blocking this one.
    }
  }

  /// Before a newer schema first opens the file, keep a copy: the upgrade
  /// deletes keystroke fragments, and on a phone there is no untouched
  /// legacy file to go back to. The schema version is read straight from
  /// the SQLite header (user_version, bytes 60–63).
  static Future<void> _backupBeforeUpgrade(String path) async {
    if (path == inMemoryDatabasePath) return;
    try {
      final f = File(path);
      if (!await f.exists()) return;
      final raf = await f.open();
      final head = await raf.read(64);
      await raf.close();
      if (head.length < 64) return;
      final v = (head[60] << 24) | (head[61] << 16) | (head[62] << 8) | head[63];
      if (v <= 0 || v >= _version) return;
      final bak = File('$path.v$v.bak');
      if (!await bak.exists()) await f.copy(bak.path);
    } catch (_) {
      // A backup must never stop the app from starting.
    }
  }

  // ─────────────────────────────────────────── schema

  Future<void> _onCreate(Database db, int version) async {
    await _createBaseTables(db);
    await _createLearningTables(db);
    await _upgradeToV4(db);
    await _upgradeToV5(db);
    await _upgradeToV6(db);
    await _upgradeToV7(db);
    await _upgradeToV8(db);
  }

  /// v1 tables. IF NOT EXISTS, so upgrades can call it to repair a database
  /// that somehow lacks them before ALTERing.
  Future<void> _createBaseTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS translations (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        source_text     TEXT    NOT NULL,
        translated_text TEXT    NOT NULL,
        source_lang     TEXT    NOT NULL,
        target_lang     TEXT    NOT NULL,
        translator      TEXT    NOT NULL,
        context_app     TEXT    DEFAULT '',
        timestamp       DATETIME DEFAULT (datetime('now','localtime'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS patterns (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        phrase      TEXT    NOT NULL,
        source_lang TEXT    NOT NULL,
        target_lang TEXT    NOT NULL,
        count       INTEGER DEFAULT 1,
        first_seen  DATETIME DEFAULT (datetime('now','localtime')),
        last_seen   DATETIME DEFAULT (datetime('now','localtime')),
        UNIQUE(phrase, source_lang, target_lang)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ts ON translations(timestamp)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pat ON patterns(count DESC)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Creates the tables already carrying the v3 columns — no ALTER needed.
      await _createLearningTables(db);
    } else if (oldVersion < 3) {
      await _addSpacedRepetitionColumns(db);
    }
    // Independent of the chain above: every path ends at v4. The helpers
    // check column existence, so no path can hit a duplicate-column error.
    if (oldVersion < 4) await _upgradeToV4(db);
    if (oldVersion < 5) await _upgradeToV5(db);
    if (oldVersion < 6) await _upgradeToV6(db);
    if (oldVersion < 7) await _upgradeToV7(db);
    if (oldVersion < 8) await _upgradeToV8(db);
  }

  /// v8: «Идеи» — projects for articles and inventions: the author's
  /// context, attached sources, dictated notes and what the background
  /// research found. Every row has a uuid: dictated on the phone, enriched
  /// on the PC, merged both ways through the exchange file.
  Future<void> _upgradeToV8(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS idea_projects (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid       TEXT NOT NULL UNIQUE,
        title      TEXT NOT NULL,
        context    TEXT DEFAULT '',
        kind       TEXT DEFAULT 'article',
        created_at DATETIME DEFAULT (datetime('now','localtime')),
        updated_at DATETIME DEFAULT (datetime('now','localtime'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS idea_notes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid       TEXT NOT NULL UNIQUE,
        project_id INTEGER NOT NULL,
        text       TEXT NOT NULL,
        clean_text TEXT DEFAULT '',
        source     TEXT DEFAULT 'voice',
        lang       TEXT DEFAULT 'ru',
        status     TEXT DEFAULT '',
        error      TEXT DEFAULT '',
        created_at DATETIME DEFAULT (datetime('now','localtime')),
        updated_at DATETIME DEFAULT (datetime('now','localtime'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS idea_sources (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid       TEXT NOT NULL UNIQUE,
        project_id INTEGER NOT NULL,
        kind       TEXT DEFAULT 'text',
        title      TEXT DEFAULT '',
        url        TEXT DEFAULT '',
        content    TEXT DEFAULT '',
        summary    TEXT DEFAULT '',
        created_at DATETIME DEFAULT (datetime('now','localtime'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS idea_insights (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid       TEXT NOT NULL UNIQUE,
        project_id INTEGER NOT NULL,
        note_id    INTEGER,
        text       TEXT NOT NULL,
        links      TEXT DEFAULT '',
        backend    TEXT DEFAULT '',
        web        INTEGER DEFAULT 0,
        kind       TEXT DEFAULT 'enrichment',
        created_at DATETIME DEFAULT (datetime('now','localtime'))
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_idea_notes_project '
        'ON idea_notes(project_id, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_idea_sources_project '
        'ON idea_sources(project_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_idea_insights_note '
        'ON idea_insights(note_id)');
  }

  /// v7: «Происхождение и история» pages (Claude, grounded in Wiktionary),
  /// kept so a page is written once — on the PC — and read everywhere.
  Future<void> _upgradeToV7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS etymology_pages (
        lang       TEXT NOT NULL,
        norm_key   TEXT NOT NULL,
        term       TEXT NOT NULL,
        json       TEXT NOT NULL,
        backend    TEXT DEFAULT '',
        created_at DATETIME DEFAULT (datetime('now','localtime')),
        PRIMARY KEY (lang, norm_key)
      )
    ''');
  }

  /// v6: exchange safety. A user's decision about an item (status_at) and
  /// its review schedule (srs_at) get their own clocks (millisecond local
  /// time, so a decision taken right after an item was created is still
  /// "later"), so a later lookup or exposure on another device cannot undo
  /// either; tombstones keep
  /// deleted history from coming back with the other device's file; indexes
  /// for merging by uuid.
  Future<void> _upgradeToV6(Database db) async {
    await _addColumn(db, 'learning_items', 'status_at', 'DATETIME');
    await _addColumn(db, 'learning_items', 'srs_at', 'DATETIME');
    // Existing decisions and schedules get the best time known for them.
    await db.execute('UPDATE learning_items SET status_at = last_seen '
        "WHERE status_at IS NULL AND status <> 'seen'");
    await db.execute('UPDATE learning_items SET srs_at = last_seen '
        'WHERE srs_at IS NULL AND (stage > 0 OR next_due IS NOT NULL)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tombstones (
        tbl        TEXT NOT NULL,
        key        TEXT NOT NULL,
        deleted_at DATETIME DEFAULT (datetime('now','localtime')),
        PRIMARY KEY (tbl, key)
      )
    ''');
    for (final (name, on) in const [
      ('idx_feed_ed_uuid', 'feed_editions(uuid)'),
      ('idx_feed_items_uuid', 'feed_items(uuid)'),
      ('idx_feed_tasks_uuid', 'feed_tasks(uuid)'),
      ('idx_feed_tasks_item', 'feed_tasks(feed_item_id)'),
      ('idx_ev_item_type', 'item_events(item_id, type)'),
    ]) {
      await db.execute('CREATE INDEX IF NOT EXISTS $name ON $on');
    }
  }

  // ─────────────────────────────────────────── tombstones

  /// Stable key of a row by its natural key (the same on every device).
  static String rowKey(List<Object?> natural) =>
      sha1.convert(utf8.encode(jsonEncode(natural))).toString();

  static List<Object?> translationKey(Map<String, Object?> r) =>
      [r['source_text'], r['timestamp'], r['target_lang']];

  static List<Object?> trainingKey(Map<String, Object?> r) =>
      [r['timestamp'], r['content']];

  static List<Object?> mistakeKey(Map<String, Object?> r) =>
      [r['original'], r['corrected'], r['lang']];

  /// Remember that rows of [table] were deleted here, so an exchange file
  /// from another device does not bring them back.
  Future<void> _bury(DatabaseExecutor db, String table,
      Iterable<List<Object?>> keys) async {
    final batch = db.batch();
    for (final k in keys) {
      batch.insert('tombstones', {'tbl': table, 'key': rowKey(k)},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _buryTranslations(List<int> ids) async {
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      final rows = await _db!.query('translations',
          columns: ['source_text', 'timestamp', 'target_lang'],
          where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: chunk);
      await _bury(_db!, 'translations', rows.map(translationKey));
    }
  }

  /// v5: the news-feed trainer. Articles keep only headline + lead; feed
  /// items are the user's personal corpus and are kept.
  Future<void> _upgradeToV5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS news_articles (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        url_hash     TEXT NOT NULL UNIQUE,
        url          TEXT NOT NULL,
        source_id    TEXT NOT NULL,
        outlet       TEXT DEFAULT '',
        lang         TEXT NOT NULL,
        variety      TEXT DEFAULT '',
        title        TEXT NOT NULL,
        lead         TEXT NOT NULL,
        categories   TEXT DEFAULT '',
        published_at TEXT,
        fetched_at   DATETIME DEFAULT (datetime('now','localtime')),
        used_count   INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_news_pub '
        'ON news_articles(lang, published_at)');
    // Stable ids so an edition written on the PC and answered on the phone
    // can be merged back (exchange files).
    await db.execute('CREATE TABLE IF NOT EXISTS exchange_imports ('
        'device TEXT NOT NULL, hash TEXT NOT NULL, '
        "imported_at DATETIME DEFAULT (datetime('now','localtime')), "
        'PRIMARY KEY(device, hash))');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feed_editions (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid       TEXT,
        lang       TEXT NOT NULL,
        created_at DATETIME DEFAULT (datetime('now','localtime')),
        status     TEXT DEFAULT 'building',
        planned    INTEGER DEFAULT 0,
        error      TEXT DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feed_items (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid         TEXT,
        edition_id   INTEGER NOT NULL,
        lang         TEXT NOT NULL,
        headline     TEXT NOT NULL,
        body         TEXT NOT NULL,
        attribution  TEXT DEFAULT '',
        outlet       TEXT DEFAULT '',
        source_url   TEXT DEFAULT '',
        published_at TEXT DEFAULT '',
        sources_json TEXT DEFAULT '',
        backend      TEXT DEFAULT '',
        created_at   DATETIME DEFAULT (datetime('now','localtime')),
        read_at      DATETIME,
        flagged      TEXT DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feed_item_targets (
        feed_item_id INTEGER NOT NULL,
        item_id      INTEGER NOT NULL,
        start_pos    INTEGER NOT NULL,
        end_pos      INTEGER NOT NULL,
        form_used    TEXT NOT NULL,
        highlight    INTEGER DEFAULT 1,
        PRIMARY KEY (feed_item_id, item_id, start_pos)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feed_tasks (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid         TEXT,
        feed_item_id INTEGER NOT NULL,
        item_id      INTEGER,
        kind         TEXT NOT NULL,
        prompt_ru    TEXT DEFAULT '',
        text         TEXT DEFAULT '',
        options      TEXT DEFAULT '',
        answer       TEXT DEFAULT '',
        user_answer  TEXT DEFAULT '',
        result       TEXT DEFAULT '',
        done_at      DATETIME
      )
    ''');
  }

  /// v3: spaced repetition columns on mistakes.
  Future<void> _addSpacedRepetitionColumns(Database db) async {
    await _addColumn(db, 'mistakes', 'practice_count', 'INTEGER DEFAULT 0');
    await _addColumn(db, 'mistakes', 'last_practiced', 'DATETIME');
    await _addColumn(db, 'mistakes', 'next_due', 'DATETIME');
  }

  /// v2: error memory + generated practice sessions.
  Future<void> _createLearningTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mistakes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        original   TEXT    NOT NULL,
        corrected  TEXT    NOT NULL,
        reason     TEXT    DEFAULT '',
        category   TEXT    DEFAULT '',
        lang       TEXT    DEFAULT '',
        context    TEXT    DEFAULT '',
        timestamp  DATETIME DEFAULT (datetime('now','localtime')),
        seen_count INTEGER DEFAULT 1,
        practice_count INTEGER DEFAULT 0,
        last_practiced DATETIME,
        next_due       DATETIME,
        UNIQUE(original, corrected, lang)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_mist ON mistakes(seen_count DESC)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trainings (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT (datetime('now','localtime')),
        lang      TEXT DEFAULT '',
        content   TEXT NOT NULL
      )
    ''');
  }

  /// v4: clean capture (settled flag, provenance, normalized key), mistake
  /// provenance, and the learner model.
  Future<void> _upgradeToV4(Database db) async {
    await _createBaseTables(db);
    await _createLearningTables(db);
    await _addSpacedRepetitionColumns(db);
    await _addColumn(db, 'translations', 'settled', 'INTEGER DEFAULT 1');
    await _addColumn(db, 'translations', 'device', "TEXT DEFAULT ''");
    await _addColumn(db, 'translations', 'norm_key', "TEXT DEFAULT ''");
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tr_norm '
        'ON translations(norm_key, source_lang, target_lang)');

    await _addColumn(db, 'mistakes', 'construction', "TEXT DEFAULT ''");
    await _addColumn(db, 'mistakes', 'severity', "TEXT DEFAULT 'error'");
    await _addColumn(db, 'mistakes', 'backend', "TEXT DEFAULT ''");
    await _addColumn(db, 'mistakes', 'source', "TEXT DEFAULT 'correct'");
    await _addColumn(db, 'mistakes', 'rejected', 'INTEGER DEFAULT 0');
    // Which mistakes a session covered, and when the user said they did it —
    // the review ladder advances on "done", not on generation.
    await _addColumn(db, 'trainings', 'mistake_ids', "TEXT DEFAULT ''");
    await _addColumn(db, 'trainings', 'done_at', 'DATETIME');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_items (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid         TEXT NOT NULL UNIQUE,
        kind         TEXT NOT NULL,
        lang         TEXT NOT NULL,
        text         TEXT NOT NULL,
        norm_key     TEXT NOT NULL,
        gloss        TEXT DEFAULT '',
        wrong_form   TEXT DEFAULT '',
        construction TEXT DEFAULT '',
        concept_key  TEXT DEFAULT '',
        source       TEXT DEFAULT '',
        status       TEXT DEFAULT 'seen',
        notes        TEXT DEFAULT '',
        stage        INTEGER DEFAULT 0,
        next_due     DATETIME,
        lookups      INTEGER DEFAULT 0,
        exposures    INTEGER DEFAULT 0,
        recall_ok    INTEGER DEFAULT 0,
        recall_fail  INTEGER DEFAULT 0,
        produced_ok  INTEGER DEFAULT 0,
        produced_err INTEGER DEFAULT 0,
        first_seen   DATETIME DEFAULT (datetime('now','localtime')),
        last_seen    DATETIME DEFAULT (datetime('now','localtime')),
        UNIQUE(kind, lang, norm_key)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_status '
        'ON learning_items(status, kind)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_constr '
        'ON learning_items(construction)');

    // Append-only: merges trivially across devices (uuid), and SRS state
    // can always be recomputed from it.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS item_events (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid           TEXT NOT NULL UNIQUE,
        item_id        INTEGER,
        type           TEXT NOT NULL,
        surface        TEXT DEFAULT '',
        context        TEXT DEFAULT '',
        translation_id INTEGER,
        device         TEXT DEFAULT '',
        ts             DATETIME DEFAULT (datetime('now','localtime')),
        payload        TEXT DEFAULT ''
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ev_item '
        'ON item_events(item_id, ts)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ev_type ON item_events(type, ts)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_usage (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ts            DATETIME DEFAULT (datetime('now','localtime')),
        feature       TEXT DEFAULT '',
        provider      TEXT DEFAULT '',
        model         TEXT DEFAULT '',
        input_tokens  INTEGER DEFAULT 0,
        output_tokens INTEGER DEFAULT 0,
        cost_usd      REAL DEFAULT 0,
        duration_ms   INTEGER DEFAULT 0,
        ok            INTEGER DEFAULT 1,
        error         TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS imported_sources (
        path        TEXT NOT NULL,
        size        INTEGER NOT NULL,
        mtime       TEXT NOT NULL,
        rows        INTEGER DEFAULT 0,
        imported_at DATETIME DEFAULT (datetime('now','localtime')),
        PRIMARY KEY(path, size, mtime)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<void> _addColumn(
      DatabaseExecutor db, String table, String column, String decl) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $decl');
  }

  /// One-time and idempotent clean-ups that need Dart logic.
  Future<void> _postOpenMaintenance() async {
    final done = await _meta('v4_cleanup');
    if (done == '1') return;
    await backfillNormKeys();
    await markSnapshotRows();
    await rebuildPatterns();
    await _itemsFromImportedMistakes();
    await _setMeta('v4_cleanup', '1');
  }

  // ─────────────────────────────────────────── ideas

  static const _ideaTables = {
    'idea_projects', 'idea_notes', 'idea_sources', 'idea_insights',
  };

  Future<List<IdeaProject>> ideaProjects() async {
    final rows = await _db!.rawQuery('''
      SELECT p.*,
        (SELECT COUNT(*) FROM idea_notes n WHERE n.project_id = p.id) AS note_count,
        (SELECT COUNT(*) FROM idea_sources s WHERE s.project_id = p.id AND s.kind <> 'found') AS source_count
      FROM idea_projects p ORDER BY p.updated_at DESC, p.id DESC
    ''');
    return rows.map(IdeaProject.fromMap).toList();
  }

  Future<IdeaProject?> ideaProject(int id) async {
    final rows = await _db!.query('idea_projects',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : IdeaProject.fromMap(rows.first);
  }

  Future<int> addIdeaProject(String title,
          {String context = '', String kind = 'article'}) =>
      _db!.insert('idea_projects', {
        'uuid': newUuid(),
        'title': title.trim(),
        'context': context.trim(),
        'kind': kind,
        'created_at': _nowLocal(),
        'updated_at': _nowLocal(),
      });

  Future<void> updateIdeaProject(int id,
      {String? title, String? context, String? kind}) async {
    await _db!.update(
        'idea_projects',
        {
          if (title != null) 'title': title.trim(),
          if (context != null) 'context': context.trim(),
          if (kind != null) 'kind': kind,
          'updated_at': _nowLocal(),
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> _touchProject(int projectId) => _db!.rawUpdate(
      'UPDATE idea_projects SET updated_at = ? WHERE id = ?',
      [_nowLocal(), projectId]);

  /// A project and everything in it; tombstones keep it deleted on the
  /// other device too.
  Future<void> deleteIdeaProject(int id) async {
    final keys = <String, List<List<Object?>>>{};
    for (final t in _ideaTables) {
      final rows = await _db!.query(t,
          columns: ['uuid'],
          where: t == 'idea_projects' ? 'id = ?' : 'project_id = ?',
          whereArgs: [id]);
      keys[t] = [for (final r in rows) [r['uuid']]];
    }
    for (final e in keys.entries) {
      await _bury(_db!, e.key, e.value);
    }
    await _db!.delete('idea_insights', where: 'project_id = ?', whereArgs: [id]);
    await _db!.delete('idea_sources', where: 'project_id = ?', whereArgs: [id]);
    await _db!.delete('idea_notes', where: 'project_id = ?', whereArgs: [id]);
    await _db!.delete('idea_projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<IdeaNote>> ideaNotes(int projectId, {int limit = 500}) async =>
      (await _db!.query('idea_notes',
              where: 'project_id = ?',
              whereArgs: [projectId],
              orderBy: 'created_at DESC, id DESC',
              limit: limit))
          .map(IdeaNote.fromMap)
          .toList();

  Future<IdeaNote?> ideaNote(int id) async {
    final rows = await _db!.query('idea_notes',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : IdeaNote.fromMap(rows.first);
  }

  Future<int> addIdeaNote(int projectId, String text,
      {String source = 'voice', String lang = 'ru', String status = ''}) async {
    final id = await _db!.insert('idea_notes', {
      'uuid': newUuid(),
      'project_id': projectId,
      'text': text,
      'source': source,
      'lang': lang,
      'status': status,
      'created_at': _nowLocal(),
      'updated_at': _nowLocal(),
    });
    await _touchProject(projectId);
    return id;
  }

  /// Dictation is saved while it is spoken: the same row grows.
  Future<void> updateIdeaNoteText(int id, String text) => _db!.update(
      'idea_notes', {'text': text, 'updated_at': _nowLocal()},
      where: 'id = ?', whereArgs: [id]);

  Future<void> setIdeaNoteStatus(int id, String status,
          {String? cleanText, String error = ''}) =>
      _db!.update(
          'idea_notes',
          {
            'status': status,
            'error': error,
            if (cleanText != null) 'clean_text': cleanText,
            'updated_at': _nowLocal(),
          },
          where: 'id = ?',
          whereArgs: [id]);

  Future<void> deleteIdeaNote(int id) async {
    final rows = await _db!.query('idea_notes',
        columns: ['uuid'], where: 'id = ?', whereArgs: [id]);
    final ins = await _db!.query('idea_insights',
        columns: ['uuid'], where: 'note_id = ?', whereArgs: [id]);
    await _bury(_db!, 'idea_notes', [for (final r in rows) [r['uuid']]]);
    await _bury(_db!, 'idea_insights', [for (final r in ins) [r['uuid']]]);
    await _db!.delete('idea_insights', where: 'note_id = ?', whereArgs: [id]);
    await _db!.delete('idea_notes', where: 'id = ?', whereArgs: [id]);
  }

  /// Notes waiting for the background research, oldest first.
  Future<List<IdeaNote>> pendingIdeaNotes({int limit = 20}) async =>
      (await _db!.query('idea_notes',
              where: "status IN ('queued', 'offline') AND trim(text) <> ''",
              orderBy: 'created_at ASC, id ASC',
              limit: limit))
          .map(IdeaNote.fromMap)
          .toList();

  Future<List<IdeaSource>> ideaSources(int projectId,
          {bool includeFound = true}) async =>
      (await _db!.query('idea_sources',
              where: includeFound
                  ? 'project_id = ?'
                  : "project_id = ? AND kind <> 'found'",
              whereArgs: [projectId],
              orderBy: 'created_at DESC, id DESC'))
          .map(IdeaSource.fromMap)
          .toList();

  Future<int> addIdeaSource(int projectId,
      {required String kind,
      String title = '',
      String url = '',
      String content = '',
      String summary = ''}) async {
    // One row per link in a project: research finds the same page again.
    if (url.isNotEmpty) {
      final dup = await _db!.query('idea_sources',
          columns: ['id'],
          where: 'project_id = ? AND url = ?',
          whereArgs: [projectId, url],
          limit: 1);
      if (dup.isNotEmpty) return dup.first['id'] as int;
    }
    final id = await _db!.insert('idea_sources', {
      'uuid': newUuid(),
      'project_id': projectId,
      'kind': kind,
      'title': title.trim(),
      'url': url.trim(),
      'content': content,
      'summary': summary,
      'created_at': _nowLocal(),
    });
    await _touchProject(projectId);
    return id;
  }

  Future<void> setIdeaSourceSummary(int id, String summary,
          {String? title}) =>
      _db!.update(
          'idea_sources',
          {'summary': summary, if (title != null && title.isNotEmpty) 'title': title},
          where: 'id = ?',
          whereArgs: [id]);

  Future<void> deleteIdeaSource(int id) async {
    final rows = await _db!.query('idea_sources',
        columns: ['uuid'], where: 'id = ?', whereArgs: [id]);
    await _bury(_db!, 'idea_sources', [for (final r in rows) [r['uuid']]]);
    await _db!.delete('idea_sources', where: 'id = ?', whereArgs: [id]);
  }

  /// Attached sources still without a summary (made in the background).
  Future<List<IdeaSource>> unsummarizedSources({int limit = 10}) async =>
      (await _db!.query('idea_sources',
              where: "kind <> 'found' AND summary = '' AND content <> ''",
              orderBy: 'id ASC',
              limit: limit))
          .map(IdeaSource.fromMap)
          .toList();

  Future<List<IdeaInsight>> ideaInsights(int projectId) async =>
      (await _db!.query('idea_insights',
              where: 'project_id = ?',
              whereArgs: [projectId],
              orderBy: 'created_at DESC, id DESC'))
          .map(IdeaInsight.fromMap)
          .toList();

  Future<int> addIdeaInsight(int projectId,
      {int? noteId,
      required String text,
      String links = '',
      String backend = '',
      bool web = false,
      String kind = 'enrichment'}) async {
    final id = await _db!.insert('idea_insights', {
      'uuid': newUuid(),
      'project_id': projectId,
      'note_id': noteId,
      'text': text,
      'links': links,
      'backend': backend,
      'web': web ? 1 : 0,
      'kind': kind,
      'created_at': _nowLocal(),
    });
    await _touchProject(projectId);
    return id;
  }

  // ─────────────────────────────────────────── origins

  Future<Map<String, Object?>?> etymologyPage(String lang, String term) async {
    final rows = await _db!.query('etymology_pages',
        where: 'lang = ? AND norm_key = ?',
        whereArgs: [lang, normalize(term)],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveEtymologyPage(
      String lang, String term, String json, String backend) async {
    await _db!.insert(
        'etymology_pages',
        {
          'lang': lang,
          'norm_key': normalize(term),
          'term': term.trim(),
          'json': json,
          'backend': backend,
          'created_at': _nowLocal(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Small key/value facts about this database (last export, clean-ups).
  Future<String?> getMeta(String key) => _meta(key);
  Future<void> setMeta(String key, String value) => _setMeta(key, value);

  Future<String?> _meta(String key) async {
    final rows =
        await _db!.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) => _db!.insert(
      'meta', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ─────────────────────────────────────────── helpers

  static String normalize(String text) =>
      text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// The (wrong, right) text of a mistake's learning item: the fix itself,
  /// or — for a lone function word ("a" → "el") — the fix with its
  /// neighbours from the user's sentence ("Llegaré a 18" → "Llegaré el 18").
  static (String, String) mistakeItemForms(Mistake m) =>
      widenFix(m.original, m.corrected, m.context);

  static int tokenCount(String text) {
    final t = text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  static final _rnd = Random.secure();
  static String newUuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  // ─────────────────────────────────────────── translations

  /// Insert a SETTLED lookup (the screen decides when typing has settled).
  Future<int> addTranslation(TranslationEntry entry) async {
    final norm = normalize(entry.sourceText);
    final map = entry.toMap()
      ..['norm_key'] = norm
      ..['settled'] = 1;
    if ((map['device'] as String? ?? '').isEmpty) map['device'] = deviceId;
    final id = await _db!.insert('translations', map);
    await _bumpPattern(norm, entry.sourceLang, entry.targetLang, 1);
    return id;
  }

  /// The user kept editing the same text after it was committed: replace
  /// the row instead of piling up fragments ("добры" → "добрый день,").
  ///
  /// Returns the id of the row now holding the lookup — a new one if the
  /// original was deleted in History meanwhile.
  Future<int> replaceTranslation(int id, TranslationEntry entry) async {
    final old = await _db!.query('translations',
        columns: [
          'norm_key', 'source_lang', 'target_lang', 'source_text', 'timestamp',
        ],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    if (old.isEmpty) return addTranslation(entry);
    // The fragment's key disappears here; the other device must drop it too.
    await _bury(_db!, 'translations', [translationKey(old.first)]);
    final norm = normalize(entry.sourceText);
    await _db!.update(
      'translations',
      {
        'source_text': entry.sourceText,
        'translated_text': entry.translatedText,
        'source_lang': entry.sourceLang,
        'target_lang': entry.targetLang,
        'translator': entry.translator,
        'norm_key': norm,
        'timestamp': _nowLocal(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final o = old.first;
    await _bumpPattern(o['norm_key'] as String? ?? '',
        o['source_lang'] as String? ?? '', o['target_lang'] as String? ?? '', -1);
    await _bumpPattern(norm, entry.sourceLang, entry.targetLang, 1);
    return id;
  }

  static String _nowLocal() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  Future<void> _bumpPattern(
      String phrase, String src, String tgt, int delta) async {
    if (phrase.isEmpty || tokenCount(phrase) > maxPatternTokens) return;
    if (delta > 0) {
      await _db!.execute('''
        INSERT INTO patterns (phrase, source_lang, target_lang)
        VALUES (?, ?, ?)
        ON CONFLICT(phrase, source_lang, target_lang)
        DO UPDATE SET count = count + 1,
                      last_seen = datetime('now','localtime')
      ''', [phrase, src, tgt]);
    } else {
      await _db!.rawUpdate(
          'UPDATE patterns SET count = count - 1 '
          'WHERE phrase = ? AND source_lang = ? AND target_lang = ?',
          [phrase, src, tgt]);
      await _db!.delete('patterns', where: 'count <= 0');
    }
  }

  /// Count a repeated lookup that was served from cache — before v4 those
  /// were never counted, so "I keep forgetting this word" was invisible.
  Future<void> countCachedLookup(String text, String src, String tgt) =>
      _bumpPattern(normalize(text), src, tgt, 1);

  Future<void> backfillNormKeys() async {
    final rows = await _db!.query('translations',
        columns: ['id', 'source_text'], where: "norm_key IS NULL OR norm_key = ''");
    if (rows.isEmpty) return;
    final batch = _db!.batch();
    for (final r in rows) {
      batch.update('translations',
          {'norm_key': normalize(r['source_text'] as String? ?? '')},
          where: 'id = ?', whereArgs: [r['id']]);
    }
    await batch.commit(noResult: true);
  }

  /// Find keystroke snapshots left by the old 300 ms auto-save: a row whose
  /// text is a prefix of a longer row saved within 2 minutes after it (or
  /// an identical re-save within a minute).
  ///
  /// Only pre-v4 rows (no device stamp) are examined: rows written since v4
  /// are committed only once typing has settled, and "casa" followed a
  /// minute later by "casa grande" is two real lookups.
  ///
  /// The fragments are DELETED from this database, not hidden: they are the
  /// user's private text (letters, names), and a hidden row could neither
  /// be seen nor deleted from History. On the desktop the original legacy
  /// file is never modified; a phone upgrading in place keeps a copy of the
  /// file first (_backupBeforeUpgrade).
  Future<int> markSnapshotRows() async {
    final rows = await _db!.query('translations',
        columns: ['id', 'norm_key', 'timestamp', 'source_lang', 'target_lang'],
        where: "device IS NULL OR device = ''",
        orderBy: 'timestamp ASC, id ASC');
    final parsed = [
      for (final r in rows)
        (
          id: r['id'] as int,
          text: r['norm_key'] as String? ?? '',
          ts: DateTime.tryParse(r['timestamp'] as String? ?? ''),
          pair: '${r['source_lang']}>${r['target_lang']}',
        ),
    ];
    final snapshot = <int>{};
    for (var i = 0; i < parsed.length; i++) {
      final a = parsed[i];
      if (a.ts == null) continue;
      if (a.text.isEmpty) {
        snapshot.add(a.id);
        continue;
      }
      for (var j = i + 1; j < parsed.length; j++) {
        final b = parsed[j];
        if (b.ts == null) continue;
        final gap = b.ts!.difference(a.ts!).inSeconds;
        if (gap > 120) break;
        if (isSnapshotOf(a.text, b.text, gap, samePair: a.pair == b.pair)) {
          snapshot.add(a.id);
          break;
        }
      }
    }
    if (snapshot.isEmpty) return 0;
    final ids = snapshot.toList();
    await _buryTranslations(ids);
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      await _db!.rawDelete(
          'DELETE FROM translations '
          'WHERE id IN (${List.filled(chunk.length, '?').join(',')})',
          chunk);
    }
    return snapshot.length;
  }

  /// Was [a] an intermediate state of typing [b], [gapSec] seconds later?
  /// The old auto-save fired 300 ms after any pause, so rows a few seconds
  /// apart were typing in progress. Visible for tests.
  static bool isSnapshotOf(String a, String b, int gapSec,
      {bool samePair = true}) {
    if (b.length > a.length && b.startsWith(a)) return true; // grew
    if (a == b) return gapSec <= 60; // re-saved
    if (_isTypoEdit(a, b)) return true; // fixed a typo in place
    // Shrinking to a prefix ("política dispar" → "política") means the user
    // looked up a part of a finished text — both lookups are real.
    if (a.startsWith(b)) return false;
    if (gapSec <= 5 && samePair) {
      // Wrong keyboard layout ("jcnfn") or a word abandoned mid-way,
      // replaced seconds later.
      if (tokenCount(a) <= 2 && gapSec <= 3) return true;
      final common = _commonPrefix(a, b);
      if (common >= a.length * 0.6 || common >= a.length - 6) return true;
    }
    return false;
  }

  static int _commonPrefix(String a, String b) {
    final n = min(a.length, b.length);
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  /// "квартр" → "квартиры", "le deriva" → "le derivo": a later text that is
  /// the same sentence with a small in-place correction (≤ 20 % edit
  /// distance). Short strings are excluded — "casa" vs "cosa" are two words.
  static bool _isTypoEdit(String a, String b) {
    if (a == b || a.length < 8 || b.length < 8) return false;
    final longer = max(a.length, b.length);
    if ((a.length - b.length).abs() > longer * 0.2) return false;
    return levenshtein(a, b, limit: (longer * 0.2).floor()) <= longer * 0.2;
  }

  /// Edit distance with an early exit once every cell exceeds [limit].
  static int levenshtein(String a, String b, {int? limit}) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
        if (cur[j] < rowMin) rowMin = cur[j];
      }
      if (limit != null && rowMin > limit) return rowMin;
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }

  /// Patterns = repeated SHORT settled lookups, recomputed from scratch.
  Future<void> rebuildPatterns() async {
    await _db!.delete('patterns');
    await _db!.execute('''
      INSERT INTO patterns (phrase, source_lang, target_lang, count, first_seen, last_seen)
      SELECT norm_key, source_lang, target_lang, COUNT(*), MIN(timestamp), MAX(timestamp)
      FROM translations
      WHERE settled = 1 AND norm_key <> ''
        AND (length(norm_key) - length(replace(norm_key, ' ', '')) + 1) <= ?
      GROUP BY norm_key, source_lang, target_lang
    ''', [maxPatternTokens]);
  }

  Future<void> deleteTranslation(int id) async {
    await _buryTranslations([id]);
    await _db!.delete('translations', where: 'id = ?', whereArgs: [id]);
  }

  /// Bulk delete — one SQL statement per 500 ids (SQLite's 999-param cap).
  Future<int> deleteTranslations(List<int> ids) async {
    if (ids.isEmpty) return 0;
    await _buryTranslations(ids);
    var total = 0;
    const chunkSize = 500;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, min(i + chunkSize, ids.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      total += await _db!.delete(
        'translations',
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
    return total;
  }

  /// L1 of the translation pipeline. Keyed on the Dart-normalized text —
  /// SQLite's LOWER() folds ASCII only, so capitalised Cyrillic never hit.
  Future<TranslationEntry?> cacheLookup({
    required String sourceText,
    required String sourceLang,
    required String targetLang,
  }) async {
    final normalized = normalize(sourceText);
    if (normalized.isEmpty) return null;
    // With an auto-detected source the stored row has the detected language:
    // match on text and target only (before, 'auto' never hit the cache).
    final auto = sourceLang == 'auto' || sourceLang.isEmpty;
    final rows = await _db!.query(
      'translations',
      where: auto
          ? "norm_key = ? AND target_lang = ? AND translated_text <> ''"
          : 'norm_key = ? AND source_lang = ? AND target_lang = ?',
      whereArgs: auto
          ? [normalized, targetLang]
          : [normalized, sourceLang, targetLang],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TranslationEntry.fromMap(rows.first);
  }

  Future<List<TranslationEntry>> getHistory({
    int limit = 200,
    String search = '',
    String sourceLang = '',
    String targetLang = '',
  }) async {
    var where = 'settled = 1';
    final args = <dynamic>[];
    if (search.isNotEmpty) {
      where += ' AND (source_text LIKE ? OR translated_text LIKE ?)';
      args.addAll(['%$search%', '%$search%']);
    }
    if (sourceLang.isNotEmpty) {
      where += ' AND source_lang = ?';
      args.add(sourceLang);
    }
    if (targetLang.isNotEmpty) {
      where += ' AND target_lang = ?';
      args.add(targetLang);
    }
    final rows = await _db!.query(
      'translations',
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(TranslationEntry.fromMap).toList();
  }

  Future<List<PatternEntry>> getTopPatterns({
    int limit = 50,
    int minCount = 2,
    String sourceLang = '',
    String targetLang = '',
  }) async {
    var where = 'count >= ?';
    final args = <dynamic>[minCount];
    if (sourceLang.isNotEmpty) {
      where += ' AND source_lang = ?';
      args.add(sourceLang);
    }
    if (targetLang.isNotEmpty) {
      where += ' AND target_lang = ?';
      args.add(targetLang);
    }
    final rows = await _db!.query(
      'patterns',
      where: where,
      whereArgs: args,
      orderBy: 'count DESC',
      limit: limit,
    );
    return rows.map(PatternEntry.fromMap).toList();
  }

  Future<Map<String, dynamic>> getStats() async {
    final total = Sqflite.firstIntValue(await _db!
            .rawQuery('SELECT COUNT(*) FROM translations WHERE settled = 1')) ??
        0;
    final langPairs = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(DISTINCT source_lang||target_lang) FROM translations '
            'WHERE settled = 1')) ??
        0;
    final hardPatterns = Sqflite.firstIntValue(await _db!
            .rawQuery('SELECT COUNT(*) FROM patterns WHERE count >= 3')) ??
        0;
    return {
      'total': total,
      'lang_pairs': langPairs,
      'hard_patterns': hardPatterns,
    };
  }

  // ─────────────────────────────────────────── mistakes & trainings

  /// Record a mistake; repeated identical mistakes bump seen_count. Returns
  /// the mistake id. Also upserts the matching learning item + event.
  Future<int> addMistake(Mistake m) async {
    // The user said «это не ошибка» about this exact fix: a model repeating
    // the same false positive must not bring it back.
    final prior = await _db!.query('mistakes',
        columns: ['id', 'rejected'],
        where: 'original = ? AND corrected = ? AND lang = ?',
        whereArgs: [m.original, m.corrected, m.lang],
        limit: 1);
    if (prior.isNotEmpty && (prior.first['rejected'] as int? ?? 0) == 1) {
      return prior.first['id'] as int;
    }
    await _db!.execute('''
      INSERT INTO mistakes (original, corrected, reason, category, lang, context,
                            construction, severity, backend, source)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(original, corrected, lang)
      DO UPDATE SET
        seen_count   = seen_count + 1,
        reason       = excluded.reason,
        context      = excluded.context,
        construction = CASE WHEN excluded.construction <> '' THEN excluded.construction ELSE construction END,
        backend      = excluded.backend,
        timestamp    = datetime('now','localtime')
    ''', [
      m.original, m.corrected, m.reason, m.category, m.lang, m.context,
      m.construction, m.severity, m.backend, m.source,
    ]);
    final row = await _db!.query('mistakes',
        columns: ['id'],
        where: 'original = ? AND corrected = ? AND lang = ?',
        whereArgs: [m.original, m.corrected, m.lang],
        limit: 1);
    final id = row.isEmpty ? 0 : row.first['id'] as int;

    // A pure deletion ("Busco a un piso" → drop "a") has no text to learn
    // as an item; the mistake row still carries it.
    if (m.severity == 'error' && m.corrected.trim().isNotEmpty) {
      final (wrong, right) = mistakeItemForms(m);
      final itemId = await upsertItem(
        kind: 'mistake',
        lang: m.lang,
        text: right,
        wrongForm: wrong,
        construction: m.construction,
        source: m.source,
        gloss: m.reason,
        status: 'learning',
      );
      await addEvent(itemId, 'produced_error',
          surface: m.source,
          context: m.context,
          payload: 'backend=${m.backend};mistake_id=$id');
    }
    return id;
  }

  /// "This was actually correct": excluded from training and the feed.
  Future<void> rejectMistake(int id) async {
    final rows = await _db!.query('mistakes',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final m = Mistake.fromMap(rows.first);
    await _db!.update('mistakes', {'rejected': 1},
        where: 'id = ?', whereArgs: [id]);
    if (m.corrected.trim().isEmpty) return;
    // Another, still-valid mistake may share the corrected form (and thus
    // the item) — only retire the item when none is left.
    final (_, itemText) = mistakeItemForms(m);
    final others = await _db!.query('mistakes',
        where: 'rejected = 0 AND lang = ? AND id <> ?',
        whereArgs: [m.lang, id]);
    final norm = normalize(itemText);
    if (others.any((o) =>
        normalize(mistakeItemForms(Mistake.fromMap(o)).$2) == norm)) {
      return;
    }
    final item = await findItem('mistake', m.lang, itemText);
    if (item?.id != null) {
      // last_seen moves too: exchange merges let the later decision win.
      await _db!.rawUpdate(
          "UPDATE learning_items SET status = 'ignored', "
          "status_at = strftime('%Y-%m-%d %H:%M:%f','now','localtime'), "
          "last_seen = datetime('now','localtime') WHERE id = ?",
          [item!.id]);
      await addEvent(item.id, 'fix_rejected', surface: m.source);
    }
  }

  Future<List<Mistake>> getMistakes({
    int limit = 100,
    String lang = '',
    String orderBy = 'seen_count DESC, timestamp DESC',
  }) async {
    final rows = await _db!.query(
      'mistakes',
      where: lang.isEmpty ? 'rejected = 0' : 'rejected = 0 AND lang = ?',
      whereArgs: lang.isEmpty ? null : [lang],
      orderBy: orderBy,
      limit: limit,
    );
    return rows.map(Mistake.fromMap).toList();
  }

  /// Mistakes due for practice: never practised, or their spaced interval has
  /// elapsed. Least-practised and most-repeated come first.
  Future<List<Mistake>> getDueMistakes({int limit = 40, String lang = ''}) async {
    final where = StringBuffer("rejected = 0 AND severity = 'error' AND "
        "(next_due IS NULL OR next_due <= datetime('now','localtime'))");
    final args = <Object?>[];
    if (lang.isNotEmpty) {
      where.write(' AND lang = ?');
      args.add(lang);
    }
    final rows = await _db!.query(
      'mistakes',
      where: where.toString(),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'practice_count ASC, seen_count DESC, timestamp DESC',
      limit: limit,
    );
    return rows.map(Mistake.fromMap).toList();
  }

  Future<int> dueMistakeCount({String lang = ''}) async {
    final sql = StringBuffer(
        "SELECT COUNT(*) FROM mistakes WHERE rejected = 0 AND severity = 'error' "
        "AND (next_due IS NULL OR next_due <= datetime('now','localtime'))");
    final args = <Object?>[];
    if (lang.isNotEmpty) {
      sql.write(' AND lang = ?');
      args.add(lang);
    }
    return Sqflite.firstIntValue(await _db!.rawQuery(sql.toString(), args)) ?? 0;
  }

  /// Advance the review ladder (1 → 3 → 7 → 21 → 60 days). Call ONLY after
  /// the user actually answered — generating a session is not a review.
  Future<void> markPracticed(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final placeholders = List.filled(list.length, '?').join(',');
    await _db!.rawUpdate('''
      UPDATE mistakes
      SET practice_count = practice_count + 1,
          last_practiced = datetime('now','localtime'),
          next_due = datetime('now','localtime',
            '+' || (CASE practice_count
                      WHEN 0 THEN 1
                      WHEN 1 THEN 3
                      WHEN 2 THEN 7
                      WHEN 3 THEN 21
                      ELSE 60 END) || ' days')
      WHERE id IN ($placeholders)
    ''', list);
  }

  /// Note that these mistakes appeared in a generated session, without
  /// moving the schedule (nothing was recalled yet).
  Future<void> markShown(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final placeholders = List.filled(list.length, '?').join(',');
    await _db!.rawUpdate(
        "UPDATE mistakes SET last_practiced = datetime('now','localtime') "
        'WHERE id IN ($placeholders)',
        list);
  }

  Future<int> mistakeCount() async =>
      Sqflite.firstIntValue(await _db!
          .rawQuery('SELECT COUNT(*) FROM mistakes WHERE rejected = 0')) ??
      0;

  Future<void> deleteMistake(int id) async {
    final rows = await _db!.query('mistakes',
        columns: ['original', 'corrected', 'lang'],
        where: 'id = ?',
        whereArgs: [id]);
    await _bury(_db!, 'mistakes', rows.map(mistakeKey));
    await _db!.delete('mistakes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addTraining(String lang, String content,
          {List<int> mistakeIds = const []}) async =>
      _db!.insert('trainings', {
        'lang': lang,
        'content': content,
        'mistake_ids': mistakeIds.join(','),
      });

  /// The user worked through a session: advance its mistakes one step on
  /// the review ladder (once per session).
  Future<void> markTrainingDone(int trainingId) async {
    final rows = await _db!.query('trainings',
        where: 'id = ? AND done_at IS NULL', whereArgs: [trainingId], limit: 1);
    if (rows.isEmpty) return;
    final ids = (rows.first['mistake_ids'] as String? ?? '')
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    await markPracticed(ids);
    await _db!.rawUpdate(
        "UPDATE trainings SET done_at = datetime('now','localtime') WHERE id = ?",
        [trainingId]);
  }

  Future<List<TrainingEntry>> getTrainings({int limit = 20}) async {
    final rows = await _db!.query(
      'trainings',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(TrainingEntry.fromMap).toList();
  }

  Future<void> deleteTraining(int id) async {
    final rows = await _db!.query('trainings',
        columns: ['timestamp', 'content'], where: 'id = ?', whereArgs: [id]);
    await _bury(_db!, 'trainings', rows.map(trainingKey));
    await _db!.delete('trainings', where: 'id = ?', whereArgs: [id]);
  }

  // ─────────────────────────────────────────── learner model

  /// Insert or refresh a learning item; returns its id. Status only moves
  /// "up" (seen → learning), never back down, except via explicit calls.
  Future<int> upsertItem({
    required String kind,
    required String lang,
    required String text,
    String gloss = '',
    String wrongForm = '',
    String construction = '',
    String conceptKey = '',
    String source = '',
    String status = 'seen',
    String notes = '',
  }) async {
    final norm = normalize(text);
    // status_at is the clock of the user's decision (see _upgradeToV6): set
    // when an item is created with a status other than 'seen', and moved
    // only when the status really changes.
    const newStatus = '''CASE
                         WHEN status = 'seen' AND excluded.status IN ('learning','known') THEN excluded.status
                         WHEN status = 'ignored' AND excluded.status = 'learning' THEN 'learning'
                         ELSE status END''';
    await _db!.execute('''
      INSERT INTO learning_items (uuid, kind, lang, text, norm_key, gloss, wrong_form,
                                  construction, concept_key, source, status, notes,
                                  status_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
              CASE WHEN ? <> 'seen' THEN strftime('%Y-%m-%d %H:%M:%f','now','localtime') END)
      ON CONFLICT(kind, lang, norm_key) DO UPDATE SET
        last_seen    = datetime('now','localtime'),
        gloss        = CASE WHEN excluded.gloss <> '' THEN excluded.gloss ELSE gloss END,
        wrong_form   = CASE WHEN excluded.wrong_form <> '' THEN excluded.wrong_form ELSE wrong_form END,
        construction = CASE WHEN excluded.construction <> '' THEN excluded.construction ELSE construction END,
        concept_key  = CASE WHEN excluded.concept_key <> '' THEN excluded.concept_key ELSE concept_key END,
        notes        = CASE WHEN excluded.notes <> '' THEN excluded.notes ELSE notes END,
        status       = $newStatus,
        status_at    = CASE WHEN ($newStatus) <> status
                         THEN strftime('%Y-%m-%d %H:%M:%f','now','localtime') ELSE status_at END
    ''', [
      newUuid(), kind, lang, text.trim(), norm, gloss, wrongForm,
      construction, conceptKey, source, status, notes, status,
    ]);
    final rows = await _db!.query('learning_items',
        columns: ['id'],
        where: 'kind = ? AND lang = ? AND norm_key = ?',
        whereArgs: [kind, lang, norm],
        limit: 1);
    return rows.first['id'] as int;
  }

  Future<LearningItem?> findItem(String kind, String lang, String text) async {
    final rows = await _db!.query('learning_items',
        where: 'kind = ? AND lang = ? AND norm_key = ?',
        whereArgs: [kind, lang, normalize(text)],
        limit: 1);
    return rows.isEmpty ? null : LearningItem.fromMap(rows.first);
  }

  static const _counterByEvent = {
    'lookup': 'lookups',
    'exposure': 'exposures',
    'recall_ok': 'recall_ok',
    'recall_fail': 'recall_fail',
    'produced_ok': 'produced_ok',
    'produced_error': 'produced_err',
  };

  /// Append an event and update the item's counters.
  Future<void> addEvent(
    int? itemId,
    String type, {
    String surface = '',
    String context = '',
    int? translationId,
    String payload = '',
  }) async {
    await _db!.insert('item_events', {
      'uuid': newUuid(),
      'item_id': itemId,
      'type': type,
      'surface': surface,
      'context': context.length > 300 ? context.substring(0, 300) : context,
      'translation_id': translationId,
      'device': deviceId,
      'payload': payload,
    });
    if (itemId == null) return;
    final counter = _counterByEvent[type];
    if (counter != null) {
      await _db!.rawUpdate(
          'UPDATE learning_items SET $counter = $counter + 1, '
          "last_seen = datetime('now','localtime') WHERE id = ?",
          [itemId]);
    }
    if (type == 'saved') {
      await _db!.rawUpdate(
          "UPDATE learning_items SET status = 'learning', "
          "status_at = strftime('%Y-%m-%d %H:%M:%f','now','localtime') "
          "WHERE id = ? AND status <> 'learning'",
          [itemId]);
    }
  }

  Future<void> setItemStatus(int id, String status) async {
    await _db!.rawUpdate(
        'UPDATE learning_items SET status = ?, '
        "status_at = strftime('%Y-%m-%d %H:%M:%f','now','localtime'), "
        "last_seen = datetime('now','localtime') WHERE id = ?",
        [status, id]);
    await addEvent(id, status == 'learning' ? 'saved' : 'status_$status');
  }

  Future<List<LearningItem>> getItems({
    List<String> statuses = const ['learning'],
    String kind = '',
    String lang = '',
    int limit = 200,
  }) async {
    final where = StringBuffer(
        'status IN (${List.filled(statuses.length, '?').join(',')})');
    final args = <Object?>[...statuses];
    if (kind.isNotEmpty) {
      where.write(' AND kind = ?');
      args.add(kind);
    }
    if (lang.isNotEmpty) {
      where.write(' AND lang = ?');
      args.add(lang);
    }
    final rows = await _db!.query('learning_items',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'last_seen DESC',
        limit: limit);
    return rows.map(LearningItem.fromMap).toList();
  }

  /// {kind: count} of items being learned — for Insights.
  Future<Map<String, int>> learningCounts() async {
    final rows = await _db!.rawQuery(
        "SELECT kind, COUNT(*) AS n FROM learning_items WHERE status = 'learning' "
        'GROUP BY kind');
    return {for (final r in rows) r['kind'] as String: r['n'] as int};
  }

  /// Problem constructions ranked by how often the user got them wrong.
  Future<List<(String, int)>> topConstructions({String lang = '', int limit = 10}) async {
    final rows = await _db!.rawQuery('''
      SELECT construction, SUM(seen_count) AS n FROM mistakes
      WHERE rejected = 0 AND severity = 'error' AND construction <> ''
        ${lang.isEmpty ? '' : 'AND lang = ?'}
      GROUP BY construction ORDER BY n DESC LIMIT ?
    ''', [if (lang.isNotEmpty) lang, limit]);
    return [
      for (final r in rows) (r['construction'] as String, (r['n'] as num).toInt())
    ];
  }

  // ─────────────────────────────────────────── AI usage

  Future<void> logAiUsage({
    required String feature,
    required String provider,
    String model = '',
    int inputTokens = 0,
    int outputTokens = 0,
    double costUsd = 0,
    int durationMs = 0,
    bool ok = true,
    String error = '',
  }) async {
    await _db!.insert('ai_usage', {
      'feature': feature,
      'provider': provider,
      'model': model,
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'cost_usd': costUsd,
      'duration_ms': durationMs,
      'ok': ok ? 1 : 0,
      'error': error.length > 500 ? error.substring(0, 500) : error,
    });
  }

  /// (requests, successful, estimated $) for the current calendar month.
  Future<(int, int, double)> aiUsageThisMonth() async {
    final rows = await _db!.rawQuery('''
      SELECT COUNT(*) AS n, SUM(ok) AS good, SUM(cost_usd) AS cost FROM ai_usage
      WHERE ts >= datetime('now','localtime','start of month')
    ''');
    final r = rows.first;
    return (
      (r['n'] as num?)?.toInt() ?? 0,
      (r['good'] as num?)?.toInt() ?? 0,
      (r['cost'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // ─────────────────────────────────────────── legacy import

  /// Merge an older LinguaTrace database (any schema version) into this
  /// one. Idempotent: rows already present are skipped, and a file whose
  /// size+mtime were imported before is not re-read. Returns rows added.
  Future<int> importLegacyDatabase(String path) async {
    final f = File(path);
    if (!f.existsSync()) return 0;
    final stat = f.statSync();
    final mtime = stat.modified.toIso8601String();
    final seen = await _db!.query('imported_sources',
        where: 'path = ? AND size = ? AND mtime = ?',
        whereArgs: [path, stat.size, mtime]);
    if (seen.isNotEmpty) return 0;

    var added = 0;
    await _db!.execute('ATTACH DATABASE ? AS src', [path]);
    try {
      final tables = (await _db!.rawQuery(
              "SELECT name FROM src.sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      Future<Set<String>> cols(String t) async =>
          (await _db!.rawQuery('PRAGMA src.table_info($t)'))
              .map((r) => r['name'] as String)
              .toSet();

      if (tables.contains('translations')) {
        final c = await cols('translations');
        final ctx = c.contains('context_app') ? "COALESCE(s.context_app,'')" : "''";
        final dev = c.contains('device') ? "COALESCE(s.device,'')" : "''";
        final before = await _count('translations');
        await _db!.execute('''
          INSERT INTO translations (source_text, translated_text, source_lang, target_lang,
                                    translator, context_app, timestamp, device, settled)
          SELECT s.source_text, s.translated_text, s.source_lang, s.target_lang,
                 s.translator, $ctx, s.timestamp, $dev, 1
          FROM src.translations s
          WHERE NOT EXISTS (SELECT 1 FROM translations m
                            WHERE m.source_text = s.source_text AND m.timestamp = s.timestamp)
        ''');
        added += await _count('translations') - before;
      }
      if (tables.contains('mistakes')) {
        final before = await _count('mistakes');
        await _db!.execute('''
          INSERT OR IGNORE INTO mistakes (original, corrected, reason, category, lang,
                                          context, timestamp, seen_count, source)
          SELECT original, corrected, COALESCE(reason,''), COALESCE(category,''),
                 COALESCE(lang,''), COALESCE(context,''), timestamp,
                 COALESCE(seen_count,1), 'import'
          FROM src.mistakes
        ''');
        added += await _count('mistakes') - before;
      }
      if (tables.contains('trainings')) {
        final before = await _count('trainings');
        await _db!.execute('''
          INSERT INTO trainings (timestamp, lang, content)
          SELECT s.timestamp, COALESCE(s.lang,''), s.content FROM src.trainings s
          WHERE NOT EXISTS (SELECT 1 FROM trainings m
                            WHERE m.timestamp = s.timestamp AND m.content = s.content)
        ''');
        added += await _count('trainings') - before;
      }
    } finally {
      await _db!.execute('DETACH DATABASE src');
    }

    await _db!.insert('imported_sources', {
      'path': path,
      'size': stat.size,
      'mtime': mtime,
      'rows': added,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (added > 0) {
      await backfillNormKeys();
      await markSnapshotRows();
      await rebuildPatterns();
      await _itemsFromImportedMistakes();
    }
    return added;
  }

  Future<int> _count(String table) async =>
      Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  /// Mistakes that arrived without learning items (imports, pre-v4 rows).
  Future<void> _itemsFromImportedMistakes() async {
    final rows = await _db!.query('mistakes',
        where: "rejected = 0 AND severity = 'error' AND trim(corrected) <> ''");
    for (final r in rows) {
      final m = Mistake.fromMap(r);
      final (wrong, right) = mistakeItemForms(m);
      if (await findItem('mistake', m.lang, right) != null) continue;
      await upsertItem(
        kind: 'mistake',
        lang: m.lang,
        text: right,
        wrongForm: wrong,
        construction: m.construction,
        source: m.source,
        gloss: m.reason,
        status: 'learning',
      );
    }
  }

  /// Items for pre-v4 mistakes already in this database.
  Future<void> ensureMistakeItems() => _itemsFromImportedMistakes();

  // ─────────────────────────────────────────── news feed

  /// Store harvested articles (headline + lead only); prune stale unused
  /// ones after a week.
  Future<int> saveArticles(List<NewsArticle> list) async {
    var added = 0;
    final batch = _db!.batch();
    for (final a in list) {
      final m = a.toMap()..remove('id');
      batch.insert('news_articles', m,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    final res = await batch.commit();
    for (final r in res) {
      if (r is int && r > 0) added++;
    }
    await _db!.rawDelete(
        "DELETE FROM news_articles WHERE used_count = 0 "
        "AND fetched_at < datetime('now','localtime','-7 days')");
    return added;
  }

  /// Fresh articles in [lang], newest first. Stories already retold are
  /// left out unless [includeUsed] — the feed should bring new events.
  Future<List<NewsArticle>> recentArticles(
      {required String lang,
      int hours = 72,
      int limit = 200,
      bool includeUsed = false}) async {
    final rows = await _db!.rawQuery('''
      SELECT * FROM news_articles
      WHERE lang = ? AND (published_at IS NULL OR published_at >= ?)
        ${includeUsed ? '' : 'AND used_count = 0'}
      ORDER BY used_count ASC, published_at DESC
      LIMIT ?
    ''', [
      lang,
      DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String(),
      limit,
    ]);
    return rows.map(NewsArticle.fromMap).toList();
  }

  Future<void> markArticlesUsed(Iterable<int> ids) async {
    for (final id in ids) {
      await _db!.rawUpdate(
          'UPDATE news_articles SET used_count = used_count + 1 WHERE id = ?',
          [id]);
    }
  }

  Future<int> createEdition(String lang, int planned) => _db!.insert(
      'feed_editions', {'uuid': newUuid(), 'lang': lang, 'planned': planned});

  Future<void> finishEdition(int id, {String error = ''}) => _db!.update(
      'feed_editions', {'status': error.isEmpty ? 'done' : 'failed', 'error': error},
      where: 'id = ?', whereArgs: [id]);

  /// Today's edition in [lang], if one was built.
  Future<int?> todaysEdition(String lang) async {
    final rows = await _db!.rawQuery('''
      SELECT e.id FROM feed_editions e
      WHERE e.lang = ? AND date(e.created_at) = date('now','localtime')
        AND EXISTS (SELECT 1 FROM feed_items i WHERE i.edition_id = e.id)
      ORDER BY e.id DESC LIMIT 1
    ''', [lang]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Persist one validated feed item with its target spans and tasks.
  Future<int> saveFeedItem(
    FeedItem item,
    List<FeedItemTarget> targets,
    List<FeedTask> tasks, {
    List<int> articleIds = const [],
    String sourcesJson = '',
  }) async {
    return _db!.transaction((txn) async {
      final id = await txn.insert('feed_items', {
        'uuid': newUuid(),
        'edition_id': item.editionId,
        'lang': item.lang,
        'headline': item.headline,
        'body': item.body,
        'attribution': item.attribution,
        'outlet': item.outlet,
        'source_url': item.sourceUrl,
        'published_at': item.publishedAt,
        'sources_json': sourcesJson,
        'backend': item.backend,
      });
      for (final t in targets) {
        await txn.insert(
            'feed_item_targets',
            {
              'feed_item_id': id,
              'item_id': t.itemId,
              'start_pos': t.start,
              'end_pos': t.end,
              'form_used': t.form,
              'highlight': t.highlight ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final t in tasks) {
        await txn.insert('feed_tasks', {
          'uuid': newUuid(),
          'feed_item_id': id,
          'item_id': t.itemId,
          'kind': t.kind,
          'prompt_ru': t.promptRu,
          'text': t.text,
          'options': t.options.join('␟'),
          'answer': t.answer,
        });
      }
      for (final a in articleIds) {
        await txn.rawUpdate(
            'UPDATE news_articles SET used_count = used_count + 1 WHERE id = ?',
            [a]);
      }
      return id;
    });
  }

  /// Feed items (newest first) with their targets and tasks.
  Future<List<FeedItem>> getFeedItems({int? editionId, int limit = 40}) async {
    final rows = await _db!.query('feed_items',
        where: editionId == null ? null : 'edition_id = ?',
        whereArgs: editionId == null ? null : [editionId],
        orderBy: 'id DESC',
        limit: limit);
    final out = <FeedItem>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final targets = (await _db!.rawQuery('''
        SELECT t.*, i.kind, i.text, i.gloss, i.wrong_form, i.construction
        FROM feed_item_targets t LEFT JOIN learning_items i ON i.id = t.item_id
        WHERE t.feed_item_id = ? ORDER BY t.start_pos
      ''', [id])).map(FeedItemTarget.fromMap).toList();
      final tasks = (await _db!.query('feed_tasks',
              where: 'feed_item_id = ?', whereArgs: [id], orderBy: 'id'))
          .map(FeedTask.fromMap)
          .toList();
      out.add(FeedItem.fromMap(r, targets: targets, tasks: tasks));
    }
    return out;
  }

  Future<FeedItem?> getFeedItem(int id) async {
    final rows = await _db!.query('feed_items',
        columns: ['edition_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final all = await getFeedItems(
        editionId: rows.first['edition_id'] as int, limit: 1000);
    for (final i in all) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Free answers stored as 'pending' (written where no AI was available).
  Future<List<(FeedItem, FeedTask)>> pendingFeedTasks() async {
    final rows = await _db!.query('feed_tasks',
        where: "result = 'pending' AND user_answer <> ''", orderBy: 'id');
    final out = <(FeedItem, FeedTask)>[];
    for (final r in rows) {
      final item = await getFeedItem(r['feed_item_id'] as int);
      if (item != null) out.add((item, FeedTask.fromMap(r)));
    }
    return out;
  }

  /// First time the user sees an item: exposure events for its targets.
  Future<void> markFeedItemRead(int feedItemId) async {
    final n = await _db!.rawUpdate(
        "UPDATE feed_items SET read_at = datetime('now','localtime') "
        'WHERE id = ? AND read_at IS NULL',
        [feedItemId]);
    if (n == 0) return;
    final targets = await _db!.query('feed_item_targets',
        columns: ['item_id'], where: 'feed_item_id = ?', whereArgs: [feedItemId]);
    for (final t in targets.map((t) => t['item_id'] as int).toSet()) {
      await addEvent(t, 'exposure',
          surface: 'feed', payload: 'feed_item=$feedItemId');
    }
  }

  Future<void> saveTaskResult(int taskId, String userAnswer, String result) =>
      _db!.update(
          'feed_tasks',
          {
            'user_answer': userAnswer,
            'result': result,
            'done_at': _nowLocal(),
          },
          where: 'id = ?',
          whereArgs: [taskId]);

  /// Days until the next review for each SRS stage (graded recall only).
  static const srsLadderDays = [1, 3, 7, 21, 60, 120];

  Future<void> _moveStage(int itemId, int delta, {bool failed = false}) async {
    final rows = await _db!.rawQuery(
        'SELECT stage, (next_due IS NULL OR '
        "next_due <= datetime('now','localtime')) AS due "
        'FROM learning_items WHERE id = ?',
        [itemId]);
    if (rows.isEmpty) return;
    // A success before the item is due — the same target in the next story,
    // a second task of one sitting — is logged (events, counters) but does
    // not promote: the ladder measures spacing, not the number of taps.
    if (!failed && (rows.first['due'] as int? ?? 1) == 0) return;
    final stage = ((rows.first['stage'] as int? ?? 0) + delta)
        .clamp(0, srsLadderDays.length);
    final days = failed ? 1 : srsLadderDays[max(0, stage - 1)];
    await _db!.rawUpdate(
        "UPDATE learning_items SET stage = ?, status = CASE WHEN status = 'seen' "
        "THEN 'learning' ELSE status END, "
        "status_at = CASE WHEN status = 'seen' "
        "THEN strftime('%Y-%m-%d %H:%M:%f','now','localtime') ELSE status_at END, "
        "srs_at = strftime('%Y-%m-%d %H:%M:%f','now','localtime'), "
        "next_due = datetime('now','localtime','+$days days') WHERE id = ?",
        [stage, itemId]);
  }

  /// Graded recall (cloze / choice) — the only thing besides production
  /// that moves the schedule.
  Future<void> recordRecall(int itemId, bool ok, {String surface = 'feed'}) async {
    await addEvent(itemId, ok ? 'recall_ok' : 'recall_fail', surface: surface);
    await _moveStage(itemId, ok ? 1 : -1, failed: !ok);
  }

  /// Free production (rephrase / retell / own text) of a target.
  Future<void> recordProduction(int itemId, bool ok,
      {String surface = 'feed', String context = ''}) async {
    await addEvent(itemId, ok ? 'produced_ok' : 'produced_error',
        surface: surface, context: context);
    await _moveStage(itemId, ok ? 2 : -1, failed: !ok);
  }

  /// Items the feed may target in [lang], most urgent first within each
  /// kind: due reviews, then things the user got wrong, then least-seen.
  /// Each kind has its own quota, so sixty due mistakes cannot crowd the
  /// user's idioms out of the plan.
  Future<List<LearningItem>> feedCandidates(String lang, {int perKind = 30}) async {
    final out = <LearningItem>[];
    for (final kinds in const [
      "kind = 'mistake'",
      "kind NOT IN ('mistake', 'proverb')",
      "kind = 'proverb'",
    ]) {
      final rows = await _db!.rawQuery('''
        SELECT * FROM learning_items
        WHERE lang = ? AND $kinds AND status <> 'ignored' AND status <> 'known'
          AND (status = 'learning' OR (source = 'lookup_produce' AND lookups > 0))
        ORDER BY (next_due IS NULL OR next_due <= datetime('now','localtime')) DESC,
                 produced_err DESC, exposures ASC, last_seen DESC
        LIMIT ?
      ''', [lang, perKind]);
      out.addAll(rows.map(LearningItem.fromMap));
    }
    return out;
  }

  Future<int> dueItemCount(String lang) async =>
      Sqflite.firstIntValue(await _db!.rawQuery('''
        SELECT COUNT(*) FROM learning_items
        WHERE lang = ? AND status = 'learning'
          AND (next_due IS NULL OR next_due <= datetime('now','localtime'))
      ''', [lang])) ??
      0;

  /// New seed expressions introduced today (cap: 2/day).
  Future<int> seedsIntroducedToday(String lang) async =>
      Sqflite.firstIntValue(await _db!.rawQuery('''
        SELECT COUNT(*) FROM learning_items
        WHERE lang = ? AND source = 'seed' AND date(first_seen) = date('now','localtime')
      ''', [lang])) ??
      0;

  // ─────────────────────────────────────────── sync (legacy)

  /// Export all rows for sync — returns maps ready for JSON.
  Future<List<Map<String, dynamic>>> exportAll() async =>
      await _db!.query('translations', orderBy: 'id ASC');

  /// Import rows coming from the desktop sync server.
  Future<void> importRows(List<Map<String, dynamic>> rows) async {
    final batch = _db!.batch();
    for (final r in rows) {
      batch.insert('translations', r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    await backfillNormKeys();
    await rebuildPatterns();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
