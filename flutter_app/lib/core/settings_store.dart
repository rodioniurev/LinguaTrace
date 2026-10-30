/// Key/value persistence behind [ConfigService].
///
/// Android keeps SharedPreferences. Desktop writes a plain JSON file in the
/// data folder instead: on Windows the SharedPreferences file lives under
/// %APPDATA%, which packaged launchers virtualize, and its plugin swallows
/// write errors — settings (including API keys) could silently fail to
/// survive a restart. Here a failed write throws, and the caller shows it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

abstract class SettingsStore {
  /// Human-readable location, shown in Settings → Diagnostics.
  String get location;

  String? getString(String key);
  bool? getBool(String key);
  double? getDouble(String key);

  /// Stage a value; nothing is written until [flush].
  void set(String key, Object value);

  /// Persist everything staged. Throws on failure.
  Future<void> flush();
}

class PrefsSettingsStore implements SettingsStore {
  final SharedPreferences _prefs;
  final _staged = <String, Object>{};

  PrefsSettingsStore(this._prefs);

  static Future<PrefsSettingsStore> open() async =>
      PrefsSettingsStore(await SharedPreferences.getInstance());

  @override
  String get location => 'SharedPreferences';

  @override
  String? getString(String key) => _staged[key] as String? ?? _prefs.getString(key);
  @override
  bool? getBool(String key) => _staged[key] as bool? ?? _prefs.getBool(key);
  @override
  double? getDouble(String key) => _staged[key] as double? ?? _prefs.getDouble(key);

  @override
  void set(String key, Object value) => _staged[key] = value;

  @override
  Future<void> flush() async {
    final entries = Map.of(_staged);
    _staged.clear();
    var ok = true;
    for (final e in entries.entries) {
      final v = e.value;
      final done = switch (v) {
        String s => await _prefs.setString(e.key, s),
        bool b => await _prefs.setBool(e.key, b),
        double d => await _prefs.setDouble(e.key, d),
        int i => await _prefs.setInt(e.key, i),
        _ => false,
      };
      ok = ok && done;
    }
    if (!ok) throw const FileSystemException('SharedPreferences write failed');
  }
}

class JsonFileSettingsStore implements SettingsStore {
  final File file;
  final Map<String, Object?> _data;

  JsonFileSettingsStore._(this.file, this._data);

  /// Opens [path]; when the file doesn't exist yet, seeds it from
  /// [seedFrom] (the old SharedPreferences values) so nothing is lost.
  static Future<JsonFileSettingsStore> open(String path,
      {Map<String, Object?> Function()? seedFrom}) async {
    final f = File(path);
    Map<String, Object?> data = {};
    if (f.existsSync()) {
      try {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map) data = decoded.cast<String, Object?>();
      } catch (_) {
        // A corrupt file must not brick the app: keep a copy for diagnosis
        // and start from defaults.
        try {
          f.copySync('$path.corrupt');
        } catch (_) {}
      }
    } else if (seedFrom != null) {
      data = seedFrom();
    }
    final store = JsonFileSettingsStore._(f, data);
    if (!f.existsSync()) await store.flush();
    return store;
  }

  @override
  String get location => file.path;

  @override
  String? getString(String key) {
    final v = _data[key];
    return v is String ? v : null;
  }

  @override
  bool? getBool(String key) {
    final v = _data[key];
    return v is bool ? v : null;
  }

  @override
  double? getDouble(String key) {
    final v = _data[key];
    return v is num ? v.toDouble() : null;
  }

  @override
  void set(String key, Object value) => _data[key] = value;

  @override
  Future<void> flush() async {
    file.parent.createSync(recursive: true);
    // Write-then-rename so a crash mid-write never leaves half a file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_data), flush: true);
    await tmp.rename(file.path);
  }
}

/// Everything SharedPreferences currently holds, for a one-time migration.
Future<Map<String, Object?>> readAllSharedPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return {for (final k in prefs.getKeys()) k: prefs.get(k)};
  } catch (_) {
    return {};
  }
}
