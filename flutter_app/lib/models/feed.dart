/// News-feed trainer: what the planner asks the model to use, what the model
/// returns (a draft), and what is stored and shown.
library;

/// One learning target the model must weave into a story.
class FeedTargetSpec {
  final String id; // 'T1', 'T2', … (prompt-local)
  final int itemId; // learning_items.id
  final String kind; // mistake | idiom | collocation | proverb | word
  final String canonical; // the correct form to use
  final String gloss; // meaning in the user's native language
  final String wrongForm; // mistakes: what the user wrote
  final String construction; // constructions.dart tag (mistakes)
  final bool required;
  /// First exposures: highlighted in the text. Later: plain, still tappable
  /// (fading enhancement — highlighting known items hurts recall).
  final bool highlight;

  /// Mistakes that are a PATTERN (a missing/confused function word): the
  /// realisation must contain these words ("a" after atreverse, "el" before
  /// a date) — the surrounding verb or noun may differ from the canonical.
  final List<String> mustContain;

  const FeedTargetSpec({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.canonical,
    this.gloss = '',
    this.wrongForm = '',
    this.construction = '',
    this.required = true,
    this.highlight = true,
    this.mustContain = const [],
  });
}

class DraftTargetUse {
  final String targetId;
  final String formUsed; // exact substring of body
  final int occurrence; // 1 = first occurrence of formUsed in body
  final String noteRu;
  const DraftTargetUse(this.targetId, this.formUsed, this.occurrence, this.noteRu);
}

class DraftTask {
  final String kind; // cloze | choice | rephrase | retell
  final String targetId;
  final String promptRu;
  final String text;
  final List<String> options;
  final String answer;
  const DraftTask({
    required this.kind,
    required this.targetId,
    required this.promptRu,
    required this.text,
    required this.options,
    required this.answer,
  });
}

/// The model's structured output for one feed item (FEED_SCHEMA).
class FeedDraft {
  final List<String> storySourceIds; // 'S1', …
  final String headline;
  final String body;
  final String attribution;
  final List<DraftTargetUse> targetsUsed;
  final List<(String, String)> skipped; // (targetId, reason)
  final List<(String, String)> factCheck; // (claim, sourceId)
  final List<DraftTask> tasks;

  const FeedDraft({
    required this.storySourceIds,
    required this.headline,
    required this.body,
    required this.attribution,
    required this.targetsUsed,
    required this.skipped,
    required this.factCheck,
    required this.tasks,
  });

  static String _s(Object? v) => v == null ? '' : v.toString();

  static List _l(Object? v) => v is List ? v : const [];

  factory FeedDraft.fromJson(Map<String, dynamic> j) => FeedDraft(
        storySourceIds: _l(j['story_source_ids']).map(_s).toList(),
        headline: _s(j['headline']).trim(),
        body: _s(j['body']).trim(),
        attribution: _s(j['attribution']).trim(),
        targetsUsed: [
          for (final t in _l(j['targets_used']))
            if (t is Map)
              DraftTargetUse(
                _s(t['target_id']),
                _s(t['form_used']),
                (t['occurrence'] is num)
                    ? (t['occurrence'] as num).toInt()
                    : int.tryParse(_s(t['occurrence'])) ?? 1,
                _s(t['note_ru']),
              ),
        ],
        skipped: [
          for (final t in _l(j['skipped']))
            if (t is Map) (_s(t['target_id']), _s(t['reason'])),
        ],
        factCheck: [
          for (final t in _l(j['fact_check']))
            if (t is Map) (_s(t['claim']), _s(t['source_id'])),
        ],
        tasks: [
          for (final t in _l(j['tasks']))
            if (t is Map)
              DraftTask(
                kind: _s(t['kind']),
                targetId: _s(t['target_id']),
                promptRu: _s(t['prompt_ru']),
                text: _s(t['text']),
                options: _l(t['options']).map(_s).toList(),
                answer: _s(t['answer']),
              ),
        ],
      );
}

/// A located target inside the body (UTF-16 offsets, computed by the
/// client — models are unreliable at character offsets).
class FeedSpan {
  final String targetId;
  final int start;
  final int end;
  final String form;
  const FeedSpan(this.targetId, this.start, this.end, this.form);
}

class ValidationReport {
  final List<String> violations; // human-readable, sent back for repair
  final List<FeedSpan> spans;
  const ValidationReport(this.violations, this.spans);
  bool get ok => violations.isEmpty;
}

// ─────────────────────────────────────────── stored

class FeedItem {
  final int? id;
  final int editionId;
  final String lang;
  final String headline;
  final String body;
  final String attribution;
  final String outlet;
  final String sourceUrl;
  final String publishedAt;
  final String backend;
  final String createdAt;
  final String readAt;
  final List<FeedItemTarget> targets;
  final List<FeedTask> tasks;

  const FeedItem({
    this.id,
    required this.editionId,
    required this.lang,
    required this.headline,
    required this.body,
    this.attribution = '',
    this.outlet = '',
    this.sourceUrl = '',
    this.publishedAt = '',
    this.backend = '',
    this.createdAt = '',
    this.readAt = '',
    this.targets = const [],
    this.tasks = const [],
  });

  factory FeedItem.fromMap(Map<String, dynamic> m,
          {List<FeedItemTarget> targets = const [],
          List<FeedTask> tasks = const []}) =>
      FeedItem(
        id: m['id'] as int?,
        editionId: m['edition_id'] as int? ?? 0,
        lang: m['lang'] as String? ?? '',
        headline: m['headline'] as String? ?? '',
        body: m['body'] as String? ?? '',
        attribution: m['attribution'] as String? ?? '',
        outlet: m['outlet'] as String? ?? '',
        sourceUrl: m['source_url'] as String? ?? '',
        publishedAt: m['published_at'] as String? ?? '',
        backend: m['backend'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
        readAt: m['read_at'] as String? ?? '',
        targets: targets,
        tasks: tasks,
      );
}

class FeedItemTarget {
  final int feedItemId;
  final int itemId;
  final int start;
  final int end;
  final String form;
  final bool highlight;
  // joined from learning_items for display
  final String kind;
  final String canonical;
  final String gloss;
  final String wrongForm;
  final String construction;

  const FeedItemTarget({
    required this.feedItemId,
    required this.itemId,
    required this.start,
    required this.end,
    required this.form,
    this.highlight = true,
    this.kind = '',
    this.canonical = '',
    this.gloss = '',
    this.wrongForm = '',
    this.construction = '',
  });

  factory FeedItemTarget.fromMap(Map<String, dynamic> m) => FeedItemTarget(
        feedItemId: m['feed_item_id'] as int? ?? 0,
        itemId: m['item_id'] as int? ?? 0,
        start: m['start_pos'] as int? ?? 0,
        end: m['end_pos'] as int? ?? 0,
        form: m['form_used'] as String? ?? '',
        highlight: (m['highlight'] as int? ?? 1) == 1,
        kind: m['kind'] as String? ?? '',
        canonical: m['text'] as String? ?? '',
        gloss: m['gloss'] as String? ?? '',
        wrongForm: m['wrong_form'] as String? ?? '',
        construction: m['construction'] as String? ?? '',
      );
}

class FeedTask {
  final int? id;
  final int feedItemId;
  final int? itemId;
  final String kind; // cloze | choice | rephrase | retell
  final String promptRu;
  final String text;
  final List<String> options;
  final String answer;
  final String userAnswer;
  final String result; // '' | ok | fail | fixed
  final String doneAt;

  const FeedTask({
    this.id,
    required this.feedItemId,
    this.itemId,
    required this.kind,
    this.promptRu = '',
    this.text = '',
    this.options = const [],
    this.answer = '',
    this.userAnswer = '',
    this.result = '',
    this.doneAt = '',
  });

  bool get done => doneAt.isNotEmpty;

  factory FeedTask.fromMap(Map<String, dynamic> m) => FeedTask(
        id: m['id'] as int?,
        feedItemId: m['feed_item_id'] as int? ?? 0,
        itemId: m['item_id'] as int?,
        kind: m['kind'] as String? ?? '',
        promptRu: m['prompt_ru'] as String? ?? '',
        text: m['text'] as String? ?? '',
        options: ((m['options'] as String?) ?? '')
            .split('␟')
            .where((o) => o.isNotEmpty)
            .toList(),
        answer: m['answer'] as String? ?? '',
        userAnswer: m['user_answer'] as String? ?? '',
        result: m['result'] as String? ?? '',
        doneAt: m['done_at'] as String? ?? '',
      );
}
