import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'core/config.dart';
import 'core/database.dart';
import 'core/settings_store.dart';
import 'core/startup_timings.dart';
import 'providers/providers.dart';
import 'services/dictionary_service.dart';
import 'services/proverb_service.dart';
import 'services/voice_service.dart';

void main() async {
  StartupTimings.start();
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop: use FFI for SQLite
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppPaths.init();
  StartupTimings.mark('папки');

  final db = DatabaseService();
  await db.init(path: AppPaths.dbPath);
  StartupTimings.mark('база');

  // Merge histories left by earlier desktop builds (CWD-relative databases
  // next to the exe) and anything dropped into <data>/import. Idempotent.
  var importedFiles = 0, importedRows = 0;
  for (final legacy in AppPaths.legacyDatabaseCandidates()) {
    try {
      final n = await db.importLegacyDatabase(legacy);
      if (n > 0) {
        importedFiles++;
        importedRows += n;
      }
    } catch (_) {
      // A locked or corrupt old file must never block startup.
    }
  }

  StartupTimings.mark('старые базы');
  if (AppPaths.isDesktop) {
    ConfigService.legacySeed = await readAllSharedPreferences();
  }
  final config = ConfigService();
  await config.init();
  StartupTimings.mark('настройки');

  // Initialize on-device LLM runtime in the BACKGROUND (no model load yet —
  // that happens on demand). Deliberately not awaited: with retries this call
  // can take seconds and must never delay the first frame. If it fails, local
  // LLM features stay unavailable and the rest of the app works.
  unawaited(() async {
    try {
      await FlutterGemma.initialize(
        huggingFaceToken: config.huggingFaceToken.isNotEmpty
            ? config.huggingFaceToken
            : null,
        maxDownloadRetries: 10,
      );
    } catch (_) {
      // ignore — translator falls back to ML Kit / online
    }
  }());

  final voice = VoiceService();
  // Don't await — voice init can fail silently on devices without mic
  voice.init();

  final dictionary = DictionaryService();
  // Don't await — dictionary init can fail silently if DB not bundled
  dictionary.init();

  final proverbs = ProverbService();
  // Don't await — proverb init can fail silently if DB not bundled
  proverbs.init();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        configProvider.overrideWith((ref) => config),
        voiceProvider.overrideWithValue(voice),
        dictionaryProvider.overrideWithValue(dictionary),
        proverbProvider.overrideWithValue(proverbs),
        if (importedFiles > 0)
          importReportProvider
              .overrideWith((ref) => (importedFiles, importedRows)),
      ],
      child: const LinguaTraceApp(),
    ),
  );
  WidgetsBinding.instance
      .addPostFrameCallback((_) => StartupTimings.mark('первый кадр'));
}
