/// The background research partner of «Идеи».
///
/// A dictated note is raw speech-to-text. In the background Claude cleans
/// it (punctuation, recognition slips), and — with the project's context,
/// the attached sources and the earlier notes in view — searches the web
/// to sharpen the thought: what is already known (prior art), facts and
/// figures with links, weak points, next steps. Attached articles get a
/// short summary first, so every later request carries them as context.
///
/// Without a checker (a phone with no AI) notes wait as 'queued' and are
/// processed by whichever device has Claude after the next exchange.
library;

import 'dart:async';

import '../core/config.dart';
import '../core/database.dart';
import '../models/idea.dart';
import 'ai_types.dart';
import 'exchange_service.dart';
import 'llm_router.dart';

class Enrichment {
  final String clean;
  final String insight;
  final List<({String title, String url, String why})> links;
  const Enrichment(this.clean, this.insight, this.links);
}

class IdeaEnricher {
  IdeaEnricher(this._llm, this._db, this._cfg);

  final LlmRouter _llm;
  final DatabaseService _db;
  final ConfigService _cfg;

  bool get isAvailable => _llm.hasQualityBackend;
  String get unavailableReason => _llm.unavailableReason;

  bool _running = false;
  bool get running => _running;
  int? processingNote;
  // Notes queued while a pass is running: one more pass picks them up.
  bool _again = false;

  final _changes = StreamController<int>.broadcast();

  /// Project ids whose notes, insights or sources just changed.
  Stream<int> get changes => _changes.stream;

  /// Mark a dictated note for research and start the queue.
  Future<void> enqueue(int noteId) async {
    await _db.setIdeaNoteStatus(noteId, 'queued');
    unawaited(processPending());
  }

  /// Work through everything waiting: source summaries first (they are the
  /// context), then the notes. Returns how many notes were enriched.
  Future<int> processPending() async {
    if (!isAvailable) return 0;
    if (_running) {
      _again = true;
      return 0;
    }
    _running = true;
    var n = 0;
    try {
      do {
        _again = false;
        for (final s in await _db.unsummarizedSources()) {
          try {
            await summarizeSource(s);
          } catch (_) {
            // stays without a summary; the excerpt is used instead
          }
        }
        for (final note in await _db.pendingIdeaNotes()) {
          processingNote = note.id;
          _changes.add(note.projectId);
          try {
            await enrich(note);
            n++;
          } on AiException catch (e) {
            // Offline, no credit, signed out: try again later (here or on
            // the other device after the next exchange).
            await _db.setIdeaNoteStatus(note.id!, 'offline', error: e.message);
          } catch (e) {
            await _db.setIdeaNoteStatus(note.id!, 'failed', error: '$e');
          } finally {
            processingNote = null;
            _changes.add(note.projectId);
          }
        }
      } while (_again);
    } finally {
      _running = false;
    }
    // Results go to the other devices soon (sync server).
    if (n > 0) ExchangeService.requestSync();
    return n;
  }

  Future<void> enrich(IdeaNote note) async {
    final project = await _db.ideaProject(note.projectId);
    if (project == null) return;
    final sources = await _db.ideaSources(note.projectId, includeFound: false);
    final earlier = [
      for (final n in await _db.ideaNotes(note.projectId, limit: 12))
        if (n.id != note.id && n.source != 'draft') n,
    ];
    final r = await _llm.completeResult(
      system: enrichSystem,
      user: buildEnrichMessage(project, sources, earlier, note),
      maxTokens: 10000,
      effort: 'medium',
      timeout: const Duration(minutes: 6),
      allowOnDevice: false,
      tier: 'fast',
      webSearch: _cfg.ideasWebSearch,
      feature: 'ideas',
    );
    final e = parseEnrichment(r.text);
    // Links the model cited, then the pages the search returned.
    final links = [...e.links];
    final seen = {for (final l in links) l.url};
    for (final s in r.sources) {
      if (seen.add(s.url)) links.add((title: s.title, url: s.url, why: ''));
    }
    await _db.setIdeaNoteStatus(note.id!, 'done',
        cleanText: e.clean.isNotEmpty ? e.clean : null);
    await _db.addIdeaInsight(note.projectId,
        noteId: note.id,
        text: e.insight,
        links: [
          for (final l in links)
            '- [${l.title.isEmpty ? l.url : l.title}](${l.url})'
                '${l.why.isNotEmpty ? ' — ${l.why}' : ''}',
        ].join('\n'),
        backend: r.backend,
        web: r.searchedWeb);
    for (final l in links.take(8)) {
      await _db.addIdeaSource(note.projectId,
          kind: 'found', title: l.title, url: l.url, summary: l.why);
    }
  }

  /// A short summary of an attached article, for the context of every
  /// later request.
  Future<void> summarizeSource(IdeaSource s) async {
    final excerpt = s.content.length > 40000 ? s.content.substring(0, 40000) : s.content;
    final r = await _llm.completeResult(
      system: summarySystem,
      user: 'TITLE: ${s.title}\nURL: ${s.url}\nTEXT:\n$excerpt',
      maxTokens: 3000,
      effort: 'low',
      timeout: const Duration(minutes: 3),
      allowOnDevice: false,
      tier: 'fast',
      feature: 'ideas_summary',
    );
    await _db.setIdeaSourceSummary(s.id!, r.text.trim());
    _changes.add(s.projectId);
  }

  /// A discussion turn: Claude answers the author's latest thoughts briefly
  /// and asks one or two questions that move the idea forward. The answer is
  /// read aloud, and kept in the project as a note from 'claude'.
  Future<(int, String)> discuss(int projectId, {String lang = 'ru'}) async {
    final project = await _db.ideaProject(projectId);
    if (project == null) throw const AiException('Проект не найден');
    final sources = await _db.ideaSources(projectId, includeFound: false);
    final notes = [
      for (final n in await _db.ideaNotes(projectId, limit: 14))
        if (n.source != 'draft') n,
    ];
    final r = await _llm.completeResult(
      system: discussSystem,
      user: buildDiscussMessage(project, sources, notes, lang),
      maxTokens: 1500,
      effort: 'low',
      timeout: const Duration(seconds: 60),
      allowOnDevice: false,
      tier: 'fast',
      feature: 'ideas_discuss',
    );
    final text = r.text.trim();
    if (text.isEmpty) throw const AiException('Claude ничего не ответил');
    final id = await _db.addIdeaNote(projectId, text,
        source: 'claude', lang: lang, status: 'done');
    _changes.add(projectId);
    return (id, text);
  }

  /// Visible for tests.
  static String buildDiscussMessage(IdeaProject p, List<IdeaSource> sources,
      List<IdeaNote> newestFirst, String lang) {
    final b = StringBuffer()
      ..writeln('PROJECT: ${p.title} (${_kindRu(p.kind)})')
      ..writeln('CONTEXT (the author\'s words): ${p.context.isEmpty ? '—' : _clip(p.context, 2000)}')
      ..writeln();
    if (sources.isNotEmpty) {
      b.writeln('SOURCES the author attached (summaries):');
      var budget = 5000;
      for (final s in sources) {
        final body = _clip(s.summary.isNotEmpty ? s.summary : s.content, 600);
        final entry = '- ${s.title.isEmpty ? s.url : s.title}: ${body.replaceAll('\n', ' ')}';
        if (entry.length > budget) break;
        budget -= entry.length;
        b.writeln(entry);
      }
      b.writeln();
    }
    b.writeln('THE CONVERSATION SO FAR (oldest first; the last author turn is what to answer):');
    for (final n in newestFirst.reversed) {
      final who = n.source == 'claude' ? 'YOU (Claude)' : 'AUTHOR';
      b.writeln('$who: ${_clip(n.display.replaceAll('\n', ' '), 1200)}');
    }
    b
      ..writeln()
      ..writeln('Answer in language "$lang".');
    return b.toString();
  }

  static const discussSystem = '''
You are the sparring partner of ONE author who is walking and thinking out loud about an article or an invention. Your answer will be READ ALOUD to them through the earphones, so it must sound natural when spoken.

Answer the author's latest turn:
- 2 to 4 short sentences, at most about 70 words. No lists, no headings, no Markdown, no links, no emoji.
- First, one concrete reaction: what is strong, what is doubtful, or a fact or example that matters — never empty praise.
- Then one or two precise questions that move the thought forward: test an assumption, offer a counterexample, ask how it could be measured, who would pay for it, who already does it, what happens if…
- If the author answered your previous question, react to the answer and dig one level deeper. Do not repeat questions you already asked.
- Speak the author's language (given at the end), address them informally ("ты" in Russian) if they do.''';

  /// A draft of the article (or the invention brief) from everything in the
  /// project; stored as a note of kind 'draft'.
  Future<int> composeDraft(int projectId) async {
    final project = await _db.ideaProject(projectId);
    if (project == null) throw const AiException('Проект не найден');
    final notes = (await _db.ideaNotes(projectId))
        .where((n) => n.source != 'draft')
        .toList()
        .reversed
        .toList();
    if (notes.isEmpty) throw const AiException('В проекте пока нет мыслей');
    final insights = await _db.ideaInsights(projectId);
    final sources = await _db.ideaSources(projectId);
    final r = await _llm.completeResult(
      system: project.kind == 'invention' ? inventionDraftSystem : articleDraftSystem,
      user: buildDraftMessage(project, notes, insights, sources),
      maxTokens: 16000,
      effort: 'medium',
      timeout: const Duration(minutes: 8),
      allowOnDevice: false,
      tier: 'main',
      feature: 'ideas_draft',
    );
    final id = await _db.addIdeaNote(projectId, r.text.trim(),
        source: 'draft', lang: notes.last.lang, status: 'done');
    _changes.add(projectId);
    return id;
  }

  // ─────────────────────────────────────────── prompts

  static String _kindRu(String kind) => switch (kind) {
        'invention' => 'изобретение',
        'article' => 'статья',
        _ => 'другое',
      };

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// Visible for tests.
  static String buildEnrichMessage(IdeaProject p, List<IdeaSource> sources,
      List<IdeaNote> earlier, IdeaNote note) {
    final b = StringBuffer()
      ..writeln('PROJECT: ${p.title} (${_kindRu(p.kind)})')
      ..writeln('CONTEXT (the author\'s words): ${p.context.isEmpty ? '—' : _clip(p.context, 3000)}')
      ..writeln()
      ..writeln('SOURCES the author attached:');
    if (sources.isEmpty) b.writeln('(none)');
    var budget = 14000;
    for (final s in sources) {
      final body = s.summary.isNotEmpty ? s.summary : _clip(s.content, 1500);
      final entry = '- ${s.title.isEmpty ? s.url : s.title}${s.url.isNotEmpty ? ' <${s.url}>' : ''}\n  ${body.replaceAll('\n', '\n  ')}';
      if (entry.length > budget) break;
      budget -= entry.length;
      b.writeln(entry);
    }
    b
      ..writeln()
      ..writeln('EARLIER NOTES (newest first):');
    if (earlier.isEmpty) b.writeln('(none)');
    for (final n in earlier.take(8)) {
      // A discussion turn: Claude's own question, not the author's thought.
      final who = n.source == 'claude' ? '(Claude asked) ' : '';
      b.writeln('- $who${_clip(n.display.replaceAll('\n', ' '), 800)}');
    }
    b
      ..writeln()
      ..writeln('NEW NOTE (raw dictation, language "${note.lang}"):')
      ..writeln(note.text);
    return b.toString();
  }

  static const enrichSystem = '''
You are the research partner of ONE author who dictates raw thoughts while walking — ideas for articles and inventions. You receive the PROJECT (title, kind, the author's own description of the context), the SOURCES the author attached (title + summary), EARLIER NOTES of the project, and the NEW NOTE: a raw speech-to-text dictation without proper punctuation, with recognition errors and repetitions.

Write everything in the language of the new note. Do three things:

1. CLEAN — the new note as clean prose: punctuation, paragraphs, obvious recognition errors fixed, repetitions and fillers removed. Keep the author's words, voice and ideas; add nothing of your own.

2. INSIGHT — help the author develop THIS thought, in Markdown with these sections (short, concrete, no padding):
   ### Суть — the idea in one or two sharpened sentences.
   ### Что уже известно — the closest existing work: research, products, patents, articles. Search the web for it when you can. Say plainly if the idea looks new.
   ### Факты и цифры — data that supports or challenges the idea.
   ### Слабые места и вопросы — the 2–4 most important objections or open questions.
   ### Как развить — 2–4 next steps: an experiment, a source to read, a field or person to look at.
   Connect the note to the context, the sources and the earlier notes: point out where it builds on them or contradicts them. Never invent facts, numbers, titles, names or links; if you could not verify something, say so.

3. SOURCES — every web page you relied on, one per line: - [title](url) — why it matters. Nothing if you used none.

Answer in exactly this format:
===CLEAN===
<clean note>
===INSIGHT===
<markdown>
===SOURCES===
<lines>''';

  static const summarySystem = '''
Summarize a text the author attached to their project (an article, notes, a page) so it can serve as context later. In the text's own language, 5–8 bullet points: the main claim, key arguments or methods, important numbers, and anything quotable. No preamble.''';

  static String buildDraftMessage(IdeaProject p, List<IdeaNote> notes,
      List<IdeaInsight> insights, List<IdeaSource> sources) {
    final b = StringBuffer()
      ..writeln('PROJECT: ${p.title} (${_kindRu(p.kind)})')
      ..writeln('CONTEXT: ${p.context.isEmpty ? '—' : p.context}')
      ..writeln()
      ..writeln('NOTES in the order they were dictated:');
    for (final n in notes) {
      // Discussion turns: Claude's questions are context, not the author's text.
      final who = n.source == 'claude' ? '(Claude asked) ' : '';
      b.writeln('- $who${_clip(n.display, 3000)}');
    }
    b
      ..writeln()
      ..writeln('RESEARCH FINDINGS:');
    for (final i in insights.where((i) => i.kind == 'enrichment').take(20)) {
      b.writeln(_clip(i.text, 2500));
    }
    b
      ..writeln()
      ..writeln('SOURCES:');
    for (final s in sources.take(30)) {
      b.writeln('- ${s.title.isEmpty ? s.url : s.title}${s.url.isNotEmpty ? ' <${s.url}>' : ''}'
          '${s.summary.isNotEmpty ? ': ${_clip(s.summary.replaceAll('\n', ' '), 400)}' : ''}');
    }
    return b.toString();
  }

  static const articleDraftSystem = '''
Write a first draft of the author's article from their dictated notes, the research findings and the sources. Use the notes' language and the author's voice and arguments — you are an editor, not a co-author. Markdown: a title, a short lede, sections with headings in a logical order (not the dictation order), facts with links taken from the findings. Mark every gap or unverified claim as [нужно уточнить]. Do not invent facts, quotes or links.''';

  static const inventionDraftSystem = '''
Write a first draft of an invention brief from the author's dictated notes, the research findings and the sources. Use the notes' language. Markdown sections: Проблема; Существующие решения (prior art with links from the findings); Идея; Как это работает; Преимущества; Возможная формула (2–4 short patent-style claims); Открытые вопросы и эксперименты. Mark every gap as [нужно уточнить]. Do not invent facts, patents or links.''';

  static final _section = RegExp(r'^===\s*(CLEAN|INSIGHT|SOURCES)\s*===\s*$',
      multiLine: true);

  /// The three sections of an answer; without the markers the whole text is
  /// the insight. Visible for tests.
  static Enrichment parseEnrichment(String text) {
    final parts = <String, String>{};
    final marks = _section.allMatches(text).toList();
    for (var i = 0; i < marks.length; i++) {
      final start = marks[i].end;
      final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
      parts[marks[i].group(1)!] = text.substring(start, end).trim();
    }
    if (parts.isEmpty) return Enrichment('', text.trim(), IdeaInsight.parseLinks(text));
    return Enrichment(
      parts['CLEAN'] ?? '',
      parts['INSIGHT'] ?? '',
      IdeaInsight.parseLinks(parts['SOURCES'] ?? ''),
    );
  }
}
