/// The feed's learner model (review 2026-09-26, P7–P9): the review ladder
/// moves only when an item is due, every kind of target reaches the plan,
/// a lone function-word fix becomes a usable item, and an edition never
/// offers one story to two items or two new things in one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:lingua_trace/models/news_article.dart';
import 'package:lingua_trace/services/ai_client.dart';
import 'package:lingua_trace/services/feed_composer.dart';
import 'package:lingua_trace/services/llm_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

NewsArticle _story(int i) => NewsArticle(
      id: i,
      url: 'https://example.com/$i',
      urlHash: 'h$i',
      sourceId: 's$i',
      outlet: 'Outlet $i',
      lang: 'es',
      variety: 'es-ES',
      title: 'Titular $i',
      lead: 'Entradilla $i',
      publishedAt: DateTime.now().toUtc(),
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService db;
  setUp(() async {
    db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  FeedComposer composer() {
    final cfg = ConfigService()..aiProvider = 'custom';
    return FeedComposer(LlmRouter(cfg, ai: AiClient(cfg)), db);
  }

  group('review ladder', () {
    test('four right answers in one sitting promote once', () async {
      final id = await db.upsertItem(
          kind: 'idiom', lang: 'es', text: 'dar luz verde', status: 'learning');
      for (var i = 0; i < 2; i++) {
        await db.recordRecall(id, true);
        await db.recordProduction(id, true);
      }
      final it = (await db.getItems()).single;
      expect(it.stage, 1, reason: 'not due again until tomorrow');
      expect(it.recallOk, 2, reason: 'the answers are still counted');
      expect(it.producedOk, 2);
    });

    test('a wrong answer demotes even before the item is due', () async {
      final id = await db.upsertItem(
          kind: 'idiom', lang: 'es', text: 'dar luz verde', status: 'learning');
      await db.recordRecall(id, true);
      await db.recordRecall(id, false);
      expect((await db.getItems()).single.stage, 0);
    });

    test('a due item is promoted again', () async {
      final id = await db.upsertItem(
          kind: 'idiom', lang: 'es', text: 'dar luz verde', status: 'learning');
      await db.recordRecall(id, true);
      await db.sqlite.update('learning_items', {'next_due': '2000-01-01 00:00:00'},
          where: 'id = ?', whereArgs: [id]);
      await db.recordRecall(id, true);
      expect((await db.getItems()).single.stage, 2);
    });
  });

  test('sixty mistakes do not crowd the idioms out of the plan', () async {
    for (var i = 0; i < 60; i++) {
      await db.addMistake(Mistake(
          original: 'palabra$i mal', corrected: 'palabra$i bien', lang: 'es'));
    }
    for (final t in ['echar leña al fuego', 'a toda costa', 'dar luz verde',
        'llevar a cabo', 'hacer frente a']) {
      await db.upsertItem(kind: 'idiom', lang: 'es', text: t, status: 'learning');
    }
    final c = await db.feedCandidates('es');
    expect(c.where((i) => i.kind == 'idiom'), hasLength(5));
    final slots = await composer().plan('es', [for (var i = 0; i < 12; i++) _story(i)], 4);
    expect(slots.expand((s) => s.targets).where((t) => t.kind == 'idiom'),
        isNotEmpty);
    expect(await db.seedsIntroducedToday('es'), 0,
        reason: 'five own idioms: no cold-start seeds');
  });

  group('mistake items', () {
    test('a lone function-word fix is widened from the sentence', () async {
      await db.addMistake(const Mistake(
          original: 'a',
          corrected: 'el',
          lang: 'es',
          context: 'Llegaré a 18 de agosto a Santander.'));
      final it = (await db.getItems()).single;
      expect((it.wrongForm, it.text), ('Llegaré a 18', 'Llegaré el 18'));
      expect(FeedComposer.usableMistake(it), isTrue);
    });

    test('«это не ошибка» finds the widened item', () async {
      final id = await db.addMistake(const Mistake(
          original: 'a',
          corrected: 'el',
          lang: 'es',
          context: 'Llegaré a 18 de agosto a Santander.'));
      await db.rejectMistake(id);
      expect(await db.getItems(), isEmpty);
    });
  });

  group('plan', () {
    test('no story is offered to two items of one edition', () async {
      await db.upsertItem(
          kind: 'idiom', lang: 'es', text: 'a toda costa', status: 'learning');
      final slots =
          await composer().plan('es', [for (var i = 0; i < 5; i++) _story(i)], 4);
      final all = [for (final s in slots) ...s.stories.map((a) => a.id)];
      expect(all.toSet(), hasLength(all.length), reason: '$all');
      expect(slots.every((s) => s.stories.isNotEmpty), isTrue);
    });

    test('fewer stories than items: fewer items', () async {
      final slots =
          await composer().plan('es', [for (var i = 0; i < 2; i++) _story(i)], 4);
      expect(slots, hasLength(2));
    });

    test('a new proverb never joins a new expression', () async {
      for (final t in ['echar leña al fuego', 'a toda costa', 'dar luz verde',
          'llevar a cabo']) {
        await db.upsertItem(
            kind: 'idiom', lang: 'es', text: t, status: 'learning');
      }
      await db.upsertItem(
          kind: 'proverb',
          lang: 'es',
          text: 'a quien madruga, Dios le ayuda',
          status: 'learning');
      final slots = await composer()
          .plan('es', [for (var i = 0; i < 12; i++) _story(i)], 4);
      final exposures = {
        for (final i in await db.getItems(statuses: ['learning', 'seen']))
          i.id: i.exposures,
      };
      for (final s in slots) {
        final fresh = s.targets.where((t) => exposures[t.itemId] == 0);
        expect(fresh.length, lessThanOrEqualTo(1),
            reason: 'at most one new target per item: '
                '${s.targets.map((t) => t.canonical)}');
      }
      // Once the expressions are familiar, the proverb does come.
      await db.sqlite.update('learning_items', {'exposures': 1},
          where: "kind = 'idiom'");
      final later = await composer()
          .plan('es', [for (var i = 0; i < 12; i++) _story(i)], 4);
      expect(later.expand((s) => s.targets).any((t) => t.kind == 'proverb'),
          isTrue);
    });

    test('a seed introduced today keeps its verb frame', () async {
      final slots = await composer()
          .plan('es', [for (var i = 0; i < 12; i++) _story(i)], 2);
      final seeds = slots.expand((s) => s.targets).toList();
      expect(seeds, isNotEmpty);
      // kSeedExpressionsEs carries frames like "dar luz verde (a algo)".
      expect(seeds.any((t) => t.canonical.contains('(')), isTrue,
          reason: seeds.map((t) => t.canonical).join(' | '));
    });
  });
}
