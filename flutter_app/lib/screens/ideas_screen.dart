/// «Идеи»: projects for articles and inventions. One tap to dictate into
/// the latest project — made for thinking out loud while walking.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/idea.dart';
import '../providers/providers.dart';
import 'dictation_screen.dart';
import 'idea_project_screen.dart';

class IdeasScreen extends ConsumerStatefulWidget {
  const IdeasScreen({super.key});

  @override
  ConsumerState<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends ConsumerState<IdeasScreen> {
  List<IdeaProject> _projects = [];
  bool _loading = true;
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = ref.read(ideaEnricherProvider).changes.listen((_) => _load());
    // Thoughts waiting from earlier (offline, the other device): go on.
    unawaited(ref.read(ideaEnricherProvider).processPending());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final p = await ref.read(databaseProvider).ideaProjects();
    if (mounted) {
      setState(() {
        _projects = p;
        _loading = false;
      });
    }
  }

  Future<IdeaProject?> _newProject() async {
    final created = await showProjectDialog(context);
    if (created == null) return null;
    final db = ref.read(databaseProvider);
    final id = await db.addIdeaProject(created.$1,
        context: created.$2, kind: created.$3);
    await _load();
    return db.ideaProject(id);
  }

  Future<void> _dictate() async {
    var p = _projects.isNotEmpty ? _projects.first : null;
    p ??= await _newProject();
    if (p == null || !mounted) return;
    await DictationScreen.open(context, p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    ref.listen<int>(historyVersionProvider, (_, __) => _load());
    return Scaffold(
      appBar: AppBar(
        title: Text(l.ideasTitle),
        actions: [
          IconButton(
            tooltip: l.ideasNewProject,
            onPressed: () async {
              final p = await _newProject();
              if (p != null && context.mounted) {
                await IdeaProjectScreen.open(context, p.id!);
                _load();
              }
            },
            icon: const Icon(Icons.add_rounded),
          ),
          if (Platform.isAndroid)
            PopupMenuButton<String>(
              onSelected: (_) => showDictationLog(context),
              itemBuilder: (c) =>
                  [PopupMenuItem(value: 'log', child: Text(l.dictationLog))],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _dictate,
        icon: const Icon(Icons.mic_rounded),
        label: Text(_projects.isEmpty
            ? l.ideasDictate
            : '${l.ideasDictate}: ${_projects.first.title}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  if (_projects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.ideasEmpty,
                          style: TextStyle(
                              color: cs.outline, fontSize: 14, height: 1.45)),
                    ),
                  for (final p in _projects)
                    Card(
                      child: ListTile(
                        leading: Icon(
                            p.kind == 'invention'
                                ? Icons.lightbulb_outline_rounded
                                : p.kind == 'article'
                                    ? Icons.article_outlined
                                    : Icons.notes_rounded,
                            color: cs.primary),
                        title: Text(p.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (p.context.isNotEmpty)
                              p.context.length > 90
                                  ? '${p.context.substring(0, 90)}…'
                                  : p.context,
                            l.ideasCounts(p.notes, p.sources),
                          ].join('\n'),
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                        isThreeLine: p.context.isNotEmpty,
                        trailing: IconButton(
                          tooltip: l.ideasDictate,
                          icon: const Icon(Icons.mic_none_rounded),
                          onPressed: () async {
                            await DictationScreen.open(context, p);
                            _load();
                          },
                        ),
                        onTap: () async {
                          await IdeaProjectScreen.open(context, p.id!);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// New or edited project: (title, context, kind).
Future<(String, String, String)?> showProjectDialog(BuildContext context,
    {IdeaProject? edit}) async {
  final l = AppLocalizations.of(context)!;
  final title = TextEditingController(text: edit?.title ?? '');
  final ctx = TextEditingController(text: edit?.context ?? '');
  var kind = edit?.kind ?? 'article';
  final r = await showDialog<(String, String, String)>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(edit == null ? l.ideasNewProject : l.ideasEditContext),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: edit == null,
                decoration: InputDecoration(labelText: l.ideasProjectTitleLabel),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final (k, label) in [
                  ('article', l.ideasKindArticle),
                  ('invention', l.ideasKindInvention),
                  ('other', l.ideasKindOther),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: kind == k,
                    onSelected: (_) => set(() => kind = k),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: ctx,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: l.ideasContextLabel,
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: Text(l.cancel)),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(c, (title.text.trim(), ctx.text.trim(), kind));
            },
            child: Text(edit == null ? l.ideasCreate : l.dictationSave),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  ctx.dispose();
  return r;
}
