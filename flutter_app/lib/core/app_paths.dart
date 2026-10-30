/// Where the app keeps the user's data.
///
/// Desktop used to put the SQLite file in `<current dir>/.dart_tool/…` (the
/// sqflite_common_ffi default), i.e. inside the build folder: `flutter clean`
/// or starting the exe from another folder silently gave an empty history,
/// and six diverging copies piled up. Settings lived in %APPDATA%, which the
/// Windows package sandbox of some launchers redirects, so they didn't
/// reliably survive a restart either.
///
/// Now everything the user owns lives in ONE visible folder,
/// `Documents\LinguaTrace` (override with the `LINGUATRACE_HOME` env var —
/// tests and diagnostics use that so they never touch the real data).
/// Android keeps its app-private locations, which already work.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

class AppPaths {
  AppPaths._();

  static String? _dataDir;
  static String? _dbPath;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Folder with the database, settings and import drop-box.
  static String get dataDir {
    final d = _dataDir;
    if (d == null) throw StateError('AppPaths.init() was not called');
    return d;
  }

  static String get dbPath {
    final d = _dbPath;
    if (d == null) throw StateError('AppPaths.init() was not called');
    return d;
  }

  /// Desktop only: the settings file that replaces SharedPreferences.
  static String get settingsPath => p.join(dataDir, 'settings.json');

  /// Desktop only: old databases dropped here are merged on the next start.
  static String get importDir => p.join(dataDir, 'import');

  /// Default folder for exchange files (one per device).
  static String get defaultExchangeDir => p.join(dataDir, 'exchange');

  /// The folder actually used: the user's choice, else the default.
  static String exchangeDirFor(String configured) =>
      configured.trim().isNotEmpty ? configured.trim() : defaultExchangeDir;

  static Future<void> init({String? overrideDir}) async {
    final env = Platform.environment['LINGUATRACE_HOME'];
    if (overrideDir != null || (env != null && env.trim().isNotEmpty)) {
      _dataDir = overrideDir ?? env!.trim();
    } else if (isDesktop) {
      final docs = await getApplicationDocumentsDirectory();
      _dataDir = p.join(docs.path, 'LinguaTrace');
    } else {
      _dataDir = (await getApplicationSupportDirectory()).path;
    }
    Directory(_dataDir!).createSync(recursive: true);

    if (isDesktop || overrideDir != null || (env != null && env.isNotEmpty)) {
      _dbPath = p.join(_dataDir!, 'linguatrace.db');
    } else {
      // Android/iOS: unchanged location, so the phone's history stays put.
      _dbPath = p.join(await getDatabasesPath(), 'translations.db');
    }
  }

  /// Places where earlier desktop builds left their database: next to the
  /// exe and in the working directory (both via the old CWD-relative path),
  /// plus anything the user dropped into [importDir].
  static List<String> legacyDatabaseCandidates() {
    if (!isDesktop) return const [];
    const rel = ['.dart_tool', 'sqflite_common_ffi', 'databases',
        'translations.db'];
    final seen = <String>{};
    final out = <String>[];
    void add(String path) {
      final norm = p.normalize(p.absolute(path)).toLowerCase();
      if (norm == p.normalize(dbPath).toLowerCase()) return;
      if (seen.add(norm) && File(path).existsSync()) out.add(path);
    }

    add(p.joinAll([p.dirname(Platform.resolvedExecutable), ...rel]));
    add(p.joinAll([Directory.current.path, ...rel]));
    final drop = Directory(importDir);
    if (drop.existsSync()) {
      for (final f in drop.listSync().whereType<File>()) {
        if (f.path.toLowerCase().endsWith('.db')) add(f.path);
      }
    }
    return out;
  }
}
