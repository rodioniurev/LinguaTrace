/// LIVE end-to-end check of the news feed: real RSS, real Claude through the
/// local Claude Code CLI (subscription). Skipped unless LT_LIVE=1.
///
///   LT_LIVE=1 LT_DB=<copy of a linguatrace.db> flutter test test/live_feed_test.dart
///
/// Never points at the user's real data folder: it works on a temp copy.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/claude_code_client.dart';
import 'package:lingua_trace/services/feed_composer.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:lingua_trace/services/news_source_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final live = Platform.environment['LT_LIVE'] == '1';

  test('live edition: real news + Claude subscription', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('lt_live');
    final src = Platform.environment['LT_DB'];
    final dbPath = '${tmp.path}/live.db';
    if (src != null && File(src).existsSync()) File(src).copySync(dbPath);

    final db = DatabaseService();
    await db.init(path: dbPath);
    final cfg = ConfigService()
      ..aiProvider = 'claude_code'
      ..anthropicModel = Platform.environment['LT_MODEL'] ?? 'claude-opus-5';
    final cc = ClaudeCodeClient(
        pathOverride: () => '', workDir: () => '${tmp.path}/cwd');
    final composer = FeedComposer(
        LlmRouter(cfg, ai: AiClient(cfg, claudeCode: cc, usageLog: db)), db);

    final sources = NewsSourceService.parseSources(
        File('assets/feed/sources.json').readAsStringSync());
    final sw = Stopwatch()..start();
    final r = await composer.buildEdition(
      lang: 'es',
      count: int.tryParse(Platform.environment['LT_COUNT'] ?? '') ?? 3,
      sources: sources,
      onProgress: (p) => print('[${sw.elapsed.inSeconds}s] ${p.stage}'),
    );
    print('created=${r.created} failed=${r.failed} errors=${r.errors}');
    for (final it in await db.getFeedItems()) {
      print('\n=== ${it.headline}  (${it.outlet}, ${it.backend})');
      print(it.body);
      for (final t in it.targets) {
        print('  • [${t.kind}] «${t.form}» ← ${t.canonical}'
            '${t.wrongForm.isNotEmpty ? ' (было: ${t.wrongForm})' : ''} — ${t.gloss}');
      }
      for (final t in it.tasks) {
        print('  ? ${t.kind}: ${t.promptRu} | ${t.text} | ${t.options} → ${t.answer}');
      }
    }
    final usage = await db.aiUsageThisMonth();
    print('\nAI calls: ${usage.$1} (ok ${usage.$2}); wall ${sw.elapsed.inSeconds}s');
    expect(r.created, greaterThan(0));
    await db.close();
  }, skip: live ? false : 'set LT_LIVE=1 to run against real RSS + Claude',
      timeout: const Timeout(Duration(minutes: 20)));
}
