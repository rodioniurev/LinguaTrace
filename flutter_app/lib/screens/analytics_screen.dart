import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constructions.dart';
import '../l10n/app_localizations.dart';
import '../models/learning_item.dart';
import '../models/mistake.dart';
import '../models/pattern_entry.dart';
import '../providers/providers.dart';
import 'etymology_screen.dart';
import 'history_screen.dart';
import 'training_screen.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  Map<String, dynamic> _stats = {};
  List<PatternEntry> _patterns = [];
  List<Mistake> _mistakes = [];
  List<LearningItem> _notebook = [];
  List<(String, int)> _constructions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final stats = await db.getStats();
    final patterns = await db.getTopPatterns(limit: 100, minCount: 2);
    final mistakes = await db.getMistakes(limit: 50);
    final notebook = await db.getItems(statuses: const ['learning']);
    final constructions = await db.topConstructions(limit: 8);
    if (mounted) {
      setState(() {
        _stats = stats;
        _patterns = patterns;
        _mistakes = mistakes;
        _notebook = notebook;
        _constructions = constructions;
        _loading = false;
      });
    }
  }

  Future<void> _removeFromNotebook(LearningItem item) async {
    if (item.id == null) return;
    await ref.read(databaseProvider).setItemStatus(item.id!, 'ignored');
    _load();
  }

  /// The notebook: expressions taken into use + the user's problem
  /// constructions — the material the practice and the future feed use.
  List<Widget> _buildNotebook(ColorScheme cs, AppLocalizations l) {
    final expressions =
        _notebook.where((i) => i.kind != 'mistake').toList();
    final mistakeItems = _notebook.where((i) => i.kind == 'mistake').length;
    return [
      Text(l.notebookTitle,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: cs.onSurface, fontSize: 14)),
      const SizedBox(height: 4),
      Text(l.notebookCounts(expressions.length, mistakeItems),
          style: TextStyle(color: cs.outline, fontSize: 12)),
      const SizedBox(height: 8),
      if (expressions.isEmpty && mistakeItems == 0)
        Text(l.notebookEmpty, style: TextStyle(color: cs.outline, fontSize: 12))
      else
        for (final i in expressions.take(30))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(i.lang.toUpperCase(),
                      style: TextStyle(
                          color: cs.outline,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tap: where does it come from, why is it named so.
                      InkWell(
                        onTap: () => EtymologyScreen.open(context, i.text, i.lang),
                        child: Text(i.text,
                            style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dotted,
                                decorationColor: cs.outline)),
                      ),
                      if (i.gloss.isNotEmpty)
                        Text(i.gloss,
                            style: TextStyle(color: cs.outline, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _removeFromNotebook(i),
                  tooltip: l.removeFromNotebook,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 16, color: cs.outline),
                ),
              ],
            ),
          ),
      if (_constructions.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(l.topConstructions,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                fontSize: 14)),
        const SizedBox(height: 6),
        for (final (tag, n) in _constructions)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(constructionTitle(tag),
                      style: TextStyle(color: cs.onSurface, fontSize: 13)),
                ),
                Text(l.timesCount(n),
                    style: TextStyle(color: cs.error, fontSize: 12)),
              ],
            ),
          ),
      ],
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Reload when a new translation is saved (tab state survives in the
    // IndexedStack, initState runs only once).
    ref.listen<int>(historyVersionProvider, (_, __) => _load());
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.patternsTitle),
        actions: [
          // History lives here now ("Журнал" of the notebook); the feed took
          // its place in the bottom bar.
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text(l.journalTitle),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildStatsRow(cs),
                  const SizedBox(height: 16),
                  ..._buildNotebook(cs, l),
                  // ── Error memory + personal training ──
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.myMistakes(_mistakes.length),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TrainingScreen()),
                        ),
                        icon: const Icon(Icons.fitness_center_rounded, size: 16),
                        label: Text(l.training,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_mistakes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l.mistakesHint,
                        style: TextStyle(color: cs.outline, fontSize: 12),
                      ),
                    )
                  else
                    ..._mistakes.take(15).map((m) => _buildMistakeTile(m, cs)),
                  const SizedBox(height: 16),
                  Text(
                    l.wordsLookedUpRepeatedly,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_patterns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Center(
                        child: Text(
                          l.noRepeatedPatterns,
                          style: TextStyle(color: cs.outline),
                        ),
                      ),
                    )
                  else
                    ..._patterns.map((p) => _buildPatternTile(p, cs)),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildMistakeTile(Mistake m, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.original,
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: cs.error.withOpacity(0.6),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 13, color: cs.outline),
                    ),
                    Flexible(
                      child: Text(
                        m.corrected,
                        style: TextStyle(
                          color: cs.secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (m.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      m.reason,
                      style: TextStyle(color: cs.outline, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          // Older builds recorded fixes from unknown backends, some wrong
          // (e.g. "enseguida" → "en seguida"): let the user strike them.
          if (m.id != null)
            IconButton(
              onPressed: () async {
                await ref.read(databaseProvider).rejectMistake(m.id!);
                ref.read(historyVersionProvider.notifier).state++;
              },
              tooltip: AppLocalizations.of(context)!.notAnError,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 16, color: cs.outline),
            ),
          if (m.seenCount > 1)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                AppLocalizations.of(context)!.timesCount(m.seenCount),
                style: TextStyle(
                    color: cs.error, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    return Row(
      children: [
        _statCard(
          l.statTotal,
          '${_stats['total'] ?? 0}',
          cs.primary,
          cs,
        ),
        const SizedBox(width: 10),
        _statCard(
          l.statPairs,
          '${_stats['lang_pairs'] ?? 0}',
          cs.secondary,
          cs,
        ),
        const SizedBox(width: 10),
        _statCard(
          l.statHard,
          '${_stats['hard_patterns'] ?? 0}',
          cs.error,
          cs,
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color, ColorScheme cs) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatternTile(PatternEntry p, ColorScheme cs) {
    // Badge color based on count
    Color badgeColor;
    if (p.count >= 5) {
      badgeColor = cs.error;
    } else if (p.count >= 3) {
      badgeColor = cs.tertiary;
    } else {
      badgeColor = cs.outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(
          p.phrase,
          style: TextStyle(color: cs.onSurface, fontSize: 14),
        ),
        subtitle: Text(
          '${p.sourceLang} > ${p.targetLang}',
          style: TextStyle(color: cs.outline, fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor.withOpacity(0.3)),
          ),
          child: Text(
            AppLocalizations.of(context)!.timesCount(p.count),
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
