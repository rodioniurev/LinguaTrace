/// Result of running a sentence through the writing-correction service.
class CorrectionResult {
  /// Corrected version of the user's input (minimal edits).
  final String corrected;

  /// Per-fix breakdown — empty list means the input was already correct.
  final List<CorrectionFix> fixes;

  /// One-sentence overall feedback (optional).
  final String? note;

  /// Which backend actually produced the result ("Claude Opus 5 · подписка").
  final String backend;

  /// False for small local models: show, but don't record as mistakes.
  final bool trustworthy;

  const CorrectionResult({
    required this.corrected,
    required this.fixes,
    required this.backend,
    this.note,
    this.trustworthy = true,
  });

  /// Fixes that count as the user's real errors (go to the error memory).
  Iterable<CorrectionFix> get recordable => trustworthy
      ? fixes.where((f) => f.severity == 'error' && f.confidence >= 0.7 && f.anchored)
      : const [];

  Iterable<CorrectionFix> get errors => fixes.where((f) => f.severity == 'error');
  Iterable<CorrectionFix> get upgrades =>
      fixes.where((f) => f.severity == 'upgrade');
}

/// One named change in a corrected sentence.
class CorrectionFix {
  /// The original word / phrase that was wrong (a substring of the input).
  final String original;

  /// The corrected version.
  final String fixed;

  /// Why it was wrong — one sentence in the user's native language.
  final String reason;

  /// 'grammar', 'word_choice', 'spelling', 'article', 'punctuation', 'style'.
  final String? category;

  /// Tag from constructions.dart ('es.regimen', 'es.ser_estar', …).
  final String construction;

  /// 'error' (really wrong) or 'upgrade' (correct, but a native would say
  /// it better — idiom suggestions land here).
  final String severity;

  /// Model's confidence that the fix is needed, 0..1.
  final double confidence;

  /// Whether [original] occurs verbatim in the input.
  final bool anchored;

  const CorrectionFix({
    required this.original,
    required this.fixed,
    required this.reason,
    this.category,
    this.construction = '',
    this.severity = 'error',
    this.confidence = 1,
    this.anchored = true,
  });
}
