/// Grading feed tasks: a tap is graded with the validator's option
/// predicate, an accent mistake is not "right" without its accent, and a
/// checker that fails keeps the answer as pending instead of losing it
/// (review 2026-09-26: P4, P6; Android readiness #1).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/correction_service.dart';
import 'package:lingua_trace/services/feed_task_grader.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService db;
  late int itemId;
  late FeedItem item;

  setUp(() async {
    db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    itemId = await db.upsertItem(
        kind: 'idiom', lang: 'es', text: 'dar luz verde', status: 'learning');
    final ed = await db.createEdition('es', 1);
    await db.saveFeedItem(
      FeedItem(editionId: ed, lang: 'es', headline: 'H', body: 'b'),
      const [],
      [
        FeedTask(
            feedItemId: 0,
            itemId: itemId,
            kind: 'choice',
            options: const ['a', 'de'],
            answer: 'a'),
        FeedTask(feedItemId: 0, itemId: itemId, kind: 'cloze', answer: 'está'),
        const FeedTask(feedItemId: 0, kind: 'retell'),
      ],
    );
    item = (await db.getFeedItems()).single;
  });
  tearDown(() => db.close());

  FeedTaskGrader grader(ConfigService cfg) => FeedTaskGrader(
      db, CorrectionService(LlmRouter(cfg, ai: AiClient(cfg))), cfg);

  FeedTask task(String kind) => item.tasks.firstWhere((t) => t.kind == kind);

  test('a tapped option differing only in case is right', () async {
    final g = grader(ConfigService()..aiProvider = 'custom');
    final (ok, _) = await g.gradeLocal(task('choice'), 'A');
    expect(ok, isTrue);
  });

  test('a missing accent: tolerated for an expression, not for a mistake',
      () async {
    final g = grader(ConfigService()..aiProvider = 'custom');
    var (ok, accents) = await g.gradeLocal(task('cloze'), 'esta');
    expect((ok, accents), (true, true));
    (ok, accents) =
        await g.gradeLocal(task('cloze'), 'esta', accentsMatter: true);
    expect(ok, isFalse);
  });

  test('a configured checker that fails keeps the answer as pending',
      () async {
    // A port nothing listens on: the checker is configured but fails.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final cfg = ConfigService()
      ..aiProvider = 'custom'
      ..customApiBaseUrl = 'http://127.0.0.1:$port/v1'
      ..customModel = 'gpt-4o-mini';
    final g = grader(cfg);
    expect(g.canCheckFreeText, isTrue);
    final r = await g.gradeFree(item, task('retell'), 'El Gobierno dio luz verde.');
    expect(r.result, 'pending');
    expect(r.error, isNotEmpty);
    final stored = (await db.getFeedItems()).single.tasks
        .firstWhere((t) => t.kind == 'retell');
    expect((stored.userAnswer, stored.result),
        ('El Gobierno dio luz verde.', 'pending'));
    expect(await db.pendingFeedTasks(), hasLength(1),
        reason: 'the PC grades it after the next exchange');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
