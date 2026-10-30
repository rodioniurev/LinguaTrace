/// Personal training screen — generates and stores practice sessions built
/// from the user's recorded mistakes and repeated lookups.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/mistake.dart';
import '../providers/providers.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key});

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  List<TrainingEntry> _trainings = [];
  TrainingEntry? _open;
  bool _loading = true;
  bool _generating = false;
  String? _error;
  int _due = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final rows = await db.getTrainings();
    final due = await db.dueMistakeCount();
    if (mounted) {
      setState(() {
        _trainings = rows;
        _open ??= rows.isNotEmpty ? rows.first : null;
        _due = due;
        _loading = false;
      });
    }
  }

  Future<void> _generate() async {
    final svc = ref.read(trainingProvider);
    if (!svc.isAvailable) {
      setState(() => _error = svc.unavailableReason);
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      // The language being developed — the old targetLang/sourceLang guess
      // produced 'auto' or 'az' and silently matched no mistakes.
      final lang = ref.read(configProvider).learningLang;
      final entry = await svc.generate(
        lang: lang.length >= 2 ? lang.substring(0, 2) : lang,
      );
      if (mounted) {
        setState(() {
          _open = entry;
          _generating = false;
        });
        _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _generating = false;
        });
      }
    }
  }

  /// The user worked through the open session: its mistakes move one step
  /// up the 1 → 3 → 7 → 21 → 60-day ladder.
  Future<void> _markDone() async {
    final t = _open;
    if (t?.id == null || t!.isDone) return;
    await ref.read(databaseProvider).markTrainingDone(t.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.trainingDoneMarked),
      behavior: SnackBarBehavior.floating,
    ));
    final rows = await ref.read(databaseProvider).getTrainings();
    if (!mounted) return;
    setState(() => _open = rows.firstWhere((r) => r.id == t.id, orElse: () => t));
    _load();
  }

  Future<void> _delete(TrainingEntry t) async {
    if (t.id == null) return;
    await ref.read(databaseProvider).deleteTraining(t.id!);
    if (_open?.id == t.id) _open = null;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = ref.watch(configProvider).fontSize;
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.training),
        actions: [
          if (_open != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: l.tooltipCopy,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _open!.content));
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.copied)));
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Generate button + history chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _generating ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.fitness_center_rounded,
                                size: 18),
                        label: Text(_generating
                            ? l.generating
                            : l.newTrainingFromMistakes),
                      ),
                    ],
                  ),
                ),
                // Spaced-repetition status: what the next session will drill.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  child: Row(
                    children: [
                      Icon(Icons.event_repeat_rounded,
                          size: 15, color: cs.tertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _due > 0 ? l.dueForReview(_due) : l.nothingDue,
                          style: TextStyle(
                              color: _due > 0 ? cs.tertiary : cs.outline,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(l.repetitionExplained,
                      style: TextStyle(color: cs.outline, fontSize: 10)),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(_error!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ),
                if (_trainings.length > 1)
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _trainings.length,
                      itemBuilder: (ctx, i) {
                        final t = _trainings[i];
                        final selected = _open?.id == t.id;
                        final label = t.timestamp.length > 16
                            ? t.timestamp.substring(0, 16)
                            : t.timestamp;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InputChip(
                            label: Text(label,
                                style: const TextStyle(fontSize: 11)),
                            selected: selected,
                            onSelected: (_) => setState(() => _open = t),
                            onDeleted: () => _delete(t),
                            deleteIconColor: cs.outline,
                          ),
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: _open == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              l.noTrainingsYet,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: cs.outline, fontSize: 13),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                _open!.content,
                                style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: fs - 1,
                                    height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              if (!_open!.isDone)
                                FilledButton.tonalIcon(
                                  onPressed: _markDone,
                                  icon: const Icon(Icons.check_rounded,
                                      size: 18),
                                  label: Text(l.trainingDone),
                                )
                              else
                                Text(l.trainingDoneMarked,
                                    style: TextStyle(
                                        color: cs.outline, fontSize: 12)),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
