/// Desktop settings live in a JSON file we control: they must round-trip,
/// seed from the old SharedPreferences values once, survive a corrupt file,
/// and surface write failures instead of swallowing them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/config.dart';
import 'package:lingua_trace/core/settings_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lt_settings'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('values round-trip through a restart', () async {
    final path = '${tmp.path}/settings.json';
    final cfg = ConfigService();
    await cfg.init(store: await JsonFileSettingsStore.open(path));
    cfg
      ..anthropicApiKey = 'sk-ant-api03-abc'
      ..aiProvider = 'claude'
      ..learningLang = 'es'
      ..fontSize = 17;
    await cfg.save();
    expect(cfg.lastSaveError, isNull);

    final again = ConfigService();
    await again.init(store: await JsonFileSettingsStore.open(path));
    expect(again.anthropicApiKey, 'sk-ant-api03-abc');
    expect(again.aiProvider, 'claude');
    expect(again.fontSize, 17);
  });

  test('the old default models move to their 5.5 successors once', () async {
    final path = '${tmp.path}/settings.json';
    File(path).writeAsStringSync(
        '{"anthropic_model": "claude-opus-5", "fast_model": "claude-sonnet-5"}');
    final cfg = ConfigService();
    await cfg.init(store: await JsonFileSettingsStore.open(path));
    expect(cfg.anthropicModel, 'claude-opus-5-5');
    expect(cfg.fastModel, 'claude-sonnet-5-5');

    // Choosing the older Opus afterwards is respected.
    cfg.anthropicModel = 'claude-opus-5';
    await cfg.save();
    final again = ConfigService();
    await again.init(store: await JsonFileSettingsStore.open(path));
    expect(again.anthropicModel, 'claude-opus-5');
    expect(again.fastModel, 'claude-sonnet-5-5');
  });

  test('first run seeds from old SharedPreferences values', () async {
    final store = await JsonFileSettingsStore.open(
      '${tmp.path}/settings.json',
      seedFrom: () => {'target_lang': 'es', 'ollama_enabled': true},
    );
    final cfg = ConfigService();
    await cfg.init(store: store);
    expect(cfg.targetLang, 'es');
    expect(cfg.ollamaEnabled, isTrue);
    expect(File('${tmp.path}/settings.json').existsSync(), isTrue);
  });

  test('a corrupt file does not brick startup', () async {
    final path = '${tmp.path}/settings.json';
    File(path).writeAsStringSync('{not json');
    final cfg = ConfigService();
    await cfg.init(store: await JsonFileSettingsStore.open(path));
    expect(cfg.sourceLang, 'auto');
    expect(File('$path.corrupt').existsSync(), isTrue);
  });

  test('desktop: "Claude" with no API key moves to the subscription route',
      () async {
    final store = await JsonFileSettingsStore.open('${tmp.path}/s.json',
        seedFrom: () => {'ai_provider': 'claude', 'anthropic_api_key': ''});
    final cfg = ConfigService();
    await cfg.init(store: store);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      expect(cfg.aiProvider, 'claude_code');
    }
  });

  test('a failed write is reported, not swallowed', () async {
    final cfg = ConfigService();
    await cfg.init(store: _FailingStore());
    await cfg.save();
    expect(cfg.lastSaveError, isNotNull);
  });
}

class _FailingStore implements SettingsStore {
  @override
  String get location => 'nowhere';
  @override
  String? getString(String key) => null;
  @override
  bool? getBool(String key) => null;
  @override
  double? getDouble(String key) => null;
  @override
  void set(String key, Object value) {}
  @override
  Future<void> flush() async =>
      throw const FileSystemException('disk full');
}
