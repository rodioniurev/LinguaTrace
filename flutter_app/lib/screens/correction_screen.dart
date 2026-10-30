/// "Polish" screen — writing-correction tutor.
///
/// User writes a sentence in the language they're learning (defaults to
/// the configured target language). An LLM returns a polished version plus
/// a per-fix breakdown that explains *why* each change was made.
///
/// Backend chain handled by [CorrectionService]:
/// on-device LLM → Ollama → cloud AI (Claude/ChatGPT).
/// Every returned fix is also recorded into the mistakes table (error
/// memory) — the Insights tab builds personalized training from it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constructions.dart';
import '../core/languages.dart';
import '../l10n/app_localizations.dart';
import '../models/correction.dart';
import '../models/mistake.dart';
import '../providers/providers.dart';
import '../widgets/language_selector.dart';
import 'training_screen.dart';

class CorrectionScreen extends ConsumerStatefulWidget {
  const CorrectionScreen({super.key});

  @override
  ConsumerState<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends ConsumerState<CorrectionScreen> {
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();

  late String _lang;             // Language being polished — defaults to target
  bool _loading = false;
  String? _error;
  CorrectionResult? _result;

  /// How many fixes from the current result went into the error memory.
  int _recorded = 0;

  /// Recorded fix → mistake id (for «Это не ошибка»).
  final Map<CorrectionFix, int> _fixIds = {};
  final Set<int> _rejected = {};

  // "Подробнее" panel state
  bool _explaining = false;
  String? _explanation;
  String? _explainError;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    // The language being developed — not the translator's target, which is
    // usually the user's native Russian.
    _lang = cfg.learningLang;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _recorded = 0;
      _explanation = null;
      _explainError = null;
      _fixIds.clear();
      _rejected.clear();
    });
    try {
      final svc = ref.read(correctionProvider);
      final cfg = ref.read(configProvider);
      final result =
          await svc.correct(text, _lang, nativeLang: cfg.nativeLang);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
        });
      }
      // Error memory: only real, confident errors from a trustworthy
      // backend become recorded mistakes (style "upgrades" and guesses of
      // small local models don't). Awaited, so the count shown is the truth.
      final recordable = result.recordable.toList();
      if (recordable.isNotEmpty) {
        final db = ref.read(databaseProvider);
        for (final fix in recordable) {
          _fixIds[fix] = await db.addMistake(Mistake(
            original: fix.original,
            corrected: fix.fixed,
            reason: fix.reason,
            category: fix.category ?? '',
            construction: fix.construction,
            severity: fix.severity,
            backend: result.backend,
            lang: _lang.length >= 2 ? _lang.substring(0, 2) : _lang,
            context: text,
            source: 'correct',
          ));
        }
        ref.read(historyVersionProvider.notifier).state++;
        if (mounted) setState(() => _recorded = recordable.length);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _explain() async {
    final r = _result;
    if (r == null || _explaining) return;
    setState(() {
      _explaining = true;
      _explainError = null;
    });
    try {
      final text = await ref.read(explanationProvider).explain(
            original: _inputCtrl.text.trim(),
            corrected: r.corrected,
            fixes: r.fixes,
            langName: _langName(_lang),
          );
      if (mounted) {
        setState(() {
          _explanation = text;
          _explaining = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _explainError = e.toString();
          _explaining = false;
        });
      }
    }
  }

  Future<void> _pickLang() async {
    final code = await LanguagePickerSheet.show(
      context,
      currentValue: _lang,
      includeAuto: false,
    );
    if (code != null && code != _lang) {
      setState(() => _lang = code);
    }
  }

  void _copyCorrected() {
    if (_result == null) return;
    Clipboard.setData(ClipboardData(text: _result!.corrected));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.copied)),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cfg = ref.watch(configProvider);
    final fontSize = cfg.fontSize;
    final svc = ref.read(correctionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.polishTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Backend hint when no backend is available
                  if (!svc.hasBackend) _buildNoBackendBanner(cs),

                  // Input area
                  _buildInputCard(cs, fontSize),

                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.error.withOpacity(0.25)),
                      ),
                      child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
                    ),
                  ],

                  // Result
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    _buildResultCard(_result!, cs, fontSize),
                  ],
                ],
              ),
            ),
          ),

          // Action row pinned at bottom (thumb-reachable).
          // Lang chip + Check button live here together so the user never
          // reaches to the top of the screen during normal use.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  // Language chip — Material InkWell so it gets a proper
                  // 48-tall touch target with feedback.
                  Material(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: _pickLang,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _langName(_lang),
                              style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.expand_more_rounded, size: 16, color: cs.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading || _inputCtrl.text.trim().isEmpty
                          ? null
                          : _check,
                      icon: _loading
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: Text(
                        _loading
                            ? AppLocalizations.of(context)!.checking
                            : AppLocalizations.of(context)!.checkButton,
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoBackendBanner(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.tertiary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cs.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.noBackendHint,
              style: TextStyle(color: cs.onSurface, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(ColorScheme cs, double fs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        children: [
          TextField(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            maxLines: null,
            minLines: 3,
            style: TextStyle(color: cs.onSurface, fontSize: fs),
            onChanged: (_) => setState(() {}), // re-enable Check button
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!
                  .writeSomethingIn(_langName(_lang)),
              hintStyle: TextStyle(color: cs.outlineVariant),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            ),
          ),
          // Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _inputCtrl.text = data!.text!;
                      setState(() {});
                    }
                  },
                  icon: Icon(Icons.paste_rounded, size: 18, color: cs.outline),
                  tooltip: AppLocalizations.of(context)!.tooltipPaste,
                ),
                const Spacer(),
                if (_inputCtrl.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _inputCtrl.clear();
                      setState(() {
                        _result = null;
                        _error = null;
                      });
                    },
                    icon: Icon(Icons.clear_rounded, size: 18, color: cs.outline),
                    tooltip: AppLocalizations.of(context)!.tooltipClear,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(CorrectionResult r, ColorScheme cs, double fs) {
    final perfect = r.fixes.isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: perfect / N fixes
          Row(
            children: [
              Icon(
                perfect
                    ? Icons.check_circle_rounded
                    : Icons.spellcheck_rounded,
                size: 18,
                color: perfect ? Colors.green : cs.primary,
              ),
              const SizedBox(width: 6),
              Text(
                perfect
                    ? AppLocalizations.of(context)!.looksPerfect
                    : AppLocalizations.of(context)!.fixesCount(r.fixes.length),
                style: TextStyle(
                  color: perfect ? Colors.green : cs.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                AppLocalizations.of(context)!.viaProvider(r.backend),
                style: TextStyle(color: cs.outline, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Corrected sentence
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.primary.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    r.corrected,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: fs + 1,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _copyCorrected,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Icon(Icons.copy_rounded, size: 18, color: cs.primary),
                  ),
                ),
              ],
            ),
          ),

          // Optional one-line note
          if (r.note != null) ...[
            const SizedBox(height: 8),
            Text(
              r.note!,
              style: TextStyle(color: cs.outline, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],

          // Per-fix list
          if (r.fixes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outline.withOpacity(0.4)),
            const SizedBox(height: 10),
            for (final fix in r.fixes) _buildFixRow(fix, cs),
            if (!r.trustworthy)
              Text(AppLocalizations.of(context)!.notRecordedLocal,
                  style: TextStyle(color: cs.outline, fontSize: 11)),
          ],

          // "Подробнее" — full breakdown with rules, examples and word history
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: _explaining ? null : _explain,
                icon: _explaining
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.menu_book_rounded, size: 18),
                label: Text(_explaining
                    ? AppLocalizations.of(context)!.detailsLoading
                    : AppLocalizations.of(context)!.detailsButton),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_explainError != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_explainError!,
                  style: TextStyle(color: cs.error, fontSize: 11)),
            ),
          if (_explanation != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.tertiary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.tertiary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.detailsTitle,
                    style: TextStyle(
                        color: cs.tertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _explanation!,
                    style: TextStyle(
                        color: cs.onSurface, fontSize: fs - 1, height: 1.4),
                  ),
                ],
              ),
            ),
          ],

          // Error memory: make the invisible bookkeeping visible, and give a
          // direct route to the practice built from it.
          if (_recorded > 0) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: cs.outline.withOpacity(0.4)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.psychology_rounded, size: 16, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.mistakesRecorded(_recorded),
                    style: TextStyle(color: cs.outline, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrainingScreen()),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(AppLocalizations.of(context)!.toTraining,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFixRow(CorrectionFix f, ColorScheme cs) {
    // Long fragments (full sentences, German/Russian compounds) break the
    // visual diff when squeezed into one Wrap row. Switch to a vertical
    // layout — original above, ↓, fixed below — so the relationship stays
    // legible on narrow screens.
    final long = f.original.length + f.fixed.length > 30;
    final l = AppLocalizations.of(context)!;
    final id = _fixIds[f];
    final rejected = id != null && _rejected.contains(id);

    // The construction ("управление глагола") says more than the generic
    // category ("grammar"); an upgrade is labelled as such, not as an error.
    final tagText = f.severity == 'upgrade'
        ? l.upgradeLabel
        : (f.construction.isNotEmpty && f.construction != 'other'
            ? constructionTitle(f.construction)
            : (f.category != null && f.category!.isNotEmpty
                ? _categoryLabel(f.category!)
                : ''));
    final categoryTag = tagText.isNotEmpty
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.tertiary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tagText,
              style: TextStyle(color: cs.tertiary, fontSize: 10),
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (long) ...[
            _diffChip(f.original, isOriginal: true, cs: cs),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Icon(Icons.arrow_downward_rounded, size: 14, color: cs.outline),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _diffChip(f.fixed, isOriginal: false, cs: cs)),
                if (categoryTag != null) ...[
                  const SizedBox(width: 6),
                  categoryTag,
                ],
              ],
            ),
          ] else ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                _diffChip(f.original, isOriginal: true, cs: cs),
                Icon(Icons.arrow_forward_rounded, size: 14, color: cs.outline),
                _diffChip(f.fixed, isOriginal: false, cs: cs),
                if (categoryTag != null) categoryTag,
              ],
            ),
          ],
          if (f.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                f.reason,
                style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontSize: 12),
              ),
            ),
          if (id != null && !rejected)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await ref.read(databaseProvider).rejectMistake(id);
                  ref.read(historyVersionProvider.notifier).state++;
                  if (mounted) {
                    setState(() {
                      _rejected.add(id);
                      _recorded = (_recorded - 1).clamp(0, 1 << 30);
                    });
                  }
                },
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(l.notAnError, style: const TextStyle(fontSize: 11)),
              ),
            )
          else if (rejected)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 2),
              child: Text(l.markedNotError,
                  style: TextStyle(color: cs.outline, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _diffChip(String text, {required bool isOriginal, required ColorScheme cs}) {
    final color = isOriginal ? cs.error : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text.isEmpty ? AppLocalizations.of(context)!.removeWordLabel : text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          decoration: isOriginal ? TextDecoration.lineThrough : TextDecoration.none,
        ),
      ),
    );
  }

  String _categoryLabel(String code) {
    final l = AppLocalizations.of(context)!;
    switch (code.toLowerCase()) {
      case 'grammar':     return l.catGrammar;
      case 'word_choice': return l.catWord;
      case 'article':     return l.catArticle;
      case 'spelling':    return l.catSpelling;
      case 'punctuation': return l.catPunctuation;
      case 'style':       return l.catStyle;
      default:            return code;
    }
  }

  String _langName(String code) {
    final two = code.length >= 2 ? code.substring(0, 2) : code;
    return (kLanguages[code] ?? kLanguages[two] ?? two.toUpperCase()).split('(').first.trim();
  }
}
