/// «Лента» — the daily edition: real news retold with the user's own
/// problem constructions and the expressions they are taking into use.
///
/// Reading comes first; targets are marked in the text (a highlighter band
/// while new, a dotted underline once familiar), glossed in the margin
/// below, and every item ends with tasks. Answers appear only after an
/// attempt; graded answers move the item's review schedule.
library;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_paths.dart';
import '../core/constructions.dart';
import '../l10n/app_localizations.dart';
import '../models/feed.dart';
import '../providers/providers.dart';
import '../services/feed_composer.dart';
import '../services/feed_task_grader.dart';
import 'etymology_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  List<FeedItem> _items = [];
  bool _loading = true;
  bool _building = false;
  FeedProgress? _progress;
  String? _error;
  int _due = 0;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    _load(autoBuild: true);
  }

  String get _lang {
    final l = ref.read(configProvider).learningLang;
    return l.length >= 2 ? l.substring(0, 2) : l;
  }

  Future<void> _load({bool autoBuild = false}) async {
    final db = ref.read(databaseProvider);
    final items = await db.getFeedItems(limit: 40);
    final due = await db.dueItemCount(_lang);
    final today = await db.todaysEdition(_lang);
    if (!mounted) return;
    setState(() {
      _items = items;
      _due = due;
      _loading = false;
    });
    // Opening the feed with no edition today builds one — once per session,
    // and only on the PC: a phone with a stale API key would fetch the news
    // and fail on every launch (it can still build by hand).
    if (autoBuild && today == null && !_autoTried && AppPaths.isDesktop) {
      _autoTried = true;
      final composer = ref.read(feedComposerProvider);
      if (composer.isAvailable) _build(count: 4);
    }
  }

  Future<void> _build({int count = 4}) async {
    if (_building) return;
    final composer = ref.read(feedComposerProvider);
    if (!composer.isAvailable) {
      setState(() => _error = AppPaths.isDesktop
          ? composer.unavailableReason
          : AppLocalizations.of(context)!.feedPhoneHint);
      return;
    }
    setState(() {
      _building = true;
      _error = null;
      _progress = null;
    });
    try {
      final r = await composer.buildEdition(
        lang: _lang,
        count: count,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        // Show each item as soon as it passes the checks.
        onItem: (_) => _load(),
      );
      // A new edition goes straight into this device's exchange file.
      if (AppPaths.isDesktop && r.created > 0) {
        try {
          await ref.read(exchangeProvider).exportTo(
              AppPaths.exchangeDirFor(ref.read(configProvider).exchangeDir));
        } catch (_) {}
      }
      if (mounted && r.failed > 0) {
        setState(() => _error =
            AppLocalizations.of(context)!.feedFailedItems(r.failed));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _building = false;
          _progress = null;
        });
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    ref.listen<int>(historyVersionProvider, (_, __) => _load());

    final todayCount = _items
        .where((i) => i.createdAt.startsWith(_todayPrefix()))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.feedTitle),
            Text(l.feedToday(todayCount, _due),
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.feedBuildMore,
            onPressed: _building ? null : () => _build(count: 2),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_building) _buildProgress(cs, l),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(_error!,
                          style: TextStyle(color: cs.error, fontSize: 12)),
                    ),
                  if (_items.isEmpty && !_building)
                    _buildEmpty(cs, l)
                  else
                    for (final item in _items)
                      _FeedCard(key: ValueKey(item.id), item: item),
                ],
              ),
            ),
    );
  }

  static String _todayPrefix() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  Widget _buildProgress(ColorScheme cs, AppLocalizations l) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: (_progress == null || _progress!.total == 0)
                  ? null
                  : _progress!.done / _progress!.total,
              minHeight: 2,
            ),
            const SizedBox(height: 6),
            Text(_progress?.stage ?? l.feedBuilding,
                style: TextStyle(color: cs.outline, fontSize: 12)),
          ],
        ),
      );

  Widget _buildEmpty(ColorScheme cs, AppLocalizations l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Text(l.feedEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline, fontSize: 14)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _building ? null : () => _build(count: 4),
              icon: const Icon(Icons.newspaper_rounded, size: 18),
              label: Text(l.feedBuildToday),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _FeedCard extends ConsumerStatefulWidget {
  final FeedItem item;
  const _FeedCard({super.key, required this.item});

  @override
  ConsumerState<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends ConsumerState<_FeedCard> {
  final _recognizers = <TapGestureRecognizer>[];
  ScrollPosition? _scroll;
  bool _marked = false;

  /// Targets whose task in this card has been answered (their highlight
  /// and gloss are shown only after the attempt).
  late final Set<int> _answered = {
    for (final t in widget.item.tasks)
      if (t.itemId != null && t.done) t.itemId!,
  };

  @override
  void didUpdateWidget(covariant _FeedCard old) {
    super.didUpdateWidget(old);
    // Answers graded elsewhere (the PC) arrive with a reload.
    for (final t in widget.item.tasks) {
      if (t.itemId != null && t.done) _answered.add(t.itemId!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _scroll) {
      _scroll?.removeListener(_maybeMarkRead);
      _scroll = pos?..addListener(_maybeMarkRead);
    }
  }

  @override
  void dispose() {
    _scroll?.removeListener(_maybeMarkRead);
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Exposure counts only when the reader can actually see the card: the
  /// feed tab is the visible one (the tabs live in an IndexedStack, where
  /// hidden tabs are still laid out) and the card's top is on screen.
  void _maybeMarkRead() {
    final id = widget.item.id;
    if (_marked || id == null || widget.item.readAt.isNotEmpty || !mounted) {
      return;
    }
    if (!Visibility.of(context)) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    if (top > screen - 80 || top + box.size.height < 80) return;
    _marked = true;
    ref.read(databaseProvider).markFeedItemRead(id);
  }

  /// A target whose task in this card is still open: shown plain, glossed
  /// only after the attempt — otherwise the task would copy the answer from
  /// the highlight next to it.
  bool _concealed(int itemId) =>
      !_answered.contains(itemId) &&
      widget.item.tasks.any((t) => t.itemId == itemId && t.kind != 'retell');

  void _onAnswered(FeedTask t) {
    if (t.itemId == null || !mounted) return;
    setState(() => _answered.add(t.itemId!));
  }

  Future<void> _openOriginal(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.feedCannotOpen(url))));
    }
  }

  /// Circled digits for margin markers ①…⑨.
  static String _marker(int i) =>
      i < 9 ? String.fromCharCode(0x2460 + i) : '(${i + 1})';

  List<FeedItemTarget> get _distinctTargets {
    final seen = <int>{};
    return [
      for (final t in widget.item.targets)
        if (seen.add(t.itemId)) t,
    ];
  }

  int _markerIndex(int itemId) =>
      _distinctTargets.indexWhere((t) => t.itemId == itemId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = ref.watch(configProvider).fontSize;
    final l = AppLocalizations.of(context)!;
    final it = widget.item;
    // Visibility.of registers a dependency: switching to the feed tab
    // rebuilds the card, and the check runs again after that frame.
    Visibility.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeMarkRead());

    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        // The margin rule of a school notebook — «поля».
        border: Border(left: BorderSide(color: cs.error.withOpacity(0.55), width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              it.outlet.toUpperCase(),
              if (it.publishedAt.length >= 10)
                _shortDate(it.publishedAt),
            ].join(' · '),
            style: TextStyle(
                color: cs.outline, fontSize: 11, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          Text(it.headline,
              style: TextStyle(
                  fontSize: fs + 5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 10),
          _buildBody(cs, fs),
          if (_distinctTargets.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final t in _distinctTargets)
              if (!_concealed(t.itemId)) _buildGloss(t, cs, l),
            if (_distinctTargets.any((t) => _concealed(t.itemId)))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l.feedGlossAfterTask,
                    style: TextStyle(
                        color: cs.outline,
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
              ),
          ],
          const SizedBox(height: 6),
          if (it.sourceUrl.isNotEmpty)
            InkWell(
              onTap: () => _openOriginal(it.sourceUrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(l.feedOpenOriginal(it.outlet),
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        decoration: TextDecoration.underline)),
              ),
            ),
          if (it.tasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l.tasksTitle,
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: cs.outline,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final t in it.tasks)
              _TaskView(
                key: ValueKey(t.id),
                task: t,
                item: it,
                onAnswered: _onAnswered,
              ),
          ],
        ],
      ),
    );
  }

  static String _shortDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildBody(ColorScheme cs, double fs) {
    final body = widget.item.body;
    final base = TextStyle(fontSize: fs + 1, height: 1.55, color: cs.onSurface);
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final spans = <InlineSpan>[];
    var pos = 0;
    final targets = [...widget.item.targets]..sort((a, b) => a.start - b.start);
    for (final t in targets) {
      if (t.start < pos || t.end > body.length || t.start >= t.end) continue;
      // Open task: plain text until the attempt (see _concealed).
      if (_concealed(t.itemId)) continue;
      if (t.start > pos) spans.add(TextSpan(text: body.substring(pos, t.start)));
      final rec = TapGestureRecognizer()..onTap = () => _openTarget(t);
      _recognizers.add(rec);
      final idx = _markerIndex(t.itemId);
      spans.add(TextSpan(
        text: body.substring(t.start, t.end),
        recognizer: rec,
        style: t.highlight
            // New: a highlighter band — "this is what you are absorbing".
            ? TextStyle(
                backgroundColor: cs.tertiary.withOpacity(0.22),
                decoration: TextDecoration.underline,
                decorationColor: cs.tertiary,
              )
            // Familiar: quiet, still tappable (highlighting known items
            // hurts recall of the rest of the text).
            : TextStyle(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                decorationColor: cs.outline,
              ),
      ));
      if (idx >= 0) {
        spans.add(TextSpan(
            text: _marker(idx),
            style: TextStyle(fontSize: fs - 3, color: cs.tertiary)));
      }
      pos = t.end;
    }
    if (pos < body.length) spans.add(TextSpan(text: body.substring(pos)));
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }

  Widget _buildGloss(FeedItemTarget t, ColorScheme cs, AppLocalizations l) {
    final idx = _markerIndex(t.itemId);
    final mistake = t.kind == 'mistake';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => _openTarget(t),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              child: Text(_marker(idx),
                  style: TextStyle(color: cs.tertiary, fontSize: 13)),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      // Older mistakes have no construction tag: show the
                      // reason of the fix instead of an empty title.
                      text: mistake
                          ? (t.construction.isNotEmpty
                              ? constructionTitle(t.construction)
                              : t.gloss)
                          : t.canonical,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: cs.onSurface)),
                  if (!mistake && t.gloss.isNotEmpty)
                    TextSpan(text: ' — ${t.gloss}'),
                  if (mistake && t.wrongForm.isNotEmpty)
                    TextSpan(
                        text: ' · ${l.yourMistakeShort(t.wrongForm, t.canonical)}'),
                ]),
                style: TextStyle(color: cs.outline, fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTarget(FeedItemTarget t) async {
    final db = ref.read(databaseProvider);
    await db.addEvent(t.itemId, 'lookup',
        surface: 'feed', payload: 'feed_item=${widget.item.id}');
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final mistake = t.kind == 'mistake';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.form,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            if (mistake) ...[
              Text(constructionTitle(t.construction),
                  style: TextStyle(color: cs.tertiary, fontSize: 13)),
              const SizedBox(height: 4),
              if (t.wrongForm.isNotEmpty)
                Text(l.yourMistake(t.wrongForm, t.canonical),
                    style: TextStyle(color: cs.onSurface, fontSize: 14)),
            ] else ...[
              if (t.canonical.isNotEmpty && t.canonical != t.form)
                Text(t.canonical,
                    style: TextStyle(color: cs.outline, fontSize: 13)),
              if (t.gloss.isNotEmpty)
                Text(t.gloss,
                    style: TextStyle(color: cs.onSurface, fontSize: 15)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                // Where the word or expression comes from.
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    EtymologyScreen.open(context,
                        mistake ? t.form : t.canonical, widget.item.lang);
                  },
                  icon: const Icon(Icons.history_edu_rounded, size: 16),
                  label: Text(l.chipOrigin),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l.gotIt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TaskView extends ConsumerStatefulWidget {
  final FeedTask task;
  final FeedItem item;
  final void Function(FeedTask) onAnswered;
  const _TaskView(
      {super.key,
      required this.task,
      required this.item,
      required this.onAnswered});

  @override
  ConsumerState<_TaskView> createState() => _TaskViewState();
}

class _TaskViewState extends ConsumerState<_TaskView> {
  final _ctrl = TextEditingController();
  bool _checking = false;
  String? _result; // ok | fail | fixed
  String? _feedback;
  String? _chosen;

  @override
  void initState() {
    super.initState();
    _fromTask();
  }

  void _fromTask() {
    if (widget.task.done) {
      _result = widget.task.result;
      _ctrl.text = widget.task.userAnswer;
      _chosen = widget.task.userAnswer;
    }
  }

  /// A reload brings the stored result — e.g. a phone answer graded on the
  /// PC and imported with its exchange file: show it instead of «pending».
  @override
  void didUpdateWidget(covariant _TaskView old) {
    super.didUpdateWidget(old);
    final t = widget.task;
    if (t.result != old.task.result || t.doneAt != old.task.doneAt) {
      if (t.done && !_checking) {
        setState(() {
          _fromTask();
          _feedback = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  FeedTask get t => widget.task;
  bool get _answered => _result != null;

  FeedTaskGrader get _grader => ref.read(feedTaskGraderProvider);

  Future<void> _gradeLocal(String answer) async {
    // One grade per task: a quick second tap must not grade (and move the
    // review schedule) twice.
    if (_checking || _answered) return;
    setState(() => _checking = true);
    // For a past mistake the accent can be the mistake itself.
    final strict = widget.item.targets
        .any((x) => x.itemId == t.itemId && x.kind == 'mistake');
    final (ok, accents) =
        await _grader.gradeLocal(t, answer, accentsMatter: strict);
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _checking = false;
      _result = ok ? 'ok' : 'fail';
      _feedback = ok
          ? (accents ? l.taskAccents(t.answer) : l.taskCorrect)
          : l.taskWrong(t.answer);
    });
    widget.onAnswered(t);
  }

  /// Rephrase / retell: checked by the corrector (or stored as pending where
  /// no AI is available — the PC grades it after the next exchange).
  Future<void> _gradeFree() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _checking || _answered) return;
    final l = AppLocalizations.of(context)!;
    final history = ref.read(historyVersionProvider.notifier);
    setState(() => _checking = true);
    try {
      final g = await _grader.gradeFree(widget.item, t, text);
      history.state++;
      final buf = StringBuffer();
      if (g.result == 'pending') {
        buf.writeln(l.taskPending);
        if (g.error.isNotEmpty) buf.writeln(g.error);
      } else {
        buf.writeln(g.errors.isEmpty
            ? l.ownTextPerfect
            : g.errors
                .map((f) => '«${f.original}» → «${f.fixed.isEmpty ? l.removeWordLabel : f.fixed}»: ${f.reason}')
                .join('\n'));
        if (!g.usedTarget) buf.writeln(l.taskTargetMissing);
      }
      if (t.answer.isNotEmpty) buf.write(l.taskModelAnswer(t.answer));
      if (!mounted) return;
      setState(() {
        _checking = false;
        _result = g.result;
        _feedback = buf.toString().trim();
      });
      widget.onAnswered(t);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _feedback = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final fs = ref.watch(configProvider).fontSize;
    final free = t.kind == 'rephrase' || t.kind == 'retell';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.promptRu.isNotEmpty)
            Text(t.promptRu,
                style: TextStyle(color: cs.onSurface, fontSize: fs - 1)),
          if (t.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t.text,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: fs,
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 6),
          if (t.kind == 'choice')
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final o in t.options)
                  ChoiceChip(
                    label: Text(o),
                    selected: _chosen == o,
                    onSelected: _answered || _checking
                        ? null
                        : (_) {
                            setState(() => _chosen = o);
                            _gradeLocal(o);
                          },
                  ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    enabled: !_answered && !_checking,
                    minLines: free ? 2 : 1,
                    maxLines: free ? 5 : 1,
                    style: TextStyle(fontSize: fs),
                    decoration: InputDecoration(
                      hintText: free ? l.taskPlaceholder : '____',
                      isDense: true,
                      // A ruled line, not a box.
                      border: const UnderlineInputBorder(),
                    ),
                    onSubmitted: free || _answered
                        ? null
                        : (v) => v.trim().isEmpty ? null : _gradeLocal(v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_answered)
                  TextButton(
                    onPressed: _checking
                        ? null
                        : () {
                            final v = _ctrl.text.trim();
                            if (v.isEmpty) return;
                            free ? _gradeFree() : _gradeLocal(v);
                          },
                    child: _checking
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l.taskCheck),
                  ),
              ],
            ),
          if (_feedback != null || (_answered && t.done))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(
                _feedback ??
                    switch (_result) {
                      'ok' => l.taskCorrect,
                      'pending' => l.taskPending,
                      'fixed' => t.answer.isEmpty
                          ? l.taskChecked
                          : l.taskModelAnswer(t.answer),
                      _ => l.taskWrong(t.answer),
                    },
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: _result == 'ok' ? cs.primary : cs.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}
