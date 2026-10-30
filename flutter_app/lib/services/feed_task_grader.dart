/// Grades feed tasks and turns answers into learning evidence.
///
/// Cloze/choice are graded locally (works offline, on any device). Free
/// answers (rephrase/retell) go through the corrector; when no AI is
/// available — the phone without an API key, or a key that stopped working
/// — the answer is stored as 'pending' and graded later on the PC after an
/// exchange-file sync.
library;

import '../core/config.dart';
import '../core/database.dart';
import '../models/correction.dart';
import '../models/feed.dart';
import '../models/mistake.dart';
import 'correction_service.dart';
import 'feed_validator.dart';

class FreeGrade {
  /// ok | fixed | pending
  final String result;
  final List<CorrectionFix> errors;
  /// Whether at least one of the task's targets appears in the answer.
  final bool usedTarget;
  final bool trustworthy;
  /// Why the answer is pending although a checker is configured.
  final String error;
  const FreeGrade(this.result,
      {this.errors = const [],
      this.usedTarget = false,
      this.trustworthy = true,
      this.error = ''});
}

/// Does [text] realise [canonical]? Delegates to the feed validator, which
/// knows Spanish verb morphology ("dio" ≈ "dar", "se atrevió" ≈ "atreverse").
bool realisesTarget(String text, String canonical, {String kind = 'idiom'}) =>
    FeedValidator.realises(text, canonical, kind: kind);

/// Does [text] use target [t] as the learner should: an expression in any
/// inflection; a past mistake in its CORRECT form, pinned to its
/// construction (any «a» is not «atreverse a»).
bool usesTarget(String text, FeedItemTarget t) {
  if (t.kind == 'mistake') {
    return FeedValidator.realisesMistake(text, t.wrongForm, t.canonical,
        construction: t.construction);
  }
  final key = t.canonical.isNotEmpty ? t.canonical : t.form;
  return realisesTarget(text, key, kind: t.kind.isEmpty ? 'idiom' : t.kind);
}

class FeedTaskGrader {
  final DatabaseService _db;
  final CorrectionService _correction;
  final ConfigService _cfg;

  FeedTaskGrader(this._db, this._correction, this._cfg);

  bool get canCheckFreeText => _correction.hasBackend;

  /// Cloze / choice. A tapped option is compared with the grader's option
  /// predicate (accents count: «esta» / «está» may be the point); a typed
  /// cloze tolerates accents — except for a past mistake, where the accent
  /// can be the mistake itself ([accentsMatter]).
  Future<(bool, bool)> gradeLocal(FeedTask t, String answer,
      {bool accentsMatter = false}) async {
    var (ok, accents) = t.kind == 'choice'
        ? (FeedValidator.sameOption(answer, t.answer), false)
        : FeedValidator.answerMatches(answer, t.answer);
    if (ok && accents && accentsMatter) ok = false;
    if (t.id != null) await _db.saveTaskResult(t.id!, answer, ok ? 'ok' : 'fail');
    if (t.itemId != null) await _db.recordRecall(t.itemId!, ok);
    return (ok, accents);
  }

  /// Rephrase / retell. Real errors are recorded; each target the user
  /// managed to use counts as production (correct if no fix touches it).
  Future<FreeGrade> gradeFree(FeedItem item, FeedTask t, String text) async {
    if (!_correction.hasBackend) {
      if (t.id != null) await _db.saveTaskResult(t.id!, text, 'pending');
      return const FreeGrade('pending');
    }
    final CorrectionResult r;
    try {
      r = await _correction.correct(text, item.lang,
          nativeLang: _cfg.nativeLang, feature: 'feed_task');
    } catch (e) {
      // A configured checker that fails (no credit, offline) must not lose
      // the answer: it waits for the PC like on a phone without AI.
      if (t.id != null) await _db.saveTaskResult(t.id!, text, 'pending');
      return FreeGrade('pending', error: e.toString());
    }
    for (final f in r.recordable) {
      await _db.addMistake(Mistake(
        original: f.original,
        corrected: f.fixed,
        reason: f.reason,
        category: f.category ?? '',
        construction: f.construction,
        severity: f.severity,
        backend: r.backend,
        lang: item.lang,
        context: text,
        source: 'feed',
      ));
    }
    final targetIds = t.itemId != null
        ? {t.itemId!}
        : item.targets.map((x) => x.itemId).toSet();
    var usedAny = false;
    for (final id in targetIds) {
      final matches = item.targets.where((x) => x.itemId == id);
      if (matches.isEmpty) continue;
      final target = matches.first;
      if (!usesTarget(text, target)) continue;
      usedAny = true;
      // A fix inside the target's words means it was not produced right.
      final touched = r.errors
          .any((f) => usesTarget(f.original, target) || usesTarget(f.fixed, target));
      if (r.trustworthy) {
        await _db.recordProduction(id, !touched, surface: 'feed', context: text);
      }
    }
    final result = r.errors.isEmpty && usedAny ? 'ok' : 'fixed';
    if (t.id != null) await _db.saveTaskResult(t.id!, text, result);
    return FreeGrade(result,
        errors: r.errors.toList(), usedTarget: usedAny, trustworthy: r.trustworthy);
  }

  /// Grade answers that were written where no AI was available (the phone),
  /// e.g. right after importing its exchange file on the PC.
  Future<int> gradePending() async {
    if (!_correction.hasBackend) return 0;
    var n = 0;
    for (final (item, task) in await _db.pendingFeedTasks()) {
      try {
        final g = await gradeFree(item, task, task.userAnswer);
        if (g.result != 'pending') n++;
      } catch (_) {
        // Stays pending; retried on the next sync.
      }
    }
    return n;
  }
}
