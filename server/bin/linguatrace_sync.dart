/// linguatrace-sync — the LinguaTrace sync server.
///
///   linguatrace-sync new-key                  print a new access key
///   linguatrace-sync serve [options]          run the server
///
/// Options of serve:
///   --port 8790            port to listen on
///   --host 0.0.0.0         address to listen on (127.0.0.1 behind a proxy)
///   --data ./data          where the files are kept
///   --keys ./keys.txt      access keys, one per line (# comments allowed);
///                          the environment variable LINGUATRACE_KEYS
///                          (comma-separated) works too
///   --cert f --key f       serve HTTPS with this certificate (PEM)
///   --max-mb 100           largest exchange file accepted
///   --quiet                no request log
library;

import 'dart:async';
import 'dart:io';

import 'package:linguatrace_sync/sync_server.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == 'help' || args.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  switch (args.first) {
    case 'new-key':
      stdout.writeln(SyncServer.newKey());
    case 'serve':
      await _serve(_options(args.skip(1).toList()));
    default:
      stderr.writeln('unknown command: ${args.first}\n\n$_usage');
      exitCode = 64;
  }
}

Map<String, String> _options(List<String> args) {
  final o = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq > 0) {
      o[a.substring(2, eq)] = a.substring(eq + 1);
    } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      o[a.substring(2)] = args[++i];
    } else {
      o[a.substring(2)] = 'true';
    }
  }
  return o;
}

Future<void> _serve(Map<String, String> o) async {
  final keys = <String>[
    ...?Platform.environment['LINGUATRACE_KEYS']?.split(','),
    if (o['keys'] != null && File(o['keys']!).existsSync())
      ...File(o['keys']!).readAsLinesSync(),
  ].map((k) => k.trim()).where((k) => k.isNotEmpty && !k.startsWith('#'));
  if (keys.isEmpty) {
    stderr.writeln('No access keys. Make one:\n'
        '  linguatrace-sync new-key >> keys.txt\n'
        'and start with --keys keys.txt');
    exitCode = 78;
    return;
  }
  final data = Directory(o['data'] ?? 'data')..createSync(recursive: true);
  final quiet = o['quiet'] == 'true';
  final server = SyncServer(
    dataDir: data,
    keys: keys,
    maxBytes: (int.tryParse(o['max-mb'] ?? '') ?? 100) * 1024 * 1024,
    log: quiet ? null : (line) => stdout.writeln('${_now()} $line'),
  );
  SecurityContext? tls;
  if (o['cert'] != null && o['key'] != null) {
    tls = SecurityContext()
      ..useCertificateChain(o['cert']!)
      ..usePrivateKey(o['key']!);
  }
  final port = int.tryParse(o['port'] ?? '') ?? 8790;
  final http = await server.listen(host: o['host'] ?? '0.0.0.0', port: port, tls: tls);
  stdout.writeln('${_now()} LinguaTrace sync on ${tls == null ? 'http' : 'https'}://'
      '${http.address.address}:${http.port} | data ${data.absolute.path} | '
      '${keys.length} key(s)');

  Future<void> stop(ProcessSignal s) async {
    stdout.writeln('${_now()} stopping ($s)');
    await http.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}

String _now() => DateTime.now().toIso8601String().substring(0, 19);

const _usage = '''
LinguaTrace sync server: keeps one exchange file per device; the app merges.

  linguatrace-sync new-key              print a new access key
  linguatrace-sync serve [options]      run the server

  --port 8790     --host 0.0.0.0     --data ./data     --keys ./keys.txt
  --cert fullchain.pem --key privkey.pem   (HTTPS without a proxy)
  --max-mb 100    --quiet

Keys may also come from LINGUATRACE_KEYS (comma-separated).''';
