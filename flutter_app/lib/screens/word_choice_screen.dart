/// «Подбор слова»: point at the word the translation got wrong, see the
/// real options for this sentence — meaning, register, fit, collocations —
/// each with the sentence rewritten, and take the one you mean. Returns the
/// chosen sentence to the translate screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_paths.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/word_choice_service.dart';
import 'etymology_screen.dart';

class WordChoiceScreen extends ConsumerStatefulWidget {
  final String source;
  final String translation;
  final String srcLang;
  final String tgtLang;
  const WordChoiceScreen({
    super.key,
    required this.source,
    required this.translation,
    required this.srcLang,
    required this.tgtLang,
  });

  /// The chosen sentence, or null.
  static Future<String?> open(BuildContext context,
          {required String source,
          required String translation,
          required String srcLang,
          required String tgtLang}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => WordChoiceScreen(
              source: source,
              translation: translation,
              srcLang: srcLang,
              tgtLang: tgtLang)));

  @override
  ConsumerState<WordChoiceScreen> createState() => _WordChoiceScreenState();
}

class _WordChoiceScreenState extends ConsumerState<WordChoiceScreen> {
  final _hintCtrl = TextEditingController();
  String _focus = '';
  WordChoice? _choice;
  bool _busy = false;
  String? _error;
  final _saved = <String>{};

  static final _wordRe = RegExp(r"[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*",
      unicode: true);

  List<String> get _words => [
        for (final m in _wordRe.allMatches(widget.source)) m.group(0)!,
      ];

  @override
  void dispose() {
    _hintCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref.read(wordChoiceProvider).suggest(
            source: widget.source,
            translation: widget.translation,
            focus: _focus,
            srcLang: widget.srcLang,
            tgtLang: widget.tgtLang,
            hint: _hintCtrl.text,
          );
      if (mounted) setState(() => _choice = c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(WordOption o) async {
    final db = ref.read(databaseProvider);
    final id = await db.upsertItem(
      kind: o.pattern.trim().contains(' ') ? 'collocation' : 'word',
      lang: widget.tgtLang.length >= 2 ? widget.tgtLang.substring(0, 2) : widget.tgtLang,
      text: o.pattern.isNotEmpty ? o.pattern : o.word,
      gloss: [
        if (_focus.isNotEmpty) _focus,
        if (o.glossRu.isNotEmpty) o.glossRu,
      ].join(' — '),
      notes: o.sentence,
      source: 'word_choice',
      status: 'learning',
    );
    await db.addEvent(id, 'saved', surface: 'word_choice');
    ref.read(historyVersionProvider.notifier).state++;
    if (mounted) setState(() => _saved.add(o.word));
  }

  Future<void> _askClaudeApp(AppLocalizations l) async {
    await SharePlus.instance.share(ShareParams(
        text: l.wordChoiceAskPrompt(
            widget.source, widget.translation, _focus.isEmpty ? '—' : _focus)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final svc = ref.watch(wordChoiceProvider);
    final c = _choice;
    return Scaffold(
      appBar: AppBar(title: Text(l.wordChoiceTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(l.wordChoiceNow,
              style: TextStyle(fontSize: 11, color: cs.outline)),
          Text(widget.translation,
              style: TextStyle(fontSize: 15, color: cs.onSurface)),
          const SizedBox(height: 14),
          Text(l.wordChoicePick,
              style: TextStyle(fontSize: 13, color: cs.onSurface)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in _words)
                ChoiceChip(
                  label: Text(w),
                  selected: _focus == w,
                  onSelected: (sel) => setState(() => _focus = sel ? w : ''),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hintCtrl,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              labelText: l.wordChoiceHintLabel,
              hintText: l.wordChoiceHintExample,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.tune_rounded, size: 18),
            label: Text(_focus.isEmpty
                ? l.wordChoiceRunSentence
                : l.wordChoiceRunWord(_focus)),
          ),
          if (!svc.canExplain) ...[
            const SizedBox(height: 8),
            Text(AppPaths.isDesktop ? l.wordChoiceNoAiDesktop : l.wordChoiceNoAiPhone,
                style: TextStyle(fontSize: 11, color: cs.outline)),
            if (!AppPaths.isDesktop)
              TextButton.icon(
                onPressed: () => _askClaudeApp(l),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(l.askClaudeApp),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SelectableText(_error!,
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
          if (c != null) ..._result(c, cs, l),
        ],
      ),
    );
  }

  List<Widget> _result(WordChoice c, ColorScheme cs, AppLocalizations l) {
    Color fitColor(String fit) => switch (fit) {
          'best' => cs.primary,
          'good' => cs.tertiary,
          'wrong' => cs.error,
          _ => cs.outline,
        };
    return [
      const SizedBox(height: 16),
      if (c.meaningRu.isNotEmpty)
        Text(c.meaningRu,
            style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurface)),
      if (c.bestSentence.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(c.bestSentence,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(c.bestSentence),
                child: Text(l.wordChoiceUse),
              ),
            ],
          ),
        ),
      ],
      if (c.issuesRu.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final i in c.issuesRu)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $i',
                style: TextStyle(fontSize: 12, height: 1.35, color: cs.error)),
          ),
      ],
      if (c.fromDictionary && c.options.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(l.wordChoiceDictionaryNote,
              style: TextStyle(fontSize: 11, color: cs.outline)),
        ),
      const SizedBox(height: 8),
      for (final o in c.options)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: o.word,
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                        if (o.pattern.isNotEmpty && o.pattern != o.word)
                          TextSpan(
                              text: '  ${o.pattern}',
                              style:
                                  TextStyle(fontSize: 12, color: cs.outline)),
                      ])),
                    ),
                    if (!c.fromDictionary)
                      Text(l.wordChoiceFit(o.fit),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: fitColor(o.fit))),
                  ],
                ),
                if (o.glossRu.isNotEmpty || o.register.isNotEmpty)
                  Text(
                      [
                        if (o.glossRu.isNotEmpty) o.glossRu,
                        if (o.register.isNotEmpty) o.register,
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: cs.onSurface)),
                if (o.whyRu.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(o.whyRu,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.35, color: cs.outline)),
                  ),
                if (o.collocations.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(o.collocations.join(' · '),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            color: cs.onSurface)),
                  ),
                if (o.sentence.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SelectableText(o.sentence,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: o.fit == 'wrong'
                                ? cs.outline
                                : cs.onSurface)),
                  ),
                Wrap(
                  spacing: 2,
                  children: [
                    if (o.sentence.isNotEmpty && o.fit != 'wrong')
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(o.sentence),
                        child: Text(l.wordChoiceUse),
                      ),
                    if (o.fit != 'wrong')
                      TextButton(
                        onPressed:
                            _saved.contains(o.word) ? null : () => _save(o),
                        child: Text(_saved.contains(o.word)
                            ? l.savedToNotebook
                            : l.saveToNotebook),
                      ),
                    TextButton(
                      onPressed: () => EtymologyScreen.open(
                          context,
                          o.word,
                          widget.tgtLang.length >= 2
                              ? widget.tgtLang.substring(0, 2)
                              : widget.tgtLang),
                      child: Text(l.wordChoiceOrigin),
                    ),
                    if (o.sentence.isNotEmpty)
                      IconButton(
                        tooltip: l.copy,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: o.sentence)),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
