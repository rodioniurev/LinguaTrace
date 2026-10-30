/// LinguaTrace sync server: a small store of exchange files, one per device.
///
/// Every device (the phone, each PC) uploads its own exchange bundle and
/// downloads the others'; the app merges them exactly as it merges the
/// files of an exchange folder. The server never interprets the data beyond
/// checking that an upload is an exchange bundle, so it stays tiny, fast,
/// and can't break a merge.
///
///   GET    /v1/health            → "ok" (no key needed)
///   GET    /v1/bundles           → {"devices": [{device, etag, size, updated}]}
///   GET    /v1/bundles/<device>  → the bundle (gzip when accepted), ETag
///   PUT    /v1/bundles/<device>  → store it (JSON, gzip allowed) → {etag, size}
///   DELETE /v1/bundles/<device>  → forget a device
///
/// Everything but health needs "Authorization: Bearer <key>". Each key has
/// its own space on disk, so one server can serve several people. Once a
/// day the previous version of each device's bundle is kept as a backup.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class SyncServer {
  SyncServer({
    required this.dataDir,
    required Iterable<String> keys,
    this.maxBytes = 100 * 1024 * 1024,
    this.keepDays = 14,
    void Function(String line)? log,
  })  : _spaces = {for (final k in keys) _digest(k): _digest(k).substring(0, 16)},
        _log = log ?? ((_) {});

  /// Where the bundles live: <dataDir>/<space>/<device>.json.gz (+ .meta).
  final Directory dataDir;

  /// Largest bundle accepted, compressed and uncompressed.
  final int maxBytes;

  /// Daily backups kept per device.
  final int keepDays;

  final Map<String, String> _spaces; // sha256(key) → space directory name
  final void Function(String line) _log;
  final _failures = <String, (int, DateTime)>{}; // ip → (count, since)

  static final _deviceName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
  static final _bundleStart =
      RegExp(r'^\s*\{\s*"format"\s*:\s*"linguatrace-exchange"');

  static String _digest(String key) =>
      sha256.convert(utf8.encode(key.trim())).toString();

  /// A new random key: 32 bytes, URL-safe base64.
  static String newKey() {
    final r = Random.secure();
    final bytes = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<HttpServer> listen(
      {Object host = '0.0.0.0', int port = 8790, SecurityContext? tls}) async {
    final server = tls == null
        ? await HttpServer.bind(host, port)
        : await HttpServer.bindSecure(host, port, tls);
    server.idleTimeout = const Duration(seconds: 30);
    server.listen((req) => unawaited(handle(req)));
    return server;
  }

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    final sw = Stopwatch()..start();
    res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      await _route(req, res);
    } catch (e) {
      _log('error ${req.method} ${req.uri.path}: $e');
      try {
        await _text(res, 500, 'server error');
      } catch (_) {}
    }
    if (req.uri.path != '/v1/health') {
      _log('${req.method} ${req.uri.path} ${res.statusCode} '
          '${sw.elapsedMilliseconds} ms');
    }
  }

  Future<void> _route(HttpRequest req, HttpResponse res) async {
    final seg = req.uri.pathSegments;
    if (seg.length == 2 && seg[0] == 'v1' && seg[1] == 'health') {
      return _text(res, 200, 'ok');
    }
    if (seg.length < 2 || seg[0] != 'v1' || seg[1] != 'bundles' || seg.length > 3) {
      return _text(res, 404, 'not found');
    }
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    if (_blocked(ip)) return _text(res, 429, 'too many wrong keys, wait');
    final space = _spaceOf(req);
    if (space == null) {
      _failed(ip);
      // Slows down guessing without blocking other requests.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return _text(res, 401, 'wrong key');
    }
    if (seg.length == 2) {
      if (req.method != 'GET') return _text(res, 405, 'method not allowed');
      return _list(res, space);
    }
    final device = seg[2];
    if (!_deviceName.hasMatch(device)) {
      return _text(res, 400, 'bad device name');
    }
    switch (req.method) {
      case 'GET':
      case 'HEAD':
        return _get(req, res, space, device);
      case 'PUT':
        return _put(req, res, space, device);
      case 'DELETE':
        return _delete(res, space, device);
      default:
        return _text(res, 405, 'method not allowed');
    }
  }

  // ─────────────────────────────────────────── keys

  String? _spaceOf(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!h.startsWith('Bearer ')) return null;
    return _spaces[_digest(h.substring(7))];
  }

  bool _blocked(String ip) {
    final f = _failures[ip];
    if (f == null) return false;
    if (DateTime.now().difference(f.$2) > const Duration(minutes: 10)) {
      _failures.remove(ip);
      return false;
    }
    return f.$1 >= 20;
  }

  void _failed(String ip) {
    final f = _failures[ip];
    _failures[ip] = f == null ? (1, DateTime.now()) : (f.$1 + 1, f.$2);
    if (_failures.length > 10000) _failures.clear(); // never grows unbounded
    _log('wrong key from $ip');
  }

  // ─────────────────────────────────────────── bundles

  Directory _dir(String space) => Directory('${dataDir.path}/$space');
  File _bundle(String space, String device) =>
      File('${_dir(space).path}/$device.json.gz');
  File _meta(String space, String device) =>
      File('${_dir(space).path}/$device.meta');

  Future<Map<String, Object?>?> _readMeta(String space, String device) async {
    final f = _meta(space, device);
    if (!await f.exists()) return null;
    try {
      return (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _list(HttpResponse res, String space) async {
    final devices = <Map<String, Object?>>[];
    final d = _dir(space);
    if (await d.exists()) {
      await for (final e in d.list()) {
        if (e is! File || !e.path.endsWith('.meta')) continue;
        try {
          devices.add((jsonDecode(await e.readAsString()) as Map)
              .cast<String, Object?>());
        } catch (_) {}
      }
    }
    devices.sort((a, b) => '${a['device']}'.compareTo('${b['device']}'));
    return _json(res, 200, {'devices': devices});
  }

  Future<void> _get(
      HttpRequest req, HttpResponse res, String space, String device) async {
    final meta = await _readMeta(space, device);
    final f = _bundle(space, device);
    if (meta == null || !await f.exists()) {
      return _text(res, 404, 'no such device');
    }
    final etag = '"${meta['etag']}"';
    res.headers.set(HttpHeaders.etagHeader, etag);
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      res.statusCode = HttpStatus.notModified;
      return res.close();
    }
    res.headers.contentType = ContentType.json;
    final gz = (req.headers.value(HttpHeaders.acceptEncodingHeader) ?? '')
        .contains('gzip');
    if (gz) {
      res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      res.contentLength = await f.length();
    }
    if (req.method == 'HEAD') return res.close();
    await res.addStream(gz ? f.openRead() : f.openRead().transform(gzip.decoder));
    return res.close();
  }

  Future<void> _put(
      HttpRequest req, HttpResponse res, String space, String device) async {
    if (req.contentLength > maxBytes) {
      await req.drain<void>();
      return _text(res, 413, 'too large');
    }
    final zipped =
        (req.headers.value(HttpHeaders.contentEncodingHeader) ?? '') == 'gzip';
    final body = await _readCapped(req);
    if (body == null) return _text(res, 413, 'too large');
    final Uint8List plain;
    try {
      plain = zipped ? await _gunzipCapped(body) : body;
    } on _TooLarge {
      return _text(res, 413, 'too large');
    } catch (_) {
      return _text(res, 400, 'bad gzip');
    }
    if (!_isBundle(plain)) {
      return _text(res, 400, 'not a LinguaTrace exchange file');
    }
    final etag = sha256.convert(plain).toString().substring(0, 32);
    final updated = DateTime.now().toUtc().toIso8601String();
    await _store(space, device, zipped ? body : gzip.encode(plain), {
      'device': device,
      'etag': etag,
      'size': plain.length,
      'updated': updated,
    });
    return _json(res, 200, {'etag': etag, 'size': plain.length, 'updated': updated});
  }

  Future<void> _delete(HttpResponse res, String space, String device) async {
    for (final f in [_bundle(space, device), _meta(space, device)]) {
      if (await f.exists()) await f.delete();
    }
    res.statusCode = HttpStatus.noContent;
    return res.close();
  }

  /// The previous bundle becomes today's backup (if there is none yet), then
  /// the new one replaces it atomically; the meta file goes last.
  Future<void> _store(String space, String device, List<int> gz,
      Map<String, Object?> meta) async {
    final dir = await _dir(space).create(recursive: true);
    final f = _bundle(space, device);
    if (keepDays > 0 && await f.exists()) {
      final h = await Directory('${dir.path}/history/$device').create(recursive: true);
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final backup = File('${h.path}/$day.json.gz');
      if (!await backup.exists()) await f.copy(backup.path);
      final old = (await h.list().toList()).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final e in old.take(max(0, old.length - keepDays))) {
        await e.delete();
      }
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = File('${f.path}.$stamp.tmp');
    await tmp.writeAsBytes(gz, flush: true);
    await tmp.rename(f.path);
    final m = _meta(space, device);
    final mtmp = File('${m.path}.$stamp.tmp');
    await mtmp.writeAsString(jsonEncode(meta), flush: true);
    await mtmp.rename(m.path);
  }

  bool _isBundle(Uint8List plain) {
    final head = utf8.decode(
        plain.sublist(0, min(plain.length, 256)), allowMalformed: true);
    if (_bundleStart.hasMatch(head)) return true;
    // Another key order: parse it once (rare, and still a small file).
    try {
      final d = jsonDecode(utf8.decode(plain));
      return d is Map && d['format'] == 'linguatrace-exchange';
    } catch (_) {
      return false;
    }
  }

  /// The body, or null when it is larger than [maxBytes] — read to the end
  /// anyway (the key is already checked), so the client gets the 413
  /// instead of a broken connection.
  Future<Uint8List?> _readCapped(Stream<List<int>> body) async {
    final b = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in body) {
      if (tooLarge) continue;
      b.add(chunk);
      if (b.length > maxBytes) {
        tooLarge = true;
        b.clear();
      }
    }
    return tooLarge ? null : b.takeBytes();
  }

  /// Unpacks without trusting the sender: a gzip bomb stops at [maxBytes].
  Future<Uint8List> _gunzipCapped(Uint8List data) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk
        in Stream<List<int>>.value(data).transform(gzip.decoder)) {
      b.add(chunk);
      if (b.length > maxBytes) throw const _TooLarge();
    }
    return b.takeBytes();
  }

  Future<void> _text(HttpResponse res, int status, String text) {
    res.statusCode = status;
    res.headers.contentType = ContentType.text;
    res.write(text);
    return res.close();
  }

  Future<void> _json(HttpResponse res, int status, Object body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    return res.close();
  }
}

class _TooLarge implements Exception {
  const _TooLarge();
}
