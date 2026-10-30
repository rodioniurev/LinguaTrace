/// Getting the author's material into a project: a pasted text, a web page
/// (reduced to its readable text), a text file, or a PDF (read by Claude).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_types.dart';
import 'llm_router.dart';

class IngestedText {
  final String title;
  final String text;
  final String url;
  const IngestedText(this.title, this.text, {this.url = ''});
}

class SourceIngest {
  SourceIngest(this._llm, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final LlmRouter _llm;
  final http.Client _http;

  /// Long articles are kept up to this size; summaries carry them into
  /// prompts.
  static const maxChars = 60000;

  /// A web page → its title and readable text. A PDF link goes to Claude.
  Future<IngestedText> fromUrl(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
      throw const AiException('Это не похоже на ссылку (нужно http… или https…)');
    }
    final resp = await _http.get(u, headers: {
      'User-Agent': 'Mozilla/5.0 (LinguaTrace)',
      'Accept': 'text/html,application/xhtml+xml,application/pdf;q=0.9,*/*;q=0.8',
    }).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw AiException('Страница не открылась (${resp.statusCode})');
    }
    final type = resp.headers['content-type'] ?? '';
    if (type.contains('pdf') || u.path.toLowerCase().endsWith('.pdf')) {
      final r = await fromPdf(resp.bodyBytes, name: u.pathSegments.isEmpty ? url : u.pathSegments.last);
      return IngestedText(r.title, r.text, url: url);
    }
    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final (title, text) = htmlToText(html);
    if (text.trim().length < 200) {
      throw const AiException('На странице почти нет текста (возможно, '
          'она требует входа или собирается скриптами) — вставьте текст вручную.');
    }
    return IngestedText(title.isEmpty ? u.host : title, _cap(text), url: url);
  }

  /// A file the user picked: text formats are read as they are; a PDF goes
  /// to Claude.
  Future<IngestedText> fromFile(String path) async {
    final f = File(path);
    final name = path.split(RegExp(r'[\\/]')).last;
    final lower = name.toLowerCase();
    final size = await f.length();
    if (size > 30 * 1024 * 1024) {
      throw const AiException('Файл больше 30 МБ — так много в контекст не войдёт.');
    }
    if (lower.endsWith('.pdf')) return fromPdf(await f.readAsBytes(), name: name);
    final raw = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      final (title, text) = htmlToText(raw);
      return IngestedText(title.isEmpty ? name : title, _cap(text));
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.markdown') ||
        lower.endsWith('.csv') || lower.endsWith('.json') || lower.endsWith('.rtf') ||
        !raw.contains('\u0000')) {
      return IngestedText(name.replaceAll(RegExp(r'\.[^.]+$'), ''), _cap(raw));
    }
    throw const AiException('Такой формат пока не читается: txt, md, html или pdf.');
  }

  /// A PDF: Claude reads it and writes a dense digest (thesis, key points,
  /// figures, quotes) — the whole text would not fit into later prompts.
  Future<IngestedText> fromPdf(Uint8List bytes, {required String name}) async {
    final r = await _llm.completeResult(
      system: _pdfSystem,
      user: 'File: $name',
      maxTokens: 8000,
      effort: 'low',
      timeout: const Duration(minutes: 4),
      allowOnDevice: false,
      tier: 'fast',
      documents: [AiDocument('application/pdf', bytes, name)],
      feature: 'ideas_pdf',
    );
    final title = RegExp(r'^#\s*(.+)$', multiLine: true).firstMatch(r.text)?.group(1)?.trim();
    return IngestedText(title ?? name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
        _cap(r.text));
  }

  static const _pdfSystem = '''
You read a document for an author who is collecting material for an article or an invention. Write a dense digest of the document in its own language, as Markdown:
# <the document's title>
- Who wrote it, where and when (if stated).
## Main claim
## Key points
(bullets: arguments, methods, results)
## Figures and data
(the important numbers with their context)
## Quotes worth keeping
(short, verbatim, with page numbers if visible)
Never add anything that is not in the document.''';

  static String _cap(String s) =>
      s.length <= maxChars ? s : '${s.substring(0, maxChars)}\n…';

  static final _drop = RegExp(
      r'<(script|style|noscript|svg|nav|footer|header|form|aside|iframe)\b[^>]*>.*?</\1\s*>',
      caseSensitive: false,
      dotAll: true);
  static final _block = RegExp(
      r'</?(p|div|br|li|ul|ol|h[1-6]|tr|table|section|article|blockquote|pre)\b[^>]*>',
      caseSensitive: false);
  static final _tag = RegExp(r'<[^>]+>', dotAll: true);
  static final _title =
      RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true);

  /// HTML → (title, readable text): scripts, menus and footers dropped,
  /// blocks become lines, entities decoded. Visible for tests.
  static (String, String) htmlToText(String html) {
    final title = _decode(_title.firstMatch(html)?.group(1)?.replaceAll(_tag, '') ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Prefer the article body when the page marks it.
    final article = RegExp(r'<article\b[^>]*>(.*?)</article>',
            caseSensitive: false, dotAll: true)
        .firstMatch(html)
        ?.group(1);
    var body = article ?? html;
    body = body.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
    body = body.replaceAll(_drop, ' ');
    body = body.replaceAll(_block, '\n');
    body = body.replaceAll(_tag, ' ');
    body = _decode(body);
    final lines = [
      for (final l in body.split('\n'))
        if (l.replaceAll(RegExp(r'\s+'), ' ').trim().length > 1)
          l.replaceAll(RegExp(r'[ \t ]+'), ' ').trim(),
    ];
    return (title, lines.join('\n'));
  }

  static final _entity = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);');
  static const _named = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
    'laquo': '«', 'raquo': '»', 'mdash': '—', 'ndash': '–', 'hellip': '…',
    'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“', 'copy': '©',
  };

  static String _decode(String s) => s.replaceAllMapped(_entity, (m) {
        final e = m.group(1)!;
        if (e.startsWith('#')) {
          final code = e.startsWith('#x') || e.startsWith('#X')
              ? int.tryParse(e.substring(2), radix: 16)
              : int.tryParse(e.substring(1));
          return code == null ? m.group(0)! : String.fromCharCode(code);
        }
        return _named[e.toLowerCase()] ?? m.group(0)!;
      });
}
