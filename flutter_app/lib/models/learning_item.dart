/// One learnable thing: a word or collocation the user needed, an idiom or
/// proverb they chose to take into use, or a construction they got wrong.
/// Everything the future news-feed trainer targets comes from these rows;
/// the counters are updated only by events in `item_events`.
class LearningItem {
  final int? id;
  final String kind; // word|collocation|idiom|proverb|mistake
  final String lang;
  final String text; // canonical correct form
  final String gloss; // meaning in the user's native language
  final String wrongForm; // mistakes: what the user wrote
  final String construction; // tag from constructions.dart
  final String conceptKey;
  final String source;
  final String status; // seen|learning|known|ignored
  final String notes;
  final int stage;
  final String nextDue;
  final int lookups;
  final int exposures;
  final int recallOk;
  final int recallFail;
  final int producedOk;
  final int producedErr;
  final String firstSeen;
  final String lastSeen;

  const LearningItem({
    this.id,
    required this.kind,
    required this.lang,
    required this.text,
    this.gloss = '',
    this.wrongForm = '',
    this.construction = '',
    this.conceptKey = '',
    this.source = '',
    this.status = 'seen',
    this.notes = '',
    this.stage = 0,
    this.nextDue = '',
    this.lookups = 0,
    this.exposures = 0,
    this.recallOk = 0,
    this.recallFail = 0,
    this.producedOk = 0,
    this.producedErr = 0,
    this.firstSeen = '',
    this.lastSeen = '',
  });

  factory LearningItem.fromMap(Map<String, dynamic> m) => LearningItem(
        id: m['id'] as int?,
        kind: m['kind'] as String? ?? '',
        lang: m['lang'] as String? ?? '',
        text: m['text'] as String? ?? '',
        gloss: m['gloss'] as String? ?? '',
        wrongForm: m['wrong_form'] as String? ?? '',
        construction: m['construction'] as String? ?? '',
        conceptKey: m['concept_key'] as String? ?? '',
        source: m['source'] as String? ?? '',
        status: m['status'] as String? ?? 'seen',
        notes: m['notes'] as String? ?? '',
        stage: m['stage'] as int? ?? 0,
        nextDue: m['next_due'] as String? ?? '',
        lookups: m['lookups'] as int? ?? 0,
        exposures: m['exposures'] as int? ?? 0,
        recallOk: m['recall_ok'] as int? ?? 0,
        recallFail: m['recall_fail'] as int? ?? 0,
        producedOk: m['produced_ok'] as int? ?? 0,
        producedErr: m['produced_err'] as int? ?? 0,
        firstSeen: m['first_seen'] as String? ?? '',
        lastSeen: m['last_seen'] as String? ?? '',
      );

  bool get isCollected => status == 'learning' || status == 'known';
}
