import 'dart:convert';
import 'dart:io';

import 'package:linguatrace_sync/sync_server.dart';
import 'package:test/test.dart';

const _key = 'test-key-1';
const _other = 'test-key-2';

String _bundle(String device, [int n = 1]) => jsonEncode({
      'format': 'linguatrace-exchange',
      'version': 2,
      'device': device,
      'translations': [
        for (var i = 0; i < n; i++)
          {'source_text': 'casa $i', 'translated_text': 'дом $i'}
      ],
    });

void main() {
  late Directory tmp;
  late HttpServer http;
  late HttpClient client;
  late Uri base;

  Future<HttpServer> start({int maxBytes = 1024 * 1024}) async {
    final s = SyncServer(
        dataDir: Directory('${tmp.path}/data'),
        keys: const [_key, _other],
        maxBytes: maxBytes);
    return s.listen(host: InternetAddress.loopbackIPv4, port: 0);
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lt_sync');
    http = await start();
    base = Uri.parse('http://127.0.0.1:${http.port}');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await http.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  Future<(int, String, HttpHeaders)> call(String method, String path,
      {String? key = _key,
      List<int>? body,
      bool gzipBody = false,
      Map<String, String> headers = const {}}) async {
    final req = await client.openUrl(method, base.resolve(path));
    if (key != null) req.headers.set('Authorization', 'Bearer $key');
    headers.forEach(req.headers.set);
    if (body != null) {
      if (gzipBody) req.headers.set('Content-Encoding', 'gzip');
      req.add(gzipBody ? gzip.encode(body) : body);
    }
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (res.statusCode, text, res.headers);
  }

  test('health needs no key; everything else does', () async {
    expect((await call('GET', '/v1/health', key: null)).$1, 200);
    expect((await call('GET', '/v1/bundles', key: null)).$1, 401);
    expect((await call('GET', '/v1/bundles', key: 'guess')).$1, 401);
    final (status, text, _) = await call('GET', '/v1/bundles');
    expect(status, 200);
    expect(jsonDecode(text), {'devices': []});
  });

  test('a device uploads (gzip), another lists and downloads it', () async {
    final (put, putText, _) = await call('PUT', '/v1/bundles/android',
        body: utf8.encode(_bundle('android', 3)), gzipBody: true);
    expect(put, 200, reason: putText);
    final etag = (jsonDecode(putText) as Map)['etag'];

    final list = jsonDecode((await call('GET', '/v1/bundles')).$2) as Map;
    final d = (list['devices'] as List).single as Map;
    expect(d['device'], 'android');
    expect(d['etag'], etag);

    // HttpClient asks for gzip and unpacks it.
    final (get, body, headers) = await call('GET', '/v1/bundles/android');
    expect(get, 200);
    expect(jsonDecode(body)['translations'], hasLength(3));
    expect(headers.value('etag'), '"$etag"');

    final (same, _, _) = await call('GET', '/v1/bundles/android',
        headers: {'If-None-Match': '"$etag"'});
    expect(same, 304, reason: 'nothing new: nothing sent');
  });

  test('plain JSON uploads work too; the same content keeps its etag', () async {
    final a = jsonDecode((await call('PUT', '/v1/bundles/windows-pc',
        body: utf8.encode(_bundle('pc')))).$2)['etag'];
    final b = jsonDecode((await call('PUT', '/v1/bundles/windows-pc',
        body: utf8.encode(_bundle('pc')), gzipBody: true)).$2)['etag'];
    expect(a, b);
  });

  test('only exchange files, sane names, limited size', () async {
    expect((await call('PUT', '/v1/bundles/android',
            body: utf8.encode('{"hello": 1}')))
        .$1, 400);
    expect((await call('PUT', '/v1/bundles/..%2Fetc',
            body: utf8.encode(_bundle('x'))))
        .$1, anyOf(400, 404));
    expect((await call('PUT', '/v1/bundles/android',
            body: [1, 2, 3], gzipBody: false, headers: {'Content-Encoding': 'gzip'}))
        .$1, 400);
    await http.close(force: true);
    http = await start(maxBytes: 64 * 1024);
    base = Uri.parse('http://127.0.0.1:${http.port}');
    // Too large as sent: a clear 413, not a dropped connection.
    final big = utf8.encode(_bundle('x', 5000));
    expect(big.length, greaterThan(64 * 1024));
    expect((await call('PUT', '/v1/bundles/android', body: big)).$1, 413);
    // A gzip bomb: tiny on the wire, huge unpacked.
    final bomb = utf8.encode(jsonEncode({
      'format': 'linguatrace-exchange',
      'pad': 'a' * (2 * 1024 * 1024),
    }));
    expect(gzip.encode(bomb).length, lessThan(64 * 1024));
    expect((await call('PUT', '/v1/bundles/android', body: bomb, gzipBody: true)).$1,
        413);
  });

  test('each key has its own space', () async {
    await call('PUT', '/v1/bundles/android', body: utf8.encode(_bundle('a')));
    final mine = jsonDecode((await call('GET', '/v1/bundles')).$2) as Map;
    final theirs =
        jsonDecode((await call('GET', '/v1/bundles', key: _other)).$2) as Map;
    expect(mine['devices'], hasLength(1));
    expect(theirs['devices'], isEmpty);
  });

  test('the previous version is kept as the day\'s backup; delete forgets', () async {
    await call('PUT', '/v1/bundles/android', body: utf8.encode(_bundle('a', 1)));
    await call('PUT', '/v1/bundles/android', body: utf8.encode(_bundle('a', 2)));
    final history = tmp
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('history'))
        .toList();
    expect(history, hasLength(1));
    expect((await call('DELETE', '/v1/bundles/android')).$1, 204);
    expect((await call('GET', '/v1/bundles/android')).$1, 404);
  });

  test('wrong keys from one address get blocked for a while', () async {
    for (var i = 0; i < 20; i++) {
      await call('GET', '/v1/bundles', key: 'guess-$i');
    }
    expect((await call('GET', '/v1/bundles')).$1, 429,
        reason: 'even the right key waits: the address is blocked');
  });
}
