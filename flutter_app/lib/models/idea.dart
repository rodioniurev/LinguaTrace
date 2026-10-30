/// «Идеи»: projects for articles and inventions — the author's context,
/// attached sources, dictated notes, and what the background research
/// found for each note.
library;

class IdeaProject {
  final int? id;
  final String uuid;
  final String title;
  /// What the project is about, in the author's words — given to every
  /// request as context.
  final String context;
  final String kind; // article | invention | other
  final String createdAt;
  final String updatedAt;
  final int notes;
  final int sources;

  const IdeaProject({
    this.id,
    required this.uuid,
    required this.title,
    this.context = '',
    this.kind = 'article',
    this.createdAt = '',
    this.updatedAt = '',
    this.notes = 0,
    this.sources = 0,
  });

  factory IdeaProject.fromMap(Map<String, Object?> m) => IdeaProject(
        id: m['id'] as int?,
        uuid: m['uuid'] as String? ?? '',
        title: m['title'] as String? ?? '',
        context: m['context'] as String? ?? '',
        kind: m['kind'] as String? ?? 'article',
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
        notes: m['note_count'] as int? ?? 0,
        sources: m['source_count'] as int? ?? 0,
      );
}

class IdeaNote {
  final int? id;
  final String uuid;
  final int projectId;
  /// Raw dictation as recognised.
  final String text;
  /// Punctuated, cleaned text (Claude), '' until processed.
  final String cleanText;
  final String source; // voice | typed | draft
  final String lang;
  /// '' (new) | queued | done | failed | offline
  final String status;
  final String error;
  final String createdAt;
  final String updatedAt;

  const IdeaNote({
    this.id,
    required this.uuid,
    required this.projectId,
    required this.text,
    this.cleanText = '',
    this.source = 'voice',
    this.lang = 'ru',
    this.status = '',
    this.error = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  String get display => cleanText.trim().isNotEmpty ? cleanText : text;

  factory IdeaNote.fromMap(Map<String, Object?> m) => IdeaNote(
        id: m['id'] as int?,
        uuid: m['uuid'] as String? ?? '',
        projectId: m['project_id'] as int? ?? 0,
        text: m['text'] as String? ?? '',
        cleanText: m['clean_text'] as String? ?? '',
        source: m['source'] as String? ?? 'voice',
        lang: m['lang'] as String? ?? 'ru',
        status: m['status'] as String? ?? '',
        error: m['error'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
      );
}

class IdeaSource {
  final int? id;
  final String uuid;
  final int projectId;
  final String kind; // text | url | file | found
  final String title;
  final String url;
  /// Extracted text (articles the author attached); '' for found links.
  final String content;
  /// Short summary for the context of every request ('' until made).
  final String summary;
  final String createdAt;

  const IdeaSource({
    this.id,
    required this.uuid,
    required this.projectId,
    required this.kind,
    this.title = '',
    this.url = '',
    this.content = '',
    this.summary = '',
    this.createdAt = '',
  });

  factory IdeaSource.fromMap(Map<String, Object?> m) => IdeaSource(
        id: m['id'] as int?,
        uuid: m['uuid'] as String? ?? '',
        projectId: m['project_id'] as int? ?? 0,
        kind: m['kind'] as String? ?? 'text',
        title: m['title'] as String? ?? '',
        url: m['url'] as String? ?? '',
        content: m['content'] as String? ?? '',
        summary: m['summary'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
      );
}

class IdeaInsight {
  final int? id;
  final String uuid;
  final int projectId;
  final int? noteId;
  /// Markdown: the idea sharpened, what is known, facts, questions, steps.
  final String text;
  /// "- [title](url) — why" lines.
  final List<({String title, String url, String why})> links;
  final String backend;
  final bool web;
  final String kind; // enrichment | draft
  final String createdAt;

  const IdeaInsight({
    this.id,
    required this.uuid,
    required this.projectId,
    this.noteId,
    required this.text,
    this.links = const [],
    this.backend = '',
    this.web = false,
    this.kind = 'enrichment',
    this.createdAt = '',
  });

  factory IdeaInsight.fromMap(Map<String, Object?> m) => IdeaInsight(
        id: m['id'] as int?,
        uuid: m['uuid'] as String? ?? '',
        projectId: m['project_id'] as int? ?? 0,
        noteId: m['note_id'] as int?,
        text: m['text'] as String? ?? '',
        links: parseLinks(m['links'] as String? ?? ''),
        backend: m['backend'] as String? ?? '',
        web: (m['web'] as int? ?? 0) == 1,
        kind: m['kind'] as String? ?? 'enrichment',
        createdAt: m['created_at'] as String? ?? '',
      );

  static final _linkLine =
      RegExp(r'^\s*[-*•]?\s*\[([^\]]*)\]\((https?://[^)\s]+)\)\s*(?:[—–-]\s*(.*))?$');
  static final _bareUrl = RegExp(r'(https?://[^\s)\]>]+)');

  /// "- [title](url) — why" lines (or bare URLs) → links, deduplicated.
  static List<({String title, String url, String why})> parseLinks(String s) {
    final out = <({String title, String url, String why})>[];
    final seen = <String>{};
    for (final line in s.split('\n')) {
      final m = _linkLine.firstMatch(line);
      if (m != null) {
        final url = m.group(2)!;
        if (seen.add(url)) {
          out.add((title: m.group(1)!.trim(), url: url, why: (m.group(3) ?? '').trim()));
        }
        continue;
      }
      for (final b in _bareUrl.allMatches(line)) {
        final url = b.group(1)!.replaceAll(RegExp(r'[.,;:]+$'), '');
        if (seen.add(url)) out.add((title: '', url: url, why: ''));
      }
    }
    return out;
  }
}
