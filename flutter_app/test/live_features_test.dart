/// Real Claude (subscription, warm Claude Code) + real Wiktionary:
/// «Подбор слова» on the user's own example and an origin page.
/// Skipped unless LT_LIVE=1.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/claude_code_client.dart';
import 'package:lingua_trace/services/etymology_service.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:lingua_trace/services/word_choice_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final live = Platform.environment['LT_LIVE'] == '1';
  test('word choice + origin page, live', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('lt_live_feat');
    final cfg = ConfigService()
      ..aiProvider = 'claude_code'
      ..fastModel = 'claude-sonnet-5';
    final cc = ClaudeCodeClient(
        pathOverride: () => '', workDir: () => tmp.path, warm: () => true);
    final router = LlmRouter(cfg, ai: AiClient(cfg, claudeCode: cc));
    final db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);

    var sw = Stopwatch()..start();
    final c = await WordChoiceService(router).suggest(
        source: 'что я должен привнести в проект?',
        translation: 'qué yo debo llevar al proyecto?',
        focus: 'привнести',
        srcLang: 'ru',
        tgtLang: 'es');
    // ignore: avoid_print
    print('WORD CHOICE ${sw.elapsedMilliseconds} ms\n  ${c.meaningRu}\n  best: ${c.bestSentence}\n  issues: ${c.issuesRu}');
    for (final o in c.options) {
      // ignore: avoid_print
      print('  [${o.fit}] ${o.word} (${o.pattern}) — ${o.glossRu}; ${o.whyRu} => ${o.sentence}');
    }
    sw = Stopwatch()..start();
    final p = await EtymologyService(router, db).build('aportar', 'es');
    // ignore: avoid_print
    print('ORIGIN ${sw.elapsedMilliseconds} ms  sources=${p.sources} certainty=${p.certainty}\n  ${p.summaryRu}\n  chain: ${p.chain.map((s) => '${s.form} (${s.langRu}) «${s.meaningRu}»').join(' → ')}\n  why: ${p.whyRu}\n  relatives: ${p.relatives.map((r) => '${r.lang}:${r.word}').join(', ')}\n  mnemonic: ${p.mnemonicRu}');
    expect(c.options.any((o) => o.word.toLowerCase().contains('aportar')), isTrue);
    expect(p.chain, isNotEmpty);
    cc.shutdownWarm();
    await db.close();
  }, skip: live ? false : 'LT_LIVE=1 to run against the real CLI',
      timeout: const Timeout(Duration(minutes: 6)));
}
