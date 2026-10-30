import 'package:flutter/material.dart';
import '../core/languages.dart';

/// Bottom-sheet language picker with search and favorites.
class LanguagePickerSheet extends StatefulWidget {
  final String currentValue;
  final bool includeAuto;

  const LanguagePickerSheet({
    super.key,
    required this.currentValue,
    this.includeAuto = false,
  });

  /// Show the picker and return the selected language code (or null).
  static Future<String?> show(
    BuildContext context, {
    required String currentValue,
    bool includeAuto = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LanguagePickerSheet(
        currentValue: currentValue,
        includeAuto: includeAuto,
      ),
    );
  }

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Favorites always shown as chips
  List<String> get _favorites => [
        if (widget.includeAuto) 'auto',
        'en',
        'ru',
        'es',
      ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Entries as (code, localized display name); search matches the code,
  /// the English name AND the Russian name, so "исп", "spa" and "es" all
  /// find Spanish.
  List<MapEntry<String, String>> _filteredFor(String uiLang) {
    final entries = kLanguages.keys
        .map((code) => MapEntry(code, localizedLangName(code, uiLang)))
        .toList();
    if (_query.isEmpty) return entries;
    final q = _query.toLowerCase();
    return entries
        .where((e) =>
            e.key.toLowerCase().contains(q) ||
            e.value.toLowerCase().contains(q) ||
            (kLanguages[e.key] ?? '').toLowerCase().contains(q))
        .toList();
  }

  void _select(String code) {
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: TextStyle(color: cs.onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: Localizations.localeOf(context).languageCode == 'ru'
                        ? 'Поиск языка...'
                        : 'Search languages...',
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.outline),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),

              // Favorite chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  children: _favorites
                      .map((code) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildFavChip(code, cs),
                          ))
                      .toList(),
                ),
              ),

              const Divider(height: 1),

              // Language list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filteredFor(
                          Localizations.localeOf(context).languageCode)
                      .length,
                  itemBuilder: (ctx, i) {
                    final entry = _filteredFor(
                        Localizations.localeOf(ctx).languageCode)[i];
                    final selected = entry.key == widget.currentValue;
                    return ListTile(
                      dense: true,
                      title: Text(
                        entry.value,
                        style: TextStyle(
                          color: selected ? cs.primary : cs.onSurface,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      trailing: selected
                          ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
                          : Text(
                              entry.key,
                              style: TextStyle(color: cs.outline, fontSize: 12),
                            ),
                      onTap: () => _select(entry.key),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFavChip(String code, ColorScheme cs) {
    final ui = Localizations.localeOf(context).languageCode;
    final label = code == 'auto'
        ? (ui == 'ru' ? 'Авто' : 'Auto')
        : localizedLangName(code, ui);
    final selected = code == widget.currentValue;

    return GestureDetector(
      onTap: () => _select(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.15) : cs.outline.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary.withOpacity(0.4) : cs.outline.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? cs.primary : cs.onSurface,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
