/// One place for everything the user accumulates — the notebook, mistakes,
/// trainings, feed editions with their answers, and history — as a single
/// exchange file per device, merged idempotently on any other device.
///
/// Why: feed editions are written on the PC through the Claude subscription
/// (the phone can't use it); the phone reads them and does the tasks; the
/// answers and new mistakes flow back. On the PC a folder holds one file per
/// device (point it at OneDrive and it syncs by itself); on the phone the
/// file is sent/loaded through the system share sheet and file picker.
///
/// Merge rules (natural keys, never local ids, so independent devices meet):
///   learning items by (kind, lang, normalized text): the user's decision
///   (status) and the review schedule (stage, next_due) each follow their
///   own clock — status_at, srs_at — so a later lookup elsewhere cannot undo
///   «убрать из тетради» or a review; counters are recounted from the merged
///   event log. Mistakes by (original, corrected, lang); «это не ошибка» is
///   sticky. Translations by (text, timestamp, pair). Events and feed
///   editions/items/tasks by uuid. Rows deleted on one device travel as
///   tombstones and are deleted, never re-imported, on the other.
///
/// Privacy: the file is plain JSON. By default it carries short lookups
/// only (long texts — letters — stay on the device), and a mistake keeps
/// only the sentence it was found in.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/database.dart';

class ExchangeReport {
  int translations = 0;
  int items = 0;
  int mistakes = 0;
  int events = 0;
  int trainings = 0;
  int feedItems = 0;
  int tasksUpdated = 0;
  int deleted = 0;
  int ideas = 0;
  int files = 0;
  final errors = <String>[];

  int get total =>
      translations +
      items +
      mistakes +
      events +
      trainings +
      feedItems +
      tasksUpdated +
      deleted +
      ideas;

  void add(ExchangeReport o) {
    translations += o.translations;
    items += o.items;
    mistakes += o.mistakes;
    events += o.events;
    trainings += o.trainings;
    feedItems += o.feedItems;
    tasksUpdated += o.tasksUpdated;
    deleted += o.deleted;
    ideas += o.ideas;
    files += o.files;
    uploaded = uploaded || o.uploaded;
    errors.addAll(o.errors);
  }

  /// This device's data went to the sync server.
  bool uploaded = false;
}

/// The sync server refused or could not be reached; [message] is for the user.
class SyncServerException implements Exception {
  const SyncServerException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ExchangeService {
  final DatabaseService _dbs;
  final bool Function() _fullHistory;

  /// [fullHistory] — include every translation, not only short lookups
  /// (read at export time: the setting can change while the app runs).
  ExchangeService(this._dbs, {bool Function()? fullHistory})
      : _fullHistory = fullHistory ?? (() => false);

  static const format = 'linguatrace-exchange';

  /// 2: status_at / srs_at clocks and tombstones.
  static const version = 2;

  /// A real exchange file is a few MB after years of use; anything much
  /// larger was picked by mistake (a video) and would only exhaust memory.
  static const maxFileBytes = 50 * 1024 * 1024;

  Database get _db => _dbs.sqlite;

  /// 'windows-HOST' / 'android' — file-name friendly.
  static String get deviceSlug => DatabaseService.deviceId
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .toLowerCase();

  static String fileNameFor(String slug) => 'linguatrace-$slug.json';

  // One exchange job at a time: the startup sync, the export after a new
  // edition and «Синхронизировать сейчас» can overlap.
  static Future<void> _tail = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  // ─────────────────────────────────────────── export

  Future<Map<String, dynamic>> buildBundle() async {
    // Rows from before uuids existed get one now, so they can be merged.
    for (final t in ['feed_editions', 'feed_items', 'feed_tasks']) {
      final rows = await _db.query(t, columns: ['id'], where: 'uuid IS NULL');
      if (rows.isEmpty) continue;
      final batch = _db.batch();
      for (final r in rows) {
        batch.update(t, {'uuid': DatabaseService.newUuid()},
            where: 'id = ?', whereArgs: [r['id']]);
      }
      await batch.commit(noResult: true);
    }

    final items = await _db.query('learning_items');
    final itemKey = {
      for (final r in items) r['id'] as int: _itemKeyOf(r),
    };
    final mistakes = await _db.query('mistakes');
    final mistakeKey = {
      for (final r in mistakes) r['id'] as int: DatabaseService.mistakeKey(r),
    };
    final editions = await _db.query('feed_editions');
    final editionUuid = {
      for (final r in editions) r['id'] as int: r['uuid'],
    };
    final targetsOf = <int, List<Map<String, Object?>>>{};
    for (final t in await _db.query('feed_item_targets')) {
      (targetsOf[t['feed_item_id'] as int] ??= []).add(t);
    }
    final tasksOf = <int, List<Map<String, Object?>>>{};
    for (final t in await _db.query('feed_tasks', orderBy: 'id')) {
      (tasksOf[t['feed_item_id'] as int] ??= []).add(t);
    }

    Map<String, Object?> strip(Map<String, Object?> r, List<String> drop) =>
        Map.of(r)..removeWhere((k, _) => drop.contains(k));

    final full = _fullHistory();
    return {
      'format': format,
      'version': version,
      'device': DatabaseService.deviceId,
      'exported_at': DateTime.now().toIso8601String(),
      'full_history': full,
      'translations': [
        for (final r in await _db.query('translations'))
          if (full || _shortLookup(r)) strip(r, ['id']),
      ],
      'mistakes': [
        for (final r in mistakes)
          {
            ...strip(r, ['id']),
            'context': contextSnippet(
                r['context'] as String? ?? '', r['original'] as String? ?? ''),
          },
      ],
      'trainings': [
        for (final r in await _db.query('trainings'))
          {
            ...strip(r, ['id', 'mistake_ids']),
            'mistakes': ((r['mistake_ids'] as String?) ?? '')
                .split(',')
                .map(int.tryParse)
                .whereType<int>()
                .map((id) => mistakeKey[id])
                .whereType<List>()
                .toList(),
          },
      ],
      'learning_items': [for (final r in items) strip(r, ['id'])],
      'item_events': [
        for (final r in await _db.query('item_events'))
          {
            ...strip(r, ['id', 'item_id', 'translation_id']),
            'context': _clip(r['context'] as String? ?? '', 160),
            'item': r['item_id'] == null ? null : itemKey[r['item_id']],
          },
      ],
      'feed_editions': [for (final r in editions) strip(r, ['id'])],
      'feed_items': [
        for (final r in await _db.query('feed_items'))
          {
            ...strip(r, ['id', 'edition_id']),
            'edition': editionUuid[r['edition_id']],
            'targets': [
              for (final t in targetsOf[r['id']] ?? const <Map<String, Object?>>[])
                {
                  'item': itemKey[t['item_id']],
                  'start_pos': t['start_pos'],
                  'end_pos': t['end_pos'],
                  'form_used': t['form_used'],
                  'highlight': t['highlight'],
                },
            ],
            'tasks': [
              for (final t in tasksOf[r['id']] ?? const <Map<String, Object?>>[])
                {
                  ...strip(t, ['id', 'feed_item_id', 'item_id']),
                  'item': t['item_id'] == null ? null : itemKey[t['item_id']],
                },
            ],
          },
      ],
      'etymology_pages': [
        for (final r in await _db.query('etymology_pages')) Map.of(r),
      ],
      ...await _ideasBundle(strip),
      'tombstones': [
        for (final r in await _db.query('tombstones'))
          {'tbl': r['tbl'], 'key': r['key'], 'deleted_at': r['deleted_at']},
      ],
    };
  }

  /// «Идеи»: rows refer to each other by uuid in the file.
  Future<Map<String, Object?>> _ideasBundle(
      Map<String, Object?> Function(Map<String, Object?>, List<String>) strip) async {
    final projects = await _db.query('idea_projects');
    final projectUuid = {for (final r in projects) r['id']: r['uuid']};
    final notes = await _db.query('idea_notes');
    final noteUuid = {for (final r in notes) r['id']: r['uuid']};
    return {
      'idea_projects': [for (final r in projects) strip(r, ['id'])],
      'idea_notes': [
        for (final r in notes)
          if (projectUuid[r['project_id']] != null)
            {...strip(r, ['id', 'project_id']), 'project': projectUuid[r['project_id']]},
      ],
      'idea_sources': [
        for (final r in await _db.query('idea_sources'))
          if (projectUuid[r['project_id']] != null)
            {...strip(r, ['id', 'project_id']), 'project': projectUuid[r['project_id']]},
      ],
      'idea_insights': [
        for (final r in await _db.query('idea_insights'))
          if (projectUuid[r['project_id']] != null)
            {
              ...strip(r, ['id', 'project_id', 'note_id']),
              'project': projectUuid[r['project_id']],
              'note': noteUuid[r['note_id']],
            },
      ],
    };
  }

  static List<Object?> _itemKeyOf(Map<String, Object?> r) =>
      [r['kind'], r['lang'], r['norm_key']];

  /// A short, settled lookup — what patterns and the notebook are made of.
  static bool _shortLookup(Map<String, Object?> r) =>
      (r['settled'] as int? ?? 1) == 1 &&
      DatabaseService.tokenCount(r['source_text'] as String? ?? '') <=
          DatabaseService.maxPatternTokens;

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  static final _sentenceEnd = RegExp(r'[.!?\n]');

  /// The sentence of [context] that contains [original], at most 200
  /// characters around it: enough to understand the mistake, without the
  /// rest of the user's letter. Empty when [original] is not in it.
  static String contextSnippet(String context, String original) {
    if (context.isEmpty || original.isEmpty) return '';
    final at = context.indexOf(original);
    if (at < 0) return '';
    var s = at, e = at + original.length;
    while (s > 0 && !_sentenceEnd.hasMatch(context[s - 1])) {
      s--;
    }
    while (e < context.length && !_sentenceEnd.hasMatch(context[e])) {
      e++;
    }
    if (e < context.length) e++;
    if (e - s > 200) {
      final mid = at + original.length ~/ 2;
      s = (mid - 100).clamp(s, e);
      e = (s + 200).clamp(s, e);
    }
    return context.substring(s, e).trim();
  }

  /// Write this device's bundle into [dir] (atomically). Returns the path.
  Future<String> exportTo(String dir, {String? fileName}) =>
      _serial(() => _export(dir, fileName ?? fileNameFor(deviceSlug)));

  /// Cheap summary of everything the bundle carries: when it has not
  /// changed since the last export, the file is not rebuilt (the export
  /// ran on every start and after every edition).
  Future<String> _fingerprint() async {
    final row = (await _db.rawQuery('''
      SELECT
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) || ':' || IFNULL(MAX(timestamp),'') FROM translations) AS t,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) || ':' || IFNULL(SUM(seen_count),0) || ':' ||
                IFNULL(SUM(rejected),0) || ':' || IFNULL(MAX(timestamp),'') || ':' ||
                IFNULL(MAX(last_practiced),'') FROM mistakes) AS m,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) || ':' || IFNULL(MAX(done_at),'') FROM trainings) AS tr,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) || ':' || IFNULL(MAX(last_seen),'') || ':' ||
                IFNULL(MAX(status_at),'') || ':' || IFNULL(MAX(srs_at),'') || ':' ||
                IFNULL(SUM(lookups + exposures + recall_ok + recall_fail + produced_ok + produced_err),0)
           FROM learning_items) AS i,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) FROM item_events) AS e,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) || ':' || IFNULL(MAX(status),'') FROM feed_editions) AS fe,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(id),0) || ':' || IFNULL(MAX(read_at),'') FROM feed_items) AS fi,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(done_at),'') || ':' || IFNULL(SUM(length(user_answer)),0)
           FROM feed_tasks) AS ft,
        (SELECT COUNT(*) FROM feed_item_targets) AS fg,
        (SELECT COUNT(*) FROM tombstones) AS tb,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(created_at),'') FROM etymology_pages) AS ep,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(updated_at),'') FROM idea_projects) AS ip,
        (SELECT COUNT(*) || ':' || IFNULL(MAX(updated_at),'') FROM idea_notes) AS inn,
        (SELECT COUNT(*) || ':' || IFNULL(SUM(length(summary)),0) FROM idea_sources) AS isrc,
        (SELECT COUNT(*) FROM idea_insights) AS iin
    ''')).first;
    return [version, _fullHistory(), ...row.values].join('|');
  }

  Future<String> _export(String dir, String name) async {
    Directory(dir).createSync(recursive: true);
    final path = p.join(dir, name);
    final fp = await _fingerprint();
    final fpKey = 'exchange_fp|$path';
    if (File(path).existsSync() && await _dbs.getMeta(fpKey) == fp) {
      return path; // nothing new since the last export
    }
    final bundle = await buildBundle();
    final text = await Isolate.run(() => jsonEncode(bundle));
    // A unique temp name: a second export can never trip over this one.
    final tmp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(text, flush: true);
    try {
      await tmp.rename(path);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    await _dbs.setMeta(fpKey, fp);
    return path;
  }

  // ─────────────────────────────────────────── import

  Future<ExchangeReport> importFile(String path) =>
      _serial(() async {
        final r = await _importBundle(await _readBundle(File(path)));
        r.files = 1;
        return r;
      });

  Future<ExchangeReport> importBundle(Map<String, dynamic> b) =>
      _serial(() => _importBundle(b));

  static Future<Map<String, dynamic>> _readBundle(File f,
      {List<int>? bytes}) async {
    final data = bytes ?? await _readLimited(f);
    final decoded = await Isolate.run(() => jsonDecode(utf8.decode(data)));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Это не файл обмена LinguaTrace');
    }
    return decoded;
  }

  static Future<List<int>> _readLimited(File f) async {
    final size = await f.length();
    if (size > maxFileBytes) {
      throw FormatException('Файл слишком большой для файла обмена '
          '(${size ~/ (1024 * 1024)} МБ)');
    }
    return f.readAsBytes();
  }

  Future<ExchangeReport> _importBundle(Map<String, dynamic> b) async {
    if (b['format'] != format) {
      throw const FormatException('Это не файл обмена LinguaTrace');
    }
    if ((b['version'] as num? ?? 0) > version) {
      throw const FormatException(
          'Файл создан более новой версией приложения — обновите его');
    }
    final rep = ExchangeReport();
    await _db.transaction((txn) async {
      final m = _Merge(txn, rep);
      await m.tombstones(_list(b['tombstones']));
      final itemIds = await m.items(_list(b['learning_items']));
      final mistakeIds = await m.mistakes(_list(b['mistakes']));
      await m.translations(_list(b['translations']));
      await m.trainings(_list(b['trainings']), mistakeIds);
      await m.events(_list(b['item_events']), itemIds);
      final editionIds = await m.editions(_list(b['feed_editions']));
      await m.feed(_list(b['feed_items']), itemIds, editionIds);
      await m.etymology(_list(b['etymology_pages']));
      await m.ideas(b);
    });
    if (rep.translations > 0 || rep.deleted > 0) {
      await _dbs.backfillNormKeys();
      await _dbs.rebuildPatterns();
    }
    return rep;
  }

  static List<Map<String, dynamic>> _list(Object? v) => v is List
      ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
      : const [];

  // ─────────────────────────────────────────── sync server

  /// Something changed here (a dictation ended, notes were researched):
  /// the app syncs a few seconds later.
  static void requestSync() => _syncRequests.add(null);

  /// Why the last automatic sync with the server failed (shown in Settings;
  /// being offline on the street is normal and must not pop up).
  static String? lastServerError;
  static final _syncRequests = StreamController<void>.broadcast();
  static Stream<void> get syncRequests => _syncRequests.stream;

  /// "lt.example.com" → https://lt.example.com; a bare IP or localhost
  /// (a PC at home, Tailscale) gets http://.
  static String serverBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty || u.contains('://')) return u;
    final host = u.split(RegExp(r'[:/]')).first;
    final local = host == 'localhost' ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
        host.endsWith('.local') ||
        host.endsWith('.ts.net');
    return '${local ? 'http' : 'https'}://$u';
  }

  /// Through the sync server (server/ in the project — a store of these
  /// same files, one per device): import every other device's file that
  /// changed since it was last merged, then upload this device's file if
  /// anything here is new.
  Future<ExchangeReport> syncServer(String url, String key,
          {http.Client? client, String? device}) =>
      _serial(() async {
        final base = serverBase(url);
        if (base.isEmpty || key.trim().isEmpty) {
          throw const SyncServerException('Не указан адрес сервера или ключ');
        }
        final c = client ?? http.Client();
        final auth = {'Authorization': 'Bearer ${key.trim()}'};
        final rep = ExchangeReport();
        try {
          final listed = await _call(
              () => c.get(Uri.parse('$base/v1/bundles'), headers: auth));
          final devices = ((jsonDecode(utf8.decode(listed.bodyBytes))
                  as Map)['devices'] as List? ??
              const [])
              .whereType<Map>();
          final mine = device ?? deviceSlug;
          String? myEtag;
          for (final d in devices) {
            final name = '${d['device'] ?? ''}';
            final etag = '${d['etag'] ?? ''}';
            if (name == mine) {
              myEtag = etag;
              continue;
            }
            final seenKey = 'server_etag|$base|$name';
            if (name.isEmpty || await _dbs.getMeta(seenKey) == etag) continue;
            try {
              final r = await _call(() => c.get(
                  Uri.parse('$base/v1/bundles/${Uri.encodeComponent(name)}'),
                  headers: auth));
              if (r.bodyBytes.length > maxFileBytes) {
                throw const FormatException('файл обмена слишком большой');
              }
              final decoded = await _readBundle(File(''), bytes: r.bodyBytes);
              if (decoded['format'] != format) continue;
              final one = await _importBundle(decoded);
              one.files = 1;
              rep.add(one);
              await _dbs.setMeta(seenKey, etag);
            } on SyncServerException {
              rethrow;
            } catch (e) {
              rep.errors.add('$name: $e');
            }
          }

          // This device's file: only when something is new here, or the
          // server lost it.
          final fp = await _fingerprint();
          final fpKey = 'server_fp|$base';
          final sentKey = 'server_sent|$base';
          if (myEtag == null ||
              myEtag != await _dbs.getMeta(sentKey) ||
              await _dbs.getMeta(fpKey) != fp) {
            final bundle = await buildBundle();
            final body = await _gzipJson(bundle);
            final r = await _call(() => c.put(
                Uri.parse('$base/v1/bundles/${Uri.encodeComponent(mine)}'),
                headers: {
                  ...auth,
                  'Content-Type': 'application/json',
                  'Content-Encoding': 'gzip',
                },
                body: body));
            final etag = '${(jsonDecode(r.body) as Map)['etag'] ?? ''}';
            await _dbs.setMeta(sentKey, etag);
            await _dbs.setMeta(fpKey, fp);
            rep.uploaded = true;
          }
          await _dbs.setMeta('server_last_sync|$base',
              DateTime.now().toIso8601String());
          return rep;
        } finally {
          if (client == null) c.close();
        }
      });

  // Its own function: a closure sent to an isolate carries the variables of
  // the scope it was made in, and the HTTP client there can't be sent.
  static Future<List<int>> _gzipJson(Map<String, dynamic> bundle) =>
      Isolate.run(() => gzip.encode(utf8.encode(jsonEncode(bundle))));

  static Future<http.Response> _call(
      Future<http.Response> Function() request) async {
    final http.Response r;
    try {
      r = await request().timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw const SyncServerException('Сервер синхронизации не ответил за 90 с');
    } on HandshakeException {
      throw const SyncServerException(
          'Сервер синхронизации: ошибка HTTPS-сертификата');
    } on SocketException catch (e) {
      throw SyncServerException('Сервер синхронизации недоступен: ${e.message}');
    } on http.ClientException catch (e) {
      throw SyncServerException('Сервер синхронизации недоступен: ${e.message}');
    }
    switch (r.statusCode) {
      case 200:
      case 204:
        return r;
      case 401:
        throw const SyncServerException('Сервер синхронизации не принял ключ');
      case 413:
        throw const SyncServerException(
            'Файл обмена больше, чем разрешает сервер (--max-mb)');
      case 429:
        throw const SyncServerException(
            'Слишком много неверных ключей — сервер ждёт 10 минут');
      default:
        final text = r.body.length > 200 ? r.body.substring(0, 200) : r.body;
        throw SyncServerException(
            'Сервер синхронизации ответил ${r.statusCode}: $text');
    }
  }

  // ─────────────────────────────────────────── folder sync

  /// The PC side of "one place": import every other device's file in [dir]
  /// that changed since it was last merged, then write this device's file.
  Future<ExchangeReport> syncFolder(String dir) => _serial(() async {
        final rep = ExchangeReport();
        final d = Directory(dir)..createSync(recursive: true);
        final mine = fileNameFor(deviceSlug);
        for (final f in d.listSync().whereType<File>()) {
          final name = p.basename(f.path);
          if (!name.toLowerCase().endsWith('.json') || name == mine) continue;
          try {
            final bytes = await _readLimited(f);
            final hash = sha1.convert(bytes).toString();
            final seen = await _db.query('exchange_imports',
                where: 'device = ? AND hash = ?', whereArgs: [name, hash]);
            if (seen.isNotEmpty) continue;
            final Map<String, dynamic> decoded;
            try {
              decoded = await _readBundle(f, bytes: bytes);
            } on FormatException {
              continue; // some other JSON in the folder
            }
            if (decoded['format'] != format) continue;
            final r = await _importBundle(decoded);
            r.files = 1;
            rep.add(r);
            await _db.insert('exchange_imports', {'device': name, 'hash': hash},
                conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (e) {
            rep.errors.add('$name: $e');
          }
        }
        await _export(dir, mine);
        return rep;
      });
}

/// One import, inside one transaction: local rows are loaded once per table
/// (a query per remote row took minutes on a year of data), writes go in
/// batches, and remote rows are cut down to the columns this database has —
/// a file from a newer or older version must not abort the whole merge.
class _Merge {
  _Merge(this.txn, this.rep);

  final Transaction txn;
  final ExchangeReport rep;
  final _cols = <String, Set<String>>{};
  final _dead = <String, Set<String>>{};

  static String _k(Object? key) => jsonEncode(key);

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static bool _later(Object? a, Object? b) =>
      (a?.toString() ?? '').compareTo(b?.toString() ?? '') > 0;

  Future<Map<String, Object?>> _fit(
      String table, Map<String, Object?> row) async {
    final cols = _cols[table] ??= {
      for (final c in await txn.rawQuery('PRAGMA table_info($table)'))
        c['name'] as String,
    };
    return {
      for (final e in row.entries)
        if (e.key != 'id' && cols.contains(e.key)) e.key: e.value,
    };
  }

  bool _buried(String table, List<Object?> natural) =>
      _dead[table]?.contains(DatabaseService.rowKey(natural)) ?? false;

  /// Remote deletions first: delete the rows they name here, and remember
  /// all tombstones so the merges below skip those rows.
  Future<void> tombstones(List<Map<String, dynamic>> rows) async {
    final have = <String>{};
    for (final r in await txn.query('tombstones')) {
      final tbl = r['tbl'] as String, key = r['key'] as String;
      have.add('$tbl|$key');
      (_dead[tbl] ??= {}).add(key);
    }
    final fresh = <String, Set<String>>{};
    final batch = txn.batch();
    for (final r in rows) {
      final tbl = r['tbl'], key = r['key'];
      if (tbl is! String || key is! String || !have.add('$tbl|$key')) continue;
      batch.insert(
          'tombstones',
          {
            'tbl': tbl,
            'key': key,
            if (r['deleted_at'] != null) 'deleted_at': r['deleted_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      (fresh[tbl] ??= {}).add(key);
      (_dead[tbl] ??= {}).add(key);
    }
    if (fresh.isEmpty) return;
    await batch.commit(noResult: true);
    Future<void> purge(String table, List<String> cols,
        List<Object?> Function(Map<String, Object?>) keyOf) async {
      final keys = fresh[table];
      if (keys == null) return;
      final ids = [
        for (final r in await txn.query(table, columns: ['id', ...cols]))
          if (keys.contains(DatabaseService.rowKey(keyOf(r)))) r['id'] as int,
      ];
      for (var i = 0; i < ids.length; i += 500) {
        final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
        rep.deleted += await txn.delete(table,
            where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
            whereArgs: chunk);
      }
    }

    await purge('translations', ['source_text', 'timestamp', 'target_lang'],
        DatabaseService.translationKey);
    await purge('trainings', ['timestamp', 'content'], DatabaseService.trainingKey);
    await purge('mistakes', ['original', 'corrected', 'lang'],
        DatabaseService.mistakeKey);
    for (final t in const [
      'idea_insights', 'idea_sources', 'idea_notes', 'idea_projects',
    ]) {
      await purge(t, ['uuid'], (r) => [r['uuid']]);
    }
  }

  static const _counters = {
    'lookups': 'lookup',
    'exposures': 'exposure',
    'recall_ok': 'recall_ok',
    'recall_fail': 'recall_fail',
    'produced_ok': 'produced_ok',
    'produced_err': 'produced_error',
  };

  /// Remote learning items → local ids, keyed by the JSON of the natural key.
  Future<Map<String, int>> items(List<Map<String, dynamic>> rows) async {
    final ids = <String, int>{};
    final local = <String, Map<String, Object?>>{};
    final uuids = <Object?>{};
    for (final r in await txn.query('learning_items')) {
      local[_k([r['kind'], r['lang'], r['norm_key']])] = r;
      uuids.add(r['uuid']);
    }
    final batch = txn.batch();
    var updates = 0;
    for (final r in rows) {
      final key = _k([r['kind'], r['lang'], r['norm_key']]);
      final l = local[key];
      if (l == null) {
        final row = await _fit('learning_items', r);
        if (r['uuid'] == null || uuids.contains(r['uuid'])) {
          row['uuid'] = DatabaseService.newUuid();
        }
        uuids.add(row['uuid']);
        final id = await txn.insert('learning_items', row);
        ids[key] = id;
        local[key] = {...row, 'id': id};
        rep.items++;
        continue;
      }
      final upd = <String, Object?>{
        // Counters are recounted from the merged event log afterwards
        // (events); max() keeps increments that have no event.
        for (final c in _counters.keys)
          c: _int(l[c]) >= _int(r[c]) ? l[c] : r[c],
      };
      // Each clock decides only its own fields.
      if (_later(r['status_at'], l['status_at'])) {
        upd['status'] = r['status'];
        upd['status_at'] = r['status_at'];
      }
      if (_later(r['srs_at'], l['srs_at'])) {
        upd['stage'] = r['stage'];
        upd['next_due'] = r['next_due'];
        upd['srs_at'] = r['srs_at'];
      }
      if (_later(r['last_seen'], l['last_seen'])) upd['last_seen'] = r['last_seen'];
      for (final c in ['gloss', 'wrong_form', 'construction', 'concept_key', 'notes']) {
        if ((l[c] as String? ?? '').isEmpty && (r[c] as String? ?? '').isNotEmpty) {
          upd[c] = r[c];
        }
      }
      if (r['first_seen'] != null && _later(l['first_seen'], r['first_seen'])) {
        upd['first_seen'] = r['first_seen'];
      }
      final fitted = await _fit('learning_items', upd);
      if (fitted.entries.any((e) => l[e.key] != e.value)) {
        batch.update('learning_items', fitted,
            where: 'id = ?', whereArgs: [l['id']]);
        updates++;
      }
      ids[key] = l['id'] as int;
    }
    if (updates > 0) {
      await batch.commit(noResult: true);
      rep.items += updates;
    }
    return ids;
  }

  Future<Map<String, int>> mistakes(List<Map<String, dynamic>> rows) async {
    final ids = <String, int>{};
    final local = {
      for (final r in await txn.query('mistakes'))
        _k(DatabaseService.mistakeKey(r)): r,
    };
    final batch = txn.batch();
    var updates = 0;
    for (final r in rows) {
      final natural = DatabaseService.mistakeKey(r);
      final key = _k(natural);
      final l = local[key];
      if (l == null) {
        if (_buried('mistakes', natural)) continue;
        final row = await _fit('mistakes', r);
        final id = await txn.insert('mistakes', row);
        ids[key] = id;
        local[key] = {...row, 'id': id};
        rep.mistakes++;
        continue;
      }
      final upd = <String, Object?>{
        'seen_count': _int(l['seen_count']) > _int(r['seen_count'])
            ? l['seen_count']
            : r['seen_count'],
        // «Это не ошибка» on either device wins.
        'rejected': (_int(l['rejected']) == 1 || _int(r['rejected']) == 1) ? 1 : 0,
      };
      if (_int(r['practice_count']) > _int(l['practice_count']) ||
          (_int(r['practice_count']) == _int(l['practice_count']) &&
              _later(r['last_practiced'], l['last_practiced']))) {
        upd['practice_count'] = r['practice_count'];
        upd['last_practiced'] = r['last_practiced'];
        upd['next_due'] = r['next_due'];
      }
      for (final c in ['construction', 'backend', 'reason']) {
        if ((l[c] as String? ?? '').isEmpty && (r[c] as String? ?? '').isNotEmpty) {
          upd[c] = r[c];
        }
      }
      final fitted = await _fit('mistakes', upd);
      if (fitted.entries.any((e) => l[e.key] != e.value)) {
        batch.update('mistakes', fitted, where: 'id = ?', whereArgs: [l['id']]);
        updates++;
      }
      ids[key] = l['id'] as int;
    }
    if (updates > 0) {
      await batch.commit(noResult: true);
      rep.mistakes += updates;
    }
    return ids;
  }

  Future<void> translations(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final have = {
      for (final r in await txn.query('translations',
          columns: ['source_text', 'timestamp', 'target_lang']))
        _k(DatabaseService.translationKey(r)),
    };
    final batch = txn.batch();
    var added = 0;
    for (final r in rows) {
      final natural = DatabaseService.translationKey(r);
      if (!have.add(_k(natural)) || _buried('translations', natural)) continue;
      batch.insert('translations', await _fit('translations', r));
      added++;
    }
    if (added > 0) {
      await batch.commit(noResult: true);
      rep.translations += added;
    }
  }

  Future<void> trainings(
      List<Map<String, dynamic>> rows, Map<String, int> mistakeIds) async {
    final local = {
      for (final r in await txn.query('trainings',
          columns: ['id', 'timestamp', 'content', 'done_at']))
        _k(DatabaseService.trainingKey(r)): r,
    };
    for (final r in rows) {
      final natural = DatabaseService.trainingKey(r);
      final l = local[_k(natural)];
      final ids = (r['mistakes'] is List ? r['mistakes'] as List : const [])
          .map((k) => mistakeIds[_k(k)])
          .whereType<int>()
          .join(',');
      if (l == null) {
        if (_buried('trainings', natural)) continue;
        final row = {
          'timestamp': r['timestamp'],
          'lang': r['lang'] ?? '',
          'content': r['content'] ?? '',
          'mistake_ids': ids,
          'done_at': r['done_at'],
        };
        final id = await txn.insert('trainings', row);
        local[_k(natural)] = {...row, 'id': id};
        rep.trainings++;
      } else if (l['done_at'] == null && r['done_at'] != null) {
        await txn.update('trainings', {'done_at': r['done_at']},
            where: 'id = ?', whereArgs: [l['id']]);
        rep.trainings++;
      }
    }
  }

  Future<void> events(
      List<Map<String, dynamic>> rows, Map<String, int> itemIds) async {
    if (rows.isEmpty) return;
    final have = {
      for (final r in await txn.query('item_events', columns: ['uuid'])) r['uuid'],
    };
    final batch = txn.batch();
    var added = 0;
    for (final r in rows) {
      final uuid = r['uuid'];
      if (uuid == null || !have.add(uuid)) continue;
      final row = await _fit('item_events', r);
      row['item_id'] = r['item'] == null ? null : itemIds[_k(r['item'])];
      batch.insert('item_events', row);
      added++;
    }
    if (added == 0) return;
    await batch.commit(noResult: true);
    rep.events += added;
    // Counters = events seen on either device (max() lost the increments
    // made on both sides).
    await txn.execute('UPDATE learning_items SET ${[
      for (final e in _counters.entries)
        '${e.key} = MAX(${e.key}, (SELECT COUNT(*) FROM item_events e '
            "WHERE e.item_id = learning_items.id AND e.type = '${e.value}'))",
    ].join(', ')}');
  }

  Future<Map<String, int>> editions(List<Map<String, dynamic>> rows) async {
    final ids = {
      for (final r in await txn.query('feed_editions', columns: ['id', 'uuid']))
        if (r['uuid'] != null) r['uuid'] as String: r['id'] as int,
    };
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null || ids.containsKey(uuid)) continue;
      ids[uuid] = await txn.insert('feed_editions', await _fit('feed_editions', r));
    }
    return ids;
  }

  Future<void> feed(List<Map<String, dynamic>> rows, Map<String, int> itemIds,
      Map<String, int> editionIds) async {
    if (rows.isEmpty) return;
    final localItems = {
      for (final r in await txn.query('feed_items',
          columns: ['id', 'uuid', 'read_at']))
        if (r['uuid'] != null) r['uuid'] as String: r,
    };
    final localTasks = {
      for (final r in await txn.query('feed_tasks'))
        if (r['uuid'] != null) r['uuid'] as String: r,
    };
    final batch = txn.batch();
    var writes = 0;
    for (final r in rows) {
      final uuid = r['uuid'] as String?;
      if (uuid == null) continue;
      final local = localItems[uuid];
      int feedId;
      if (local == null) {
        final row = await _fit('feed_items', r);
        row['edition_id'] = editionIds[r['edition']] ?? 0;
        feedId = await txn.insert('feed_items', row);
        rep.feedItems++;
        for (final t in ExchangeService._list(r['targets'])) {
          final itemId = itemIds[_k(t['item'])];
          if (itemId == null) continue;
          batch.insert(
              'feed_item_targets',
              {
                'feed_item_id': feedId,
                'item_id': itemId,
                'start_pos': t['start_pos'],
                'end_pos': t['end_pos'],
                'form_used': t['form_used'],
                'highlight': t['highlight'] ?? 1,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
          writes++;
        }
      } else {
        feedId = local['id'] as int;
        // Read on either device counts as read.
        if (local['read_at'] == null && r['read_at'] != null) {
          batch.update('feed_items', {'read_at': r['read_at']},
              where: 'id = ?', whereArgs: [feedId]);
          writes++;
        }
      }
      for (final t in ExchangeService._list(r['tasks'])) {
        final tuuid = t['uuid'] as String?;
        if (tuuid == null) continue;
        final l = localTasks[tuuid];
        if (l == null) {
          final row = await _fit('feed_tasks', t);
          row['feed_item_id'] = feedId;
          row['item_id'] = t['item'] == null ? null : itemIds[_k(t['item'])];
          batch.insert('feed_tasks', row);
          writes++;
          continue;
        }
        if (_takeAnswer(l, t)) {
          batch.update(
              'feed_tasks',
              {
                'user_answer': t['user_answer'],
                'result': t['result'],
                'done_at': t['done_at'],
              },
              where: 'id = ?',
              whereArgs: [l['id']]);
          writes++;
          rep.tasksUpdated++;
        }
      }
    }
    if (writes > 0) await batch.commit(noResult: true);
  }

  /// «Идеи» by uuid. A project or note edited later wins; a summary or a
  /// research result made on one device fills the other.
  Future<void> ideas(Map<String, dynamic> b) async {
    final projects = ExchangeService._list(b['idea_projects']);
    final notes = ExchangeService._list(b['idea_notes']);
    final sources = ExchangeService._list(b['idea_sources']);
    final insights = ExchangeService._list(b['idea_insights']);
    if (projects.isEmpty && notes.isEmpty && sources.isEmpty && insights.isEmpty) {
      return;
    }
    Future<Map<String, Map<String, Object?>>> byUuid(String t) async => {
          for (final r in await txn.query(t)) r['uuid'] as String: r,
        };
    bool buried(String t, Object? uuid) => _buried(t, [uuid]);

    final localProjects = await byUuid('idea_projects');
    final projectId = <String, int>{
      for (final e in localProjects.entries) e.key: e.value['id'] as int,
    };
    for (final r in projects) {
      final uuid = r['uuid'] as String?;
      if (uuid == null || buried('idea_projects', uuid)) continue;
      final l = localProjects[uuid];
      if (l == null) {
        projectId[uuid] = await txn.insert(
            'idea_projects', await _fit('idea_projects', r));
        rep.ideas++;
      } else if (_later(r['updated_at'], l['updated_at'])) {
        await txn.update(
            'idea_projects',
            await _fit('idea_projects', {
              'title': r['title'],
              'context': r['context'],
              'kind': r['kind'],
              'updated_at': r['updated_at'],
            }),
            where: 'id = ?',
            whereArgs: [l['id']]);
        rep.ideas++;
      }
    }

    final localNotes = await byUuid('idea_notes');
    final noteId = <String, int>{
      for (final e in localNotes.entries) e.key: e.value['id'] as int,
    };
    for (final r in notes) {
      final uuid = r['uuid'] as String?;
      final pid = projectId[r['project']];
      if (uuid == null || pid == null || buried('idea_notes', uuid)) continue;
      final l = localNotes[uuid];
      if (l == null) {
        final row = await _fit('idea_notes', r)..['project_id'] = pid;
        noteId[uuid] = await txn.insert('idea_notes', row);
        rep.ideas++;
      } else if (_later(r['updated_at'], l['updated_at'])) {
        await txn.update(
            'idea_notes',
            await _fit('idea_notes', {
              'text': r['text'],
              'clean_text': r['clean_text'],
              'status': r['status'],
              'error': r['error'],
              'updated_at': r['updated_at'],
            }),
            where: 'id = ?',
            whereArgs: [l['id']]);
        rep.ideas++;
      }
    }

    final localSources = await byUuid('idea_sources');
    for (final r in sources) {
      final uuid = r['uuid'] as String?;
      final pid = projectId[r['project']];
      if (uuid == null || pid == null || buried('idea_sources', uuid)) continue;
      final l = localSources[uuid];
      if (l == null) {
        final row = await _fit('idea_sources', r)..['project_id'] = pid;
        await txn.insert('idea_sources', row);
        rep.ideas++;
      } else if ((l['summary'] as String? ?? '').isEmpty &&
          (r['summary'] as String? ?? '').isNotEmpty) {
        await txn.update('idea_sources', {'summary': r['summary']},
            where: 'id = ?', whereArgs: [l['id']]);
        rep.ideas++;
      }
    }

    final localInsights = await byUuid('idea_insights');
    for (final r in insights) {
      final uuid = r['uuid'] as String?;
      final pid = projectId[r['project']];
      if (uuid == null ||
          pid == null ||
          localInsights.containsKey(uuid) ||
          buried('idea_insights', uuid)) {
        continue;
      }
      final row = await _fit('idea_insights', r)
        ..['project_id'] = pid
        ..['note_id'] = r['note'] == null ? null : noteId[r['note']];
      await txn.insert('idea_insights', row);
      rep.ideas++;
    }
  }

  /// A page per (lang, term): the newer one wins.
  Future<void> etymology(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final local = {
      for (final r in await txn.query('etymology_pages',
          columns: ['lang', 'norm_key', 'created_at']))
        '${r['lang']}|${r['norm_key']}': r['created_at'],
    };
    final batch = txn.batch();
    var n = 0;
    for (final r in rows) {
      final key = '${r['lang']}|${r['norm_key']}';
      if (r['lang'] == null || r['norm_key'] == null || r['json'] == null) {
        continue;
      }
      if (local.containsKey(key) && !_later(r['created_at'], local[key])) {
        continue;
      }
      batch.insert('etymology_pages', await _fit('etymology_pages', r),
          conflictAlgorithm: ConflictAlgorithm.replace);
      n++;
    }
    if (n > 0) await batch.commit(noResult: true);
  }

  /// Whose answer a task keeps. The same answer: a grade beats 'pending'
  /// (the PC checked the phone's text). Different answers: the later attempt
  /// wins — never a silent swap of an older answer for a newer one.
  static bool _takeAnswer(Map<String, Object?> l, Map<String, dynamic> r) {
    if (r['done_at'] == null) return false;
    final same = (l['user_answer'] ?? '') == (r['user_answer'] ?? '') &&
        l['result'] == r['result'] &&
        l['done_at'] == r['done_at'];
    if (same) return false;
    if (l['done_at'] == null) return true;
    if ((l['user_answer'] ?? '') == (r['user_answer'] ?? '')) {
      return l['result'] == 'pending' && r['result'] != 'pending';
    }
    return _later(r['done_at'], l['done_at']);
  }
}
