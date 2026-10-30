class PatternEntry {
  final int? id;
  final String phrase;
  final String sourceLang;
  final String targetLang;
  final int count;
  final String firstSeen;
  final String lastSeen;

  const PatternEntry({
    this.id,
    required this.phrase,
    required this.sourceLang,
    required this.targetLang,
    required this.count,
    this.firstSeen = '',
    this.lastSeen = '',
  });

  factory PatternEntry.fromMap(Map<String, dynamic> m) => PatternEntry(
        id: m['id'] as int?,
        phrase: m['phrase'] as String,
        sourceLang: m['source_lang'] as String,
        targetLang: m['target_lang'] as String,
        count: m['count'] as int? ?? 1,
        firstSeen: m['first_seen'] as String? ?? '',
        lastSeen: m['last_seen'] as String? ?? '',
      );
}
