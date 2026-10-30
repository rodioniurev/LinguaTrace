/// The sync server end to end: the real server (../server) on this machine,
/// a PC and a phone with their own databases syncing through it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/database.dart';
import 'package:lingua_trace/models/translation_entry.dart';
import 'package:lingua_trace/services/exchange_service.dart';
import 'package:linguatrace_sync/sync_server.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late HttpServer server;
  late String url;
  late DatabaseService pc;
  late DatabaseService phone;
  const key = 'k-123';

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lt_srv');
    server = await SyncServer(dataDir: Directory('${tmp.path}/srv'), keys: [key])
        .listen(host: InternetAddress.loopbackIPv4, port: 0);
    url = 'http://127.0.0.1:${server.port}';
    pc = DatabaseService();
    await pc.init(path: '${tmp.path}/pc.db');
    phone = DatabaseService();
    await phone.init(path: '${tmp.path}/phone.db');
  });

  tearDown(() async {
    await pc.close();
    await phone.close();
    await server.close(force: true);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('the PC and the phone meet on the server', () async {
    await pc.addTranslation(const TranslationEntry(
        sourceText: 'aportar', translatedText: 'вносить', sourceLang: 'es',
        targetLang: 'ru', translator: 'google'));
    final p = await phone.addIdeaProject('Рюкзак');
    await phone.addIdeaNote(p, 'панели на клапане');

    final a = await ExchangeService(pc).syncServer(url, key, device: 'windows-pc');
    expect(a.uploaded, isTrue);

    final b = await ExchangeService(phone).syncServer(url, key, device: 'android');
    expect(b.translations, greaterThan(0), reason: 'the PC\'s lookup came down');
    expect(b.uploaded, isTrue);
    expect((await phone.getHistory()).map((t) => t.sourceText), contains('aportar'));

    final c = await ExchangeService(pc).syncServer(url, key, device: 'windows-pc');
    expect(c.ideas, greaterThan(0), reason: 'the phone\'s thought came up');
    expect((await pc.ideaProjects()).single.title, 'Рюкзак');

    // Nothing new on either side: nothing downloaded, nothing sent.
    await ExchangeService(phone).syncServer(url, key, device: 'android');
    final d = await ExchangeService(pc).syncServer(url, key, device: 'windows-pc');
    expect(d.total, 0);
    expect(d.uploaded, isFalse);
  });

  test('a wrong key and a dead address say so', () async {
    await expectLater(
        ExchangeService(pc).syncServer(url, 'wrong', device: 'windows-pc'),
        throwsA(isA<SyncServerException>()
            .having((e) => e.message, 'message', contains('ключ'))));
    await server.close(force: true);
    await expectLater(
        ExchangeService(pc).syncServer(url, key, device: 'windows-pc'),
        throwsA(isA<SyncServerException>()
            .having((e) => e.message, 'message', contains('недоступен'))));
  });

  test('addresses as people type them', () {
    expect(ExchangeService.serverBase('lt.example.com/'), 'https://lt.example.com');
    expect(ExchangeService.serverBase('192.168.1.5:8790'), 'http://192.168.1.5:8790');
    expect(ExchangeService.serverBase('pc.tail1234.ts.net:8790'),
        'http://pc.tail1234.ts.net:8790');
    expect(ExchangeService.serverBase('https://x.org:8443'), 'https://x.org:8443');
  });
}
