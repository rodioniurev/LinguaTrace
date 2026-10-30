/// «Claude для телефона»: the PC answers AI requests from the phone with its
/// own Claude — Claude Code on the user's subscription — so the phone needs
/// no API key and nothing extra is paid. The phone and the PC must see each
/// other: the same Wi-Fi, or a private VPN such as Tailscale.
///
/// Every request carries the pairing code shown in the PC's Settings; wrong
/// codes are throttled. Only completions are served — no files, no history.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import 'ai_types.dart';

/// One completion asked for by the phone.
class RelayRequest {
  final String system;
  final String user;
  final int maxTokens;
  final String effort;
  final Map<String, dynamic>? jsonSchema;
  final String feature;
  final Duration timeout;
  final String tier; // fast | main
  final bool web; // let the PC's Claude search the web

  const RelayRequest({
    required this.system,
    required this.user,
    this.maxTokens = 8000,
    this.effort = 'medium',
    this.jsonSchema,
    this.feature = '',
    this.timeout = const Duration(minutes: 5),
    this.tier = 'main',
    this.web = false,
  });

  Map<String, dynamic> toJson() => {
        'system': system,
        'user': user,
        'max_tokens': maxTokens,
        'effort': effort,
        if (jsonSchema != null) 'json_schema': jsonSchema,
        'feature': feature,
        'timeout_s': timeout.inSeconds,
        'tier': tier,
        'web': web,
      };

  static RelayRequest fromJson(Map<String, dynamic> j) => RelayRequest(
        system: (j['system'] ?? '').toString(),
        user: (j['user'] ?? '').toString(),
        maxTokens: (j['max_tokens'] as num?)?.toInt().clamp(256, 32000) ?? 8000,
        effort: const {'low', 'medium', 'high'}.contains(j['effort'])
            ? j['effort'] as String
            : 'medium',
        jsonSchema: j['json_schema'] is Map
            ? (j['json_schema'] as Map).cast<String, dynamic>()
            : null,
        feature: (j['feature'] ?? '').toString(),
        timeout: Duration(
            seconds: (j['timeout_s'] as num?)?.toInt().clamp(10, 600) ?? 300),
        tier: j['tier'] == 'fast' ? 'fast' : 'main',
        web: j['web'] == true,
      );
}

typedef RelayCompleter = Future<AiResult> Function(RelayRequest request);

class RelayServer {
  RelayServer(this._complete, {required String token, this.port = 8765})
      : _token = normalizeCode(token);

  final RelayCompleter _complete;
  final String _token;
  final int port;

  HttpServer? _server;
  int get boundPort => _server?.port ?? port;
  bool get running => _server != null;

  /// Requests from one phone are few; two at a time keeps the PC's Claude
  /// usage (and CPU) in check.
  static const maxParallel = 2;
  static const maxBodyBytes = 512 * 1024;
  int _active = 0;
  final _waiting = <Completer<void>>[];

  // Wrong pairing codes: at most 10 a minute, then everyone waits.
  final _failures = <DateTime>[];

  Future<void> start() async {
    if (_server != null) return;
    final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
    s.idleTimeout = const Duration(seconds: 30);
    s.listen((r) => unawaited(_handle(r)));
    _server = s;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  /// LAN addresses the phone can use (loopback and link-local left out).
  static Future<List<String>> lanAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in list)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.address.startsWith('169.254.')) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  static const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

  /// A new pairing code: 10 unambiguous characters (~50 bits), shown as
  /// "abcde-fghjk".
  static String newCode() {
    final r = Random.secure();
    final s = List.generate(10, (_) => _alphabet[r.nextInt(_alphabet.length)])
        .join();
    return '${s.substring(0, 5)}-${s.substring(5)}';
  }

  /// "ABCDE-fghjk " → "abcdefghjk": the phone may type it any way.
  static String normalizeCode(String code) =>
      code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _authorized(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final given = normalizeCode(
        h.toLowerCase().startsWith('bearer ') ? h.substring(7) : '');
    if (_token.isEmpty || given.length != _token.length) return false;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given.codeUnitAt(i) ^ _token.codeUnitAt(i);
    }
    return diff == 0;
  }

  bool _throttled() {
    final now = DateTime.now();
    _failures.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    return _failures.length >= 10;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    Future<void> reply(int status, Map<String, dynamic> body) async {
      res.statusCode = status;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(body));
      await res.close();
    }

    try {
      if (_throttled()) {
        return reply(429, {'error': 'Слишком много неверных кодов — подождите минуту.'});
      }
      if (!_authorized(req)) {
        _failures.add(DateTime.now());
        return reply(401, {'error': 'Неверный код подключения.'});
      }
      if (req.method == 'GET' && req.uri.path == '/v1/ping') {
        return reply(200, {'ok': true, 'app': 'LinguaTrace'});
      }
      if (req.method != 'POST' || req.uri.path != '/v1/complete') {
        return reply(404, {'error': 'Нет такого адреса.'});
      }
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > maxBodyBytes) {
          return reply(413, {'error': 'Запрос слишком большой.'});
        }
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        return reply(400, {'error': 'Непонятный запрос.'});
      }
      if (decoded is! Map) return reply(400, {'error': 'Непонятный запрос.'});
      final request = RelayRequest.fromJson(decoded.cast<String, dynamic>());
      if (request.user.trim().isEmpty) {
        return reply(400, {'error': 'Пустой запрос.'});
      }

      await _acquire();
      try {
        final r = await _complete(request);
        return reply(200, {
          'text': r.text,
          'json': r.json,
          'backend': r.backend,
          'provider': r.provider,
          'model': r.model,
          'stop_reason': r.stopReason,
          'input_tokens': r.inputTokens,
          'output_tokens': r.outputTokens,
          'duration_ms': r.durationMs,
          'local_endpoint': r.localEndpoint,
          'sources': [for (final s in r.sources) s.toJson()],
          'searched_web': r.searchedWeb,
        });
      } finally {
        _release();
      }
    } on AiException catch (e) {
      await reply(502, {'error': e.message, 'retryable': e.retryable});
    } catch (e) {
      try {
        await reply(500, {'error': 'Ошибка на компьютере: $e'});
      } catch (_) {}
    }
  }

  Future<void> _acquire() async {
    if (_active < maxParallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(); // the slot passes to the next one
    } else {
      _active--;
    }
  }
}

/// Desktop: runs [RelayServer] as the settings say, and reports its state
/// (address for the phone, errors such as a busy port) to the UI.
class RelayHost extends ChangeNotifier {
  RelayHost(this._cfg, this._complete);

  final ConfigService _cfg;
  final RelayCompleter _complete;
  RelayServer? _server;

  String? error;
  List<String> addresses = const [];
  bool get running => _server?.running ?? false;
  int get port => _server?.boundPort ?? _cfg.relayPort;

  /// Start, restart or stop to match the settings.
  Future<void> apply() async {
    await _server?.stop();
    _server = null;
    error = null;
    if (_cfg.relayServerEnabled) {
      if (_cfg.relayCode.isEmpty) {
        _cfg.relayCode = RelayServer.newCode();
        await _cfg.save();
      }
      final s = RelayServer(_complete, token: _cfg.relayCode, port: _cfg.relayPort);
      try {
        await s.start();
        _server = s;
      } on SocketException catch (e) {
        error = 'Порт ${_cfg.relayPort} занят или недоступен (${e.osError?.message ?? e.message}).';
      }
      addresses = await RelayServer.lanAddresses();
    }
    notifyListeners();
  }

  /// A new pairing code: the phone must enter it again.
  Future<void> newCode() async {
    _cfg.relayCode = RelayServer.newCode();
    await _cfg.save();
    await apply();
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }
}
