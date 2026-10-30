/// The «Лента» screen renders an edition (marked targets, margin glosses,
/// tasks) without layout errors, and a tapped choice is graded and stored.
/// A target's highlight and gloss wait for the attempt; an item counts as
/// read only when the feed tab is the visible one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/l10n/app_localizations.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:lingua_trace/providers/providers.dart';
import 'package:lingua_trace/screens/feed_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _body = 'Los empresarios no se atrevieron a rechazar el acuerdo, '
    'según informa El País.';

/// One edition with one item: a mistake target and a choice task on it.
Future<(DatabaseService, int)> _seed(WidgetTester tester) async {
  late DatabaseService db;
  late int itemId;
  const body = _body;
  await tester.runAsync(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = DatabaseService();
    await db.init(path: inMemoryDatabasePath);
    await db.addMistake(const Mistake(
        original: 'no me atrevo molestar',
        corrected: 'no me atrevo a molestar',
        lang: 'es',
        reason: 'После atreverse нужен предлог a.',
        construction: 'es.regimen'));
    itemId = (await db.getItems()).single.id!;
    final ed = await db.createEdition('es', 1);
    await db.saveFeedItem(
      FeedItem(
          editionId: ed,
          lang: 'es',
          headline: 'Sube el salario mínimo',
          body: body,
          outlet: 'El País',
          sourceUrl: 'https://elpais.com/x'),
      [
        FeedItemTarget(
            feedItemId: 0,
            itemId: itemId,
            start: 16,
            end: 43,
            form: 'no se atrevieron a rechazar'),
      ],
      [
        FeedTask(
            feedItemId: 0,
            itemId: itemId,
            kind: 'choice',
            promptRu: 'Выберите верный вариант',
            text: 'no se atrevieron ____ rechazar',
            options: const ['a', '—'],
            answer: 'a'),
      ],
    );
  });
  return (db, itemId);
}

Future<void> _settle(WidgetTester tester) async {
  // Let the database futures (real isolate I/O) complete.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }
}

Widget _app(DatabaseService db, Widget home) {
  // No AI configured: opening the feed must not try to build an edition.
  final cfg = ConfigService()
    ..aiProvider = 'custom'
    ..learningLang = 'es';
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      configProvider.overrideWith((ref) => cfg),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

void main() {
  testWidgets('feed card: text, markers, gloss, graded choice', (tester) async {
    final (db, _) = await _seed(tester);

    await tester.pumpWidget(_app(db, const FeedScreen()));
    await _settle(tester);

    expect(find.text('Sube el salario mínimo'), findsOneWidget);
    expect(find.textContaining('EL PAÍS'), findsOneWidget);
    expect(find.text('Выберите верный вариант'), findsOneWidget);
    // Before the attempt the target is plain text and its gloss waits: the
    // task must not be answered by copying the highlight next to it.
    expect(find.textContaining('Управление глагола', findRichText: true),
        findsNothing);
    expect(find.textContaining('появятся после ответа'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'a'));
    await _settle(tester);
    expect(find.text('Верно!'), findsOneWidget);
    // After it: the gloss names the construction the user got wrong.
    expect(find.textContaining('Управление глагола', findRichText: true),
        findsWidgets);
    expect(find.textContaining('появятся после ответа'), findsNothing);

    late FeedItem stored;
    late int recallOk;
    await tester.runAsync(() async {
      stored = (await db.getFeedItems()).single;
      recallOk = (await db.getItems()).single.recallOk;
    });
    expect(stored.tasks.single.result, 'ok');
    expect(recallOk, 1, reason: 'a graded answer moves the schedule');
    expect(stored.readAt, isNotEmpty, reason: 'rendering marks the item read');

    await tester.runAsync(() => db.close());
  });

  testWidgets('a hidden feed tab does not count as reading', (tester) async {
    final (db, _) = await _seed(tester);
    final tab = ValueNotifier<int>(1);
    await tester.pumpWidget(_app(
        db,
        ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (_, i, __) => IndexedStack(
            index: i,
            children: const [FeedScreen(), Text('Перевод')],
          ),
        )));
    await _settle(tester);

    Future<String> readAt() async {
      late String r;
      await tester.runAsync(() async {
        r = (await db.getFeedItems()).single.readAt;
      });
      return r;
    }

    expect(await readAt(), isEmpty,
        reason: 'the feed is laid out in the IndexedStack but not visible');
    tab.value = 0;
    await _settle(tester);
    expect(await readAt(), isNotEmpty, reason: 'now the reader sees it');

    await tester.runAsync(() => db.close());
  });
}
