/// A recorded language mistake — harvested from the Correct tab's fixes.
/// Repeated mistakes bump [seenCount]; the training generator uses the most
/// frequent/recent ones to build a personalized practice corpus.
class Mistake {
  final int? id;
  final String original;   // what the user wrote
  final String corrected;  // what it should have been
  final String reason;     // short explanation from the corrector
  final String category;   // grammar | word_choice | article | spelling | ...
  final String lang;       // ISO 639-1 of the text being written
  final String context;    // the full sentence the mistake occurred in
  final String timestamp;
  final int seenCount;

  // ── spaced repetition (v3)
  /// How many training sessions have already covered this mistake.
  final int practiceCount;
  /// When it becomes due again; empty means "due now".
  final String nextDue;

  // ── provenance (v4)
  /// Tag from constructions.dart — lets different sentences aggregate.
  final String construction;
  /// 'error' is recorded as a real mistake; 'upgrade' is a style suggestion.
  final String severity;
  /// Which backend produced the fix, so bad corrections can be audited.
  final String backend;
  /// Where it came from: 'correct' tab, 'auto_check' of the user's own text…
  final String source;

  const Mistake({
    this.id,
    required this.original,
    required this.corrected,
    this.reason = '',
    this.category = '',
    this.lang = '',
    this.context = '',
    this.timestamp = '',
    this.seenCount = 1,
    this.practiceCount = 0,
    this.nextDue = '',
    this.construction = '',
    this.severity = 'error',
    this.backend = '',
    this.source = 'correct',
  });

  factory Mistake.fromMap(Map<String, dynamic> m) => Mistake(
        id: m['id'] as int?,
        original: m['original'] as String? ?? '',
        corrected: m['corrected'] as String? ?? '',
        reason: m['reason'] as String? ?? '',
        category: m['category'] as String? ?? '',
        lang: m['lang'] as String? ?? '',
        context: m['context'] as String? ?? '',
        timestamp: m['timestamp'] as String? ?? '',
        seenCount: m['seen_count'] as int? ?? 1,
        practiceCount: m['practice_count'] as int? ?? 0,
        nextDue: m['next_due'] as String? ?? '',
        construction: m['construction'] as String? ?? '',
        severity: m['severity'] as String? ?? 'error',
        backend: m['backend'] as String? ?? '',
        source: m['source'] as String? ?? 'correct',
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'original': original,
        'corrected': corrected,
        'reason': reason,
        'category': category,
        'lang': lang,
        'context': context,
        'seen_count': seenCount,
      };
}

/// A generated practice session (markdown text) built from the user's
/// accumulated mistakes and lookup patterns.
class TrainingEntry {
  final int? id;
  final String timestamp;
  final String lang;
  final String content;
  /// When the user marked it done (empty = not yet).
  final String doneAt;

  const TrainingEntry({
    this.id,
    this.timestamp = '',
    this.lang = '',
    required this.content,
    this.doneAt = '',
  });

  bool get isDone => doneAt.isNotEmpty;

  factory TrainingEntry.fromMap(Map<String, dynamic> m) => TrainingEntry(
        id: m['id'] as int?,
        timestamp: m['timestamp'] as String? ?? '',
        lang: m['lang'] as String? ?? '',
        content: m['content'] as String? ?? '',
        doneAt: m['done_at'] as String? ?? '',
      );
}
