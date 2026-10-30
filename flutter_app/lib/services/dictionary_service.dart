import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DictionaryEntry {
  final String word;
  final String pos;
  final String gender;
  final String definition;
  final String etymology;
  final List<String> examples;

  const DictionaryEntry({
    required this.word,
    this.pos = '',
    this.gender = '',
    this.definition = '',
    this.etymology = '',
    this.examples = const [],
  });
}

class DictionaryService {
  Database? _db;
  bool _available = false;

  bool get isAvailable => _available;

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'es_wiktionary.db');

      if (!File(dbPath).existsSync()) {
        // Try to copy from assets
        try {
          final data = await rootBundle.load('assets/dict/es_wiktionary.db');
          final bytes = data.buffer.asUint8List();
          await File(dbPath).writeAsBytes(bytes);
        } catch (_) {
          // Dictionary not bundled — that's OK, feature just won't be available
          return;
        }
      }

      _db = await openDatabase(dbPath, readOnly: true);
      _available = true;
    } catch (_) {
      _available = false;
    }
  }

  Future<DictionaryEntry?> lookup(String word) async {
    if (!_available || _db == null) return null;

    final rows = await _db!.query(
      'words',
      where: 'LOWER(word) = ?',
      whereArgs: [word.toLowerCase().trim()],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final r = rows.first;

    List<String> examples = [];
    try {
      examples = List<String>.from(jsonDecode(r['examples'] as String? ?? '[]'));
    } catch (_) {}

    return DictionaryEntry(
      word: r['word'] as String? ?? word,
      pos: r['pos'] as String? ?? '',
      gender: r['gender'] as String? ?? '',
      definition: r['definition'] as String? ?? '',
      etymology: r['etymology'] as String? ?? '',
      examples: examples,
    );
  }

  Future<void> close() async => await _db?.close();
}
