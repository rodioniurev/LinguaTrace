/// One project of «Идеи»: the context, the attached sources, the dictated
/// thoughts with what the background research found, and the draft.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/idea.dart';
import '../providers/providers.dart';
import '../services/exchange_platform.dart';
import '../widgets/markdown_lite.dart';
import 'dictation_screen.dart';
import 'ideas_screen.dart';

class IdeaProjectScreen extends ConsumerStatefulWidget {
  final int projectId;
  const IdeaProjectScreen({super.key, required this.projectId});

  static Future<void> open(BuildContext context, int projectId) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => IdeaProjectScreen(projectId: projectId)));

  @override
  ConsumerState<IdeaProjectScreen> createState() => _IdeaProjectScreenState();
}

class _IdeaProjectScreenState extends ConsumerState<IdeaProjectScreen> {
  IdeaProject? _project;
  List<IdeaNote> _notes = [];
  List<IdeaSource> _sources = [];
  Map<int, IdeaInsight> _insightByNote = {};
  bool _loading = true;
  bool _busy = false;
  String? _message;
  StreamSubscription<int>? _sub;
  final _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
    _sub = ref.read(ideaEnricherProvider).changes.listen((pid) {
      if (pid == widget.projectId) _load();
    });
    unawaited(ref.read(ideaEnricherProvider).processPending());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return; // a download finished after the screen was closed
    final db = ref.read(databaseProvider);
    final p = await db.ideaProject(widget.projectId);
    final notes = await db.ideaNotes(widget.projectId);
    final sources = await db.ideaSources(widget.projectId);
    final insights = await db.ideaInsights(widget.projectId);
    if (!mounted) return;
    setState(() {
      _project = p;
      _notes = notes;
      _sources = sources;
      _insightByNote = {
        for (final i in insights.reversed)
          if (i.noteId != null) i.noteId!: i,
      };
      _loading = false;
    });
  }

  void _say(String m) {
    if (mounted) setState(() => _message = m);
  }

  Future<void> _editContext() async {
    final p = _project;
    if (p == null) return;
    final r = await showProjectDialog(context, edit: p);
    if (r == null) return;
    await ref
        .read(databaseProvider)
        .updateIdeaProject(p.id!, title: r.$1, context: r.$2, kind: r.$3);
    _load();
  }

  // ─────────────────────────────────────────── sources

  Future<void> _addSource() async {
    final l = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(l.ideasAddUrl),
              onTap: () => Navigator.pop(c, 'url')),
          ListTile(
              leading: const Icon(Icons.notes_rounded),
              title: Text(l.ideasAddText),
              onTap: () => Navigator.pop(c, 'text')),
          ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: Text(l.ideasAddFile),
              onTap: () => Navigator.pop(c, 'file')),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'url':
        final clip = (await Clipboard.getData('text/plain'))?.text?.trim() ?? '';
        if (!mounted) return;
        final url = await _ask(l.ideasAddUrl, l.ideasUrlLabel,
            initial: clip.startsWith('http') ? clip : '');
        if (url == null || url.isEmpty) return;
        await _ingest(() async {
          final t = await ref.read(sourceIngestProvider).fromUrl(url);
          await ref.read(databaseProvider).addIdeaSource(widget.projectId,
              kind: 'url', title: t.title, url: url, content: t.text);
        });
      case 'text':
        final text = await _ask(l.ideasAddText, l.ideasTextLabel, multiline: true);
        if (text == null || text.trim().isEmpty) return;
        final firstLine = text.trim().split('\n').first;
        await ref.read(databaseProvider).addIdeaSource(widget.projectId,
            kind: 'text',
            title: firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine,
            content: text.trim());
        unawaited(ref.read(ideaEnricherProvider).processPending());
        _load();
      case 'file':
        final path = await pickExchangeFile();
        if (path == null) return;
        await _ingest(() async {
          final t = await ref.read(sourceIngestProvider).fromFile(path);
          await ref.read(databaseProvider).addIdeaSource(widget.projectId,
              kind: 'file', title: t.title, content: t.text);
        });
        await clearPickedFiles();
    }
  }

  Future<void> _ingest(Future<void> Function() job) async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _message = l.ideasAdding;
    });
    try {
      await job();
      _say('');
      unawaited(ref.read(ideaEnricherProvider).processPending());
    } catch (e) {
      _say(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  Future<String?> _ask(String title, String label,
      {String initial = '', bool multiline = false}) async {
    final l = AppLocalizations.of(context)!;
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: multiline ? 5 : 1,
          maxLines: multiline ? 14 : 1,
          keyboardType: multiline ? TextInputType.multiline : TextInputType.url,
          decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(l.dictationSave)),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _openSource(IdeaSource s) async {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(s.title.isEmpty ? s.url : s.title,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
            if (s.url.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  try {
                    await launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(Uri.tryParse(s.url)?.host ?? s.url),
              ),
            if (s.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              MarkdownLite(s.summary),
            ],
            if (s.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l.ideasSourceText,
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              SelectableText(
                  s.content.length > 8000 ? '${s.content.substring(0, 8000)}…' : s.content,
                  style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurface)),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  Navigator.pop(c);
                  await ref.read(databaseProvider).deleteIdeaSource(s.id!);
                  _load();
                },
                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                label: Text(l.delete, style: TextStyle(color: cs.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────── actions

  Future<void> _draft() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _message = l.ideasDrafting;
    });
    try {
      final id = await ref.read(ideaEnricherProvider).composeDraft(widget.projectId);
      _expanded.add(id);
      _say('');
    } catch (e) {
      _say(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  Future<void> _share() async {
    final p = _project;
    if (p == null) return;
    final l = AppLocalizations.of(context)!;
    final b = StringBuffer()
      ..writeln('# ${p.title}')
      ..writeln()
      ..writeln(p.context)
      ..writeln();
    for (final n in _notes.reversed) {
      b
        ..writeln(n.source == 'draft' ? '## ${l.ideasDraftLabel}' : '## ${n.createdAt}')
        ..writeln(n.display)
        ..writeln();
      final i = _insightByNote[n.id];
      if (i != null) {
        b
          ..writeln(i.text)
          ..writeln();
        for (final link in i.links) {
          b.writeln('- [${link.title.isEmpty ? link.url : link.title}](${link.url})');
        }
        b.writeln();
      }
    }
    final dir = Directory.systemTemp.createTempSync('lt_idea');
    final safe = p.title.replaceAll(RegExp(r'[^\w\-]+', unicode: true), '_');
    final f = File('${dir.path}/$safe.md')..writeAsStringSync(b.toString());
    await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'text/markdown')], subject: p.title));
  }

  Future<void> _deleteProject() async {
    final p = _project;
    if (p == null) return;
    final l = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(l.ideasDeleteConfirm(p.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(databaseProvider).deleteIdeaProject(p.id!);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retry(IdeaNote n) async {
    await ref.read(ideaEnricherProvider).enqueue(n.id!);
    _load();
  }

  // ─────────────────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final p = _project;
    final enricher = ref.watch(ideaEnricherProvider);
    final attached = _sources.where((s) => s.kind != 'found').toList();
    final found = _sources.where((s) => s.kind == 'found').toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.title ?? '', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l.ideasDraft,
            onPressed: _busy || _notes.isEmpty || !enricher.isAvailable ? null : _draft,
            icon: const Icon(Icons.auto_stories_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'share' => _share(),
              'delete' => _deleteProject(),
              _ => _editContext(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(l.ideasEditContext)),
              PopupMenuItem(value: 'share', child: Text(l.ideasShare)),
              PopupMenuItem(value: 'delete', child: Text(l.ideasDelete)),
            ],
          ),
        ],
      ),
      floatingActionButton: p == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await DictationScreen.open(context, p);
                _load();
              },
              icon: const Icon(Icons.mic_rounded),
              label: Text(l.ideasDictate),
            ),
      body: _loading || p == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                unawaited(ref.read(ideaEnricherProvider).processPending());
                await _load();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  // Context: what every request is told about the project.
                  InkWell(
                    onTap: _editContext,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.ideasContext.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 1,
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(p.context.isEmpty ? l.ideasContextLabel : p.context,
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: p.context.isEmpty ? cs.outline : cs.onSurface)),
                        ],
                      ),
                    ),
                  ),
                  if (!enricher.isAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l.ideasNoAi,
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                    ),
                  if (_message != null && _message!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        Expanded(
                          child: SelectableText(_message!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _busy ? cs.outline : cs.error)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Text(l.ideasSources,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : _addSource,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l.ideasAddSource),
                    ),
                  ]),
                  for (final s in attached)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          s.kind == 'url'
                              ? Icons.link_rounded
                              : s.kind == 'file'
                                  ? Icons.description_outlined
                                  : Icons.notes_rounded,
                          size: 20),
                      title: Text(s.title.isEmpty ? s.url : s.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          s.summary.isNotEmpty
                              ? s.summary.replaceAll('\n', ' ')
                              : l.ideasStatusQueued,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                      onTap: () => _openSource(s),
                    ),
                  if (found.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('${l.ideasFound} (${found.length})',
                          style: TextStyle(fontSize: 13, color: cs.onSurface)),
                      children: [
                        for (final s in found)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.travel_explore_rounded, size: 18),
                            title: Text(s.title.isEmpty ? s.url : s.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: s.summary.isEmpty
                                ? null
                                : Text(s.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: cs.outline)),
                            onTap: () => _openSource(s),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(l.ideasNotes,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (_notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(l.ideasNoNotes,
                          style: TextStyle(color: cs.outline, fontSize: 13)),
                    ),
                  for (final n in _notes) _noteCard(n, cs, l, enricher.processingNote),
                ],
              ),
            ),
    );
  }

  Widget _noteCard(IdeaNote n, ColorScheme cs, AppLocalizations l, int? working) {
    final insight = _insightByNote[n.id];
    final open = _expanded.contains(n.id) || n.source == 'draft' && _expanded.isEmpty;
    final status = n.id == working
        ? l.ideasStatusWorking
        : switch (n.status) {
            'queued' => l.ideasStatusQueued,
            'offline' => l.ideasStatusOffline,
            'failed' => l.ideasStatusFailed,
            _ => '',
          };
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: n.source == 'draft'
          ? cs.tertiary.withValues(alpha: 0.06)
          : n.source == 'claude'
              ? cs.primaryContainer.withValues(alpha: 0.25)
              : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                  n.source == 'draft'
                      ? Icons.auto_stories_rounded
                      : n.source == 'claude'
                          ? Icons.forum_rounded
                          : n.source == 'typed'
                              ? Icons.keyboard_rounded
                              : Icons.mic_none_rounded,
                  size: 14,
                  color: n.source == 'claude' ? cs.primary : cs.outline),
              const SizedBox(width: 6),
              Text(
                  n.source == 'draft'
                      ? l.ideasDraftLabel
                      : n.source == 'claude'
                          ? l.ideasClaude
                          : n.createdAt.length >= 16
                          ? n.createdAt.substring(0, 16)
                          : n.createdAt,
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              const Spacer(),
              if (status.isNotEmpty)
                Text(status,
                    style: TextStyle(
                        fontSize: 11,
                        color: n.status == 'failed' ? cs.error : cs.tertiary)),
              PopupMenuButton<String>(
                iconSize: 18,
                padding: EdgeInsets.zero,
                onSelected: (v) async {
                  if (v == 'copy') {
                    await Clipboard.setData(ClipboardData(text: n.display));
                  } else if (v == 'retry') {
                    await _retry(n);
                  } else if (v == 'delete') {
                    await ref.read(databaseProvider).deleteIdeaNote(n.id!);
                    _load();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'copy', child: Text(l.copy)),
                  if (n.source != 'draft' && n.source != 'claude')
                    PopupMenuItem(value: 'retry', child: Text(l.ideasRetry)),
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              ),
            ]),
            if (n.source == 'draft')
              MarkdownLite(n.display, fontSize: 14)
            else
              SelectableText(n.display,
                  style: TextStyle(fontSize: 15, height: 1.45, color: cs.onSurface)),
            if (n.error.isNotEmpty && n.status != 'done')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(n.error,
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ),
            if (insight != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(() =>
                    open ? _expanded.remove(n.id) : _expanded.add(n.id!)),
                child: Row(children: [
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18, color: cs.primary),
                  Text(
                      insight.web
                          ? '${l.ideasInsight} · ${l.ideasWithWeb}'
                          : l.ideasInsight,
                      style: TextStyle(fontSize: 12, color: cs.primary)),
                ]),
              ),
              if (open) ...[
                const SizedBox(height: 4),
                MarkdownLite(insight.text, fontSize: 13.5),
                for (final link in insight.links)
                  InkWell(
                    onTap: () async {
                      try {
                        await launchUrl(Uri.parse(link.url),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: link.title.isEmpty ? link.url : link.title,
                            style: TextStyle(
                                color: cs.primary,
                                decoration: TextDecoration.underline)),
                        if (link.why.isNotEmpty) TextSpan(text: ' — ${link.why}'),
                      ]), style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                if (n.cleanText.isNotEmpty && n.cleanText != n.text)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(l.ideasRaw,
                        style: TextStyle(fontSize: 12, color: cs.outline)),
                    children: [
                      SelectableText(n.text,
                          style: TextStyle(fontSize: 12.5, color: cs.outline)),
                    ],
                  ),
                if (insight.backend.isNotEmpty)
                  Text(insight.backend,
                      style: TextStyle(fontSize: 10.5, color: cs.outline)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
