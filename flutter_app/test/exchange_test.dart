/// Exchange files: an edition written on the PC travels to the phone, the
/// phone's answers and decisions travel back, and merging is idempotent.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/models/mistake.dart';
import 'package:lingua_trace/models/translation_entry.dart';
import 'package:lingua_trace/services/exchange_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late DatabaseService pc;
  late DatabaseService phone;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lt_exchange');
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

  /// The PC writes an edition with one item and two tasks.
  Future<(int, int)> seedPc() async {
    await pc.addTranslation(const TranslationEntry(
        sourceText: 'любой ценой',
        translatedText: 'a toda costa',
        sourceLang: 'ru',
        targetLang: 'es',
        translator: 'google'));
    final mid = await pc.addMistake(const Mistake(
        original: 'no me atrevo molestar',
        corrected: 'no me atrevo a molestar',
        lang: 'es',
        construction: 'es.regimen'));
    final item = await pc.findItem('mistake', 'es', 'no me atrevo a molestar');
    final ed = await pc.createEdition('es', 1);
    await pc.saveFeedItem(
      const FeedItem(
          editionId: 0,
          lang: 'es',
          headline: 'Titular',
          body: 'Los empresarios no se atrevieron a rechazar el acuerdo.',
          outlet: 'El País'),
      [
        FeedItemTarget(
            feedItemId: 0,
            itemId: item!.id!,
            start: 18,
            end: 45,
            form: 'no se atrevieron a rechazar'),
      ],
      [
        FeedTask(
            feedItemId: 0,
            itemId: item.id,
            kind: 'choice',
            text: 'no se atrevieron ____ rechazar',
            options: const ['a', '—'],
            answer: 'a'),
        const FeedTask(feedItemId: 0, kind: 'retell', promptRu: 'Перескажите'),
      ],
    );
    // saveFeedItem stored edition 0; point it at the real edition id.
    await pc.sqlite.update('feed_items', {'edition_id': ed});
    return (mid, item.id!);
  }

  test('PC → phone: the edition, targets, tasks and notebook arrive', () async {
    await seedPc();
    final r = await ExchangeService(phone)
        .importBundle(await ExchangeService(pc).buildBundle());
    expect(r.feedItems, 1);
    expect(r.translations, 1);
    expect(r.mistakes, 1);

    final items = await phone.getFeedItems();
    expect(items.single.headline, 'Titular');
    expect(items.single.targets.single.form, 'no se atrevieron a rechazar');
    expect(items.single.targets.single.kind, 'mistake',
        reason: 'the target points at the merged learning item');
    expect(items.single.tasks.map((t) => t.kind), ['choice', 'retell']);
  });

  test('phone → PC: answers, «не ошибка» and pending retells come back',
      () async {
    final (_, _) = await seedPc();
    await ExchangeService(phone)
        .importBundle(await ExchangeService(pc).buildBundle());

    // On the phone: answer the choice, write a retell with no AI (pending),
    // reject the mistake.
    final pItem = (await phone.getFeedItems()).single;
    final choice = pItem.tasks.firstWhere((t) => t.kind == 'choice');
    final retell = pItem.tasks.firstWhere((t) => t.kind == 'retell');
    await phone.saveTaskResult(choice.id!, 'a', 'ok');
    await phone.recordRecall(choice.itemId!, true);
    await phone.saveTaskResult(retell.id!, 'Los empresarios no se atrevieron.', 'pending');
    final pm = (await phone.getMistakes()).single;
    await phone.rejectMistake(pm.id!);
    await phone.markFeedItemRead(pItem.id!);

    final back = await ExchangeService(pc)
        .importBundle(await ExchangeService(phone).buildBundle());
    expect(back.tasksUpdated, 2);

    final item = (await pc.getFeedItems()).single;
    expect(item.readAt, isNotEmpty);
    expect(item.tasks.firstWhere((t) => t.kind == 'choice').result, 'ok');
    expect(item.tasks.firstWhere((t) => t.kind == 'retell').result, 'pending');
    expect((await pc.pendingFeedTasks()).length, 1,
        reason: 'the PC grades it with Claude after the sync');
    expect(await pc.mistakeCount(), 0, reason: '«это не ошибка» is sticky');
    final li = (await pc.getItems(statuses: const ['learning', 'ignored', 'seen']))
        .firstWhere((i) => i.kind == 'mistake');
    expect(li.recallOk, 1, reason: 'counters take the maximum');
  });

  test('merging the same file twice changes nothing', () async {
    await seedPc();
    final bundle = await ExchangeService(pc).buildBundle();
    await ExchangeService(phone).importBundle(bundle);
    final again = await ExchangeService(phone).importBundle(bundle);
    expect(again.total, 0);
    expect((await phone.getFeedItems()).length, 1);
    expect((await phone.getHistory()).length, 1);
  });

  test('folder sync: imports the other device, writes its own file', () async {
    await seedPc();
    final dir = '${tmp.path}/exchange';
    // The phone drops its file into the shared folder.
    await ExchangeService(pc).exportTo(dir, fileName: 'linguatrace-android.json');
    final fresh = DatabaseService();
    await fresh.init(path: '${tmp.path}/fresh.db');
    final r = await ExchangeService(fresh).syncFolder(dir);
    expect(r.files, 1);
    expect((await fresh.getFeedItems()).length, 1);
    expect(File('$dir/${ExchangeService.fileNameFor(ExchangeService.deviceSlug)}')
        .existsSync(), isTrue);
    // Unchanged file → skipped on the next sync.
    final again = await ExchangeService(fresh).syncFolder(dir);
    expect(again.files, 0);
    await fresh.close();
  });

  test('a foreign or newer-format file is refused with a clear message',
      () async {
    await expectLater(
        ExchangeService(phone).importBundle({'format': 'something-else'}),
        throwsA(isA<FormatException>()));
    await expectLater(
        ExchangeService(phone)
            .importBundle({'format': ExchangeService.format, 'version': 99}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('обновите'))));
  });
}
