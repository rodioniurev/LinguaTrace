/// «Происхождение и история»: one page per word or expression — its path
/// through the languages, why it is named so, the story behind an idiom,
/// its relatives in Spanish, Russian and English, and a hook to remember.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_paths.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/etymology_service.dart';

class EtymologyScreen extends ConsumerStatefulWidget {
  final String term;
  final String lang;
  const EtymologyScreen({super.key, required this.term, required this.lang});

  static Future<void> open(BuildContext context, String term, String lang) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EtymologyScreen(term: term.trim(), lang: lang)));

  @override
  ConsumerState<EtymologyScreen> createState() => _EtymologyScreenState();
}

class _EtymologyScreenState extends ConsumerState<EtymologyScreen> {
  EtymologyPage? _page;
  bool _loading = true;
  bool _building = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(etymologyProvider);
    final cached = await svc.cached(widget.term, widget.lang);
    if (!mounted) return;
    setState(() {
      _page = cached;
      _loading = false;
    });
    if (cached == null && svc.isAvailable) _build();
  }

  Future<void> _build() async {
    if (_building) return;
    setState(() {
      _building = true;
      _error = null;
    });
    try {
      final p = await ref.read(etymologyProvider).build(widget.term, widget.lang);
      if (mounted) setState(() => _page = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _save(EtymologyPage p) async {
    final db = ref.read(databaseProvider);
    final gloss = p.chain.isNotEmpty ? p.chain.last.meaningRu : p.summaryRu;
    final id = await db.upsertItem(
      kind: p.kind == 'word' ? 'word' : 'idiom',
      lang: widget.lang,
      text: widget.term,
      gloss: gloss,
      source: 'etymology',
      status: 'learning',
    );
    await db.addEvent(id, 'saved', surface: 'etymology');
    ref.read(historyVersionProvider.notifier).state++;
    if (mounted) setState(() => _saved = true);
  }

  /// No AI here (a phone without «Claude через компьютер»): hand the
  /// question to the Claude app — the subscription, no extra charge.
  Future<void> _askClaudeApp(AppLocalizations l) async {
    await SharePlus.instance.share(ShareParams(
        text: l.etymologyAskPrompt(widget.term, widget.lang)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final p = _page;
    final available = ref.watch(etymologyProvider).isAvailable;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.term),
        actions: [
          if (p != null)
            IconButton(
              tooltip: _saved ? l.savedToNotebook : l.saveToNotebook,
              onPressed: _saved ? null : () => _save(p),
              icon: Icon(_saved
                  ? Icons.bookmark_added_rounded
                  : Icons.bookmark_add_outlined),
            ),
          if (available && p != null)
            IconButton(
              tooltip: l.etymologyRebuild,
              onPressed: _building ? null : _build,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_building)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LinearProgressIndicator(minHeight: 2),
                        const SizedBox(height: 6),
                        Text(l.etymologyWriting,
                            style: TextStyle(color: cs.outline, fontSize: 12)),
                      ],
                    ),
                  ),
                if (_error != null)
                  SelectableText(_error!,
                      style: TextStyle(color: cs.error, fontSize: 12)),
                if (p == null && !_building && !available) ...[
                  Text(
                      AppPaths.isDesktop
                          ? ref.read(etymologyProvider).unavailableReason
                          : l.etymologyPhoneHint,
                      style: TextStyle(color: cs.outline, fontSize: 13)),
                  const SizedBox(height: 12),
                  if (!AppPaths.isDesktop)
                    FilledButton.tonalIcon(
                      onPressed: () => _askClaudeApp(l),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(l.askClaudeApp),
                    ),
                ],
                if (p != null) ..._pageBody(p, cs, l),
              ],
            ),
    );
  }

  static const _langNames = {
    'es': 'испанский',
    'ru': 'русский',
    'en': 'английский',
    'fr': 'французский',
    'it': 'итальянский',
    'de': 'немецкий',
    'la': 'латынь',
    'other': 'другие',
  };

  List<Widget> _pageBody(EtymologyPage p, ColorScheme cs, AppLocalizations l) {
    final body = TextStyle(fontSize: 15, height: 1.5, color: cs.onSurface);
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                      color: cs.tertiary)),
              const SizedBox(height: 6),
              child,
            ],
          ),
        );
    final certaintyColor = switch (p.certainty) {
      'documented' => cs.primary,
      'probable' => cs.tertiary,
      _ => cs.error,
    };
    final groups = <String, List<EtymologyRelative>>{};
    for (final r in p.relatives) {
      (groups[_langNames.containsKey(r.lang) ? r.lang : 'other'] ??= []).add(r);
    }
    return [
      Text(p.headword,
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, children: [
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text(l.etymologyCertainty(p.certainty),
              style: TextStyle(fontSize: 11, color: certaintyColor)),
          side: BorderSide(color: certaintyColor.withValues(alpha: 0.5)),
        ),
      ]),
      if (p.certaintyNoteRu.isNotEmpty)
        Text(p.certaintyNoteRu,
            style: TextStyle(fontSize: 12, color: cs.outline, height: 1.35)),
      const SizedBox(height: 10),
      if (p.summaryRu.isNotEmpty)
        Text(p.summaryRu,
            style: TextStyle(
                fontSize: 17, height: 1.45, color: cs.onSurface,
                fontWeight: FontWeight.w500)),
      if (p.chain.isNotEmpty)
        section(
          l.etymologyChain,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < p.chain.length; i++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Column(children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: i == p.chain.length - 1
                                    ? cs.primary
                                    : cs.tertiary,
                                shape: BoxShape.circle),
                          ),
                          if (i < p.chain.length - 1)
                            Expanded(
                                child: Container(
                                    width: 1.5,
                                    color: cs.tertiary.withValues(alpha: 0.4))),
                        ]),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: p.chain[i].form,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: cs.onSurface)),
                            TextSpan(
                                text: '  ${p.chain[i].langRu}'
                                    '${p.chain[i].period.isNotEmpty ? ', ${p.chain[i].period}' : ''}',
                                style:
                                    TextStyle(fontSize: 12, color: cs.outline)),
                            if (p.chain[i].meaningRu.isNotEmpty)
                              TextSpan(
                                  text: '\n«${p.chain[i].meaningRu}»',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                      color: cs.onSurface)),
                          ])),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (p.whyRu.isNotEmpty) section(l.etymologyWhy, Text(p.whyRu, style: body)),
      if (p.idiomStoryRu.isNotEmpty)
        section(l.etymologyIdiomStory, Text(p.idiomStoryRu, style: body)),
      if (p.historyRu.isNotEmpty)
        section(l.etymologyHistory, Text(p.historyRu, style: body)),
      if (groups.isNotEmpty)
        section(
          l.etymologyRelatives,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final lang in _langNames.keys)
                if (groups[lang] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_langNames[lang]!,
                            style: TextStyle(fontSize: 12, color: cs.outline)),
                        for (final r in groups[lang]!)
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: r.word,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                            if (r.meaningRu.isNotEmpty)
                              TextSpan(text: ' — ${r.meaningRu}'),
                            if (r.noteRu.isNotEmpty)
                              TextSpan(
                                  text: ' (${r.noteRu})',
                                  style: TextStyle(color: cs.outline)),
                          ]),
                              style: TextStyle(
                                  fontSize: 14, height: 1.45, color: cs.onSurface)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      if (p.falseFriendsRu.isNotEmpty)
        section(l.etymologyFalseFriends, Text(p.falseFriendsRu, style: body)),
      if (p.mnemonicRu.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
            ),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${l.etymologyMnemonic}: ',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: cs.primary)),
              TextSpan(text: p.mnemonicRu),
            ]), style: TextStyle(fontSize: 14, height: 1.45, color: cs.onSurface)),
          ),
        ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
              p.sources.isEmpty
                  ? l.etymologyNoSources
                  : '${l.etymologySources}: ',
              style: TextStyle(fontSize: 11, color: cs.outline)),
          for (final s in p.sources)
            InkWell(
              onTap: () async {
                try {
                  await launchUrl(
                      Uri.parse('https://${s.replaceAll('.wiktionary', '')}'
                          '.wiktionary.org/wiki/${Uri.encodeComponent(widget.term)}'),
                      mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
              child: Text(s,
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.primary,
                      decoration: TextDecoration.underline)),
            ),
          if (p.backend.isNotEmpty)
            Text(' · ${p.backend}',
                style: TextStyle(fontSize: 11, color: cs.outline)),
        ],
      ),
    ];
  }
}
