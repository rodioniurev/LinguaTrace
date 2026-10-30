import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/languages.dart';
import '../l10n/app_localizations.dart';
import '../models/translation_entry.dart';
import '../providers/providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<TranslationEntry> _rows = [];
  /// Holds the unfiltered result of the latest DB query — used to compute the
  /// language chip set so chips don't disappear after a filter is applied.
  List<TranslationEntry> _allRows = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // ── Multi-select ─────────────────────────────────────────────────────────
  bool _selectMode = false;
  final Set<int> _selected = {};

  // ── Filters ───────────────────────────────────────────────────────────────
  String _langFilter    = '';   // language code; '' = any
  int?   _olderThanDays;        // null = no age filter

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = ref.read(databaseProvider);
    final allRows = await db.getHistory(search: _searchCtrl.text, limit: 500);
    var rows = allRows;

    // Language filter
    if (_langFilter.isNotEmpty) {
      rows = rows
          .where((r) => r.sourceLang == _langFilter || r.targetLang == _langFilter)
          .toList();
    }

    // "Older than N days" filter
    if (_olderThanDays != null) {
      final cutoff = DateTime.now().subtract(Duration(days: _olderThanDays!));
      rows = rows.where((r) {
        try {
          return DateTime.parse(r.timestamp).isBefore(cutoff);
        } catch (_) {
          return false;
        }
      }).toList();
    }

    if (mounted) {
      setState(() {
        _allRows = allRows;
        _rows = rows;
        _loading = false;
      });
    }
  }

  // ── Delete helpers ────────────────────────────────────────────────────────

  Future<void> _deleteSingle(TranslationEntry entry) async {
    if (entry.id == null) return;
    await ref.read(databaseProvider).deleteTranslation(entry.id!);
    _load();
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final ok = await _confirm(l.deleteEntriesQuestion(_selected.length));
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await db.deleteTranslations(_selected.toList());
    setState(() { _selected.clear(); _selectMode = false; });
    _load();
  }

  /// Delete everything currently visible (respects active filters).
  Future<void> _deleteVisible() async {
    final ids = _rows.where((r) => r.id != null).map((r) => r.id!).toList();
    if (ids.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final desc = _filterDescription();
    final message = desc.isEmpty
        ? l.deleteEntriesQuestion(ids.length)
        : l.deleteEntriesFilteredQuestion(ids.length, desc);
    final ok = await _confirm(message, destructive: true);
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await db.deleteTranslations(ids);
    _load();
  }

  Future<bool?> _confirm(String message, {bool destructive = false}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.confirmDeletion),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx)!.delete),
            ),
          ],
        ),
      );

  // ── Select mode ───────────────────────────────────────────────────────────

  void _enterSelectMode([int? firstId]) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      if (firstId != null) _selected.add(firstId);
    });
  }

  void _exitSelectMode() =>
      setState(() { _selectMode = false; _selected.clear(); });

  void _toggleSelect(int id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  void _selectAll() => setState(() {
        _selected.addAll(_rows.where((r) => r.id != null).map((r) => r.id!));
      });

  // ── Filter helpers ────────────────────────────────────────────────────────

  /// All language codes that appear in the unfiltered result set.
  /// Uses `_allRows` (pre-filter) so chips don't vanish once a filter is active.
  List<String> _distinctLangCodes() {
    final codes = <String>{};
    for (final r in _allRows) {
      if (r.sourceLang.isNotEmpty && r.sourceLang != 'auto') codes.add(r.sourceLang);
      if (r.targetLang.isNotEmpty) codes.add(r.targetLang);
    }
    return (codes.toList()..sort());
  }

  String _filterDescription() {
    final l = AppLocalizations.of(context)!;
    final parts = <String>[];
    if (_langFilter.isNotEmpty) {
      parts.add(localizedLangName(
          _langFilter, Localizations.localeOf(context).languageCode));
    }
    if (_olderThanDays != null) parts.add(l.olderThanDaysDesc(_olderThanDays!));
    if (_searchCtrl.text.isNotEmpty) parts.add('"${_searchCtrl.text}"');
    return parts.join(', ');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Reload when a new translation is saved — this tab lives inside an
    // IndexedStack, so initState only ever runs once.
    ref.listen<int>(historyVersionProvider, (_, __) => _load());
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _buildAppBar(cs),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.searchHint,
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.outline),
                isDense: true,
              ),
            ),
          ),
          // Filter bar (language chips + age presets)
          _buildFilterBar(cs),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? _buildEmpty(cs)
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (ctx, i) => _buildTile(_rows[i], cs),
                      ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    if (_selectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelectMode,
          tooltip: l.cancel,
        ),
        title: Text(_selected.isEmpty
            ? l.selectEntries
            : l.selectedCount(_selected.length)),
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: Text(l.allLabel, style: TextStyle(color: cs.primary)),
          ),
          IconButton(
            icon: Icon(Icons.delete_rounded,
                color: _selected.isNotEmpty ? cs.error : cs.outline),
            onPressed: _selected.isNotEmpty ? _deleteSelected : null,
            tooltip: l.tooltipDeleteSelected,
          ),
        ],
      );
    }

    return AppBar(
      title: Text(l.historyTitle(_rows.length)),
      actions: [
        // Delete all visible (respects current filters)
        if (_rows.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: _deleteVisible,
            tooltip: l.tooltipDeleteShown,
          ),
        // Enter multi-select mode
        if (_rows.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.checklist_rounded),
            onPressed: _enterSelectMode,
            tooltip: l.tooltipSelect,
          ),
      ],
    );
  }

  Widget _buildFilterBar(ColorScheme cs) {
    final langCodes = _distinctLangCodes();
    final hasFilter = _langFilter.isNotEmpty || _olderThanDays != null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          // Language chips
          for (final code in langCodes)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                    localizedLangName(
                        code, Localizations.localeOf(context).languageCode),
                    style: const TextStyle(fontSize: 12)),
                selected: _langFilter == code,
                onSelected: (_) {
                  setState(() => _langFilter = _langFilter == code ? '' : code);
                  _load();
                },
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 2),
              ),
            ),

          // Divider between lang and age filters — VerticalDivider needs
          // intrinsic-height parent to render, so use an explicit Container.
          if (langCodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 2),
              child: Container(width: 1, height: 20, color: cs.outline),
            ),

          // Age filter presets: >7d, >30d, >90d
          for (final days in [7, 30, 90])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(AppLocalizations.of(context)!.olderThanChip(days),
                    style: const TextStyle(fontSize: 12)),
                selected: _olderThanDays == days,
                onSelected: (_) {
                  setState(() =>
                      _olderThanDays = _olderThanDays == days ? null : days);
                  _load();
                },
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 2),
              ),
            ),

          // Clear filters
          if (hasFilter)
            ActionChip(
              label: Text(AppLocalizations.of(context)!.clearFilters,
                  style: const TextStyle(fontSize: 12)),
              avatar: const Icon(Icons.close_rounded, size: 14),
              onPressed: () {
                setState(() { _langFilter = ''; _olderThanDays = null; });
                _load();
              },
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    final l = AppLocalizations.of(context)!;
    final filtered =
        _langFilter.isNotEmpty || _olderThanDays != null || _searchCtrl.text.isNotEmpty;
    return Center(
      child: Text(
        filtered ? l.noEntriesMatchFilter : l.noTranslationsYet,
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.outline),
      ),
    );
  }

  Widget _buildTile(TranslationEntry entry, ColorScheme cs) {
    final id = entry.id;
    final isSelected = id != null && _selected.contains(id);

    // ── Multi-select mode: show checkbox ─────────────────────────────────
    if (_selectMode) {
      return CheckboxListTile(
        value: isSelected,
        onChanged: id != null ? (_) => _toggleSelect(id) : null,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        title: Text(
          entry.translatedText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          entry.sourceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.outline, fontSize: 12),
        ),
        secondary: Text(
          '${entry.sourceLang}→${entry.targetLang}',
          style: TextStyle(color: cs.primary, fontSize: 10),
        ),
      );
    }

    // ── Normal mode: swipe-to-delete + long-press to select ───────────────
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: cs.error,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _deleteSingle(entry),
      child: ListTile(
        dense: true,
        onLongPress: () => _enterSelectMode(id),
        title: Text(
          entry.sourceText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: cs.outline, fontSize: 13),
        ),
        subtitle: Text(
          entry.translatedText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${entry.sourceLang} > ${entry.targetLang}',
              style: TextStyle(color: cs.primary, fontSize: 10),
            ),
            Text(
              entry.timestamp.length > 10
                  ? entry.timestamp.substring(0, 10)
                  : entry.timestamp,
              style: TextStyle(color: cs.outlineVariant, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
