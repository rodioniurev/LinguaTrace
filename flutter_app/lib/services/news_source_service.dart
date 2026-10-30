/// RSS/Atom ingestion for the news-feed trainer.
///
/// Only a headline and a short lead (≤ 2 sentences, ≤ 400 chars) survive
/// ingestion. The feed shows an original retelling with attribution and a
/// link, and article bodies are copyrighted — so `content:encoded` and Atom
/// `<content>` are cut out before parsing and never read, not even as a
/// fallback.
///
/// Real feeds are messy (a bare `&`, control characters, raw HTML that
/// breaks one item, ISO-8859-1 labels on UTF-8 bytes), so parsing is
/// layered: sanitise → parse the document → if that still fails, parse item
/// by item, so one broken item never costs the whole source. Live blogs,
/// teaser stubs, shop pages and stale items are dropped here: there is
/// nothing in them to retell as a story.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/news_article.dart';

/// Result of [NewsSourceService.fetchAll]. A failing source never fails the
/// whole fetch — it lands in [errors] and the other sources still arrive.
class FetchReport {
  /// Fresh articles from every source, deduplicated by url hash (the source
  /// listed first wins), newest first; undated ones last.
  final List<NewsArticle> articles;

  /// sourceId → short reason: "HTTP 404", "timeout after 20 s", …
  final Map<String, String> errors;

  /// sourceId → articles this source contributed to [articles] (0 on error).
  final Map<String, int> counts;

  /// sourceId → items in the feed before filtering. Next to [counts] it
  /// tells "the feed is empty" apart from "everything was stale or live".
  final Map<String, int> seen;

  const FetchReport({
    required this.articles,
    this.errors = const {},
    this.counts = const {},
    this.seen = const {},
  });

  bool get hasErrors => errors.isNotEmpty;
}

class NewsSourceService {
  /// [client] is injectable for tests. Without one, every [fetchAll] opens
  /// its own client and closes it at the end, so no sockets linger between
  /// editions.
  NewsSourceService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const assetPath = 'assets/feed/sources.json';
  static const userAgent = 'LinguaTrace/2.0 (personal reader)';

  /// Older than this is no longer news for a daily edition.
  static const maxAge = Duration(hours: 72);

  /// Real feeds weigh 10 KB–1 MB (the big ones ship article bodies we
  /// drop); anything past 3 MB is a misconfigured endpoint that must not eat
  /// a phone's memory or data plan.
  static const maxBytes = 3 * 1024 * 1024;

  /// Polite to servers and to a mobile radio, still quick for ~10 sources.
  static const maxParallel = 4;

  static const maxLeadChars = 400;

  /// Shorter leads are teasers ("Vídeo del día") with nothing to retell.
  static const minLeadChars = 60;

  // ─────────────────────────────────────────── sources

  /// Parses the sources list (a JSON array of [NewsSource.toJson] objects).
  /// Malformed entries and repeated ids are skipped rather than failing the
  /// whole list — one typo must not silence every source.
  static List<NewsSource> parseSources(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw const FormatException('sources.json: expected a JSON array');
    }
    final ids = <String>{};
    final out = <NewsSource>[];
    for (final e in decoded) {
      if (e is! Map<String, dynamic> || !_isValidSource(e)) continue;
      final source = NewsSource.fromJson(e);
      if (ids.add(source.id)) out.add(source);
    }
    return out;
  }

  static bool _isValidSource(Map<String, dynamic> j) =>
      j['id'] is String &&
      (j['id'] as String).isNotEmpty &&
      j['name'] is String &&
      j['url'] is String &&
      j['lang'] is String &&
      (j['variety'] == null || j['variety'] is String) &&
      (j['topic'] == null || j['topic'] is String) &&
      (j['enabled'] == null || j['enabled'] is bool);

  static Future<List<NewsSource>> loadBundledSources() async =>
      parseSources(await rootBundle.loadString(assetPath));

  // ─────────────────────────────────────────── fetching

  /// Fetches [sources] at most [maxParallel] at a time. Each source gets
  /// [timeout] for the whole download; its failure is recorded in the
  /// report instead of thrown. TLS verification stays on (the platform
  /// default) — there is deliberately no way to switch it off.
  Future<FetchReport> fetchAll(
    List<NewsSource> sources, {
    DateTime? now,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    // The report is keyed by id, so a repeated id would clobber a result.
    final ids = <String>{};
    final queue = [
      for (final s in sources)
        if (ids.add(s.id)) s,
    ];
    final downloads = <String, _Download>{};
    final client = _client ?? http.Client();
    try {
      var next = 0;
      Future<void> worker() async {
        while (next < queue.length) {
          final src = queue[next++];
          downloads[src.id] = await _downloadOne(client, src, timeout);
        }
      }

      final workers =
          queue.length < maxParallel ? queue.length : maxParallel;
      await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    } finally {
      if (_client == null) client.close();
    }

    // Parsing a big feed takes tens of ms, so it runs off the UI isolate —
    // all feeds in one background isolate, because every fresh isolate
    // pays the XML-parser and regex warm-up again.
    final jobs = [
      for (final src in queue)
        if (downloads[src.id]!.bytes case final bytes?)
          _ParseJob(bytes, src, at),
    ];
    final parsed = jobs.isEmpty
        ? const <String, _SourceResult>{}
        : await compute(_parseAllInBackground, jobs);

    // Merge in input order so the dedupe winner is deterministic.
    final articles = <NewsArticle>[];
    final errors = <String, String>{};
    final counts = <String, int>{};
    final seen = <String, int>{};
    final hashes = <String>{};
    for (final src in queue) {
      final download = downloads[src.id]!;
      final r = parsed[src.id] ?? _SourceResult.failed(download.error!);
      seen[src.id] = r.seen;
      if (r.error != null) errors[src.id] = r.error!;
      var added = 0;
      for (final a in r.articles) {
        if (hashes.add(a.urlHash)) {
          articles.add(a);
          added++;
        }
      }
      counts[src.id] = added;
    }
    return FetchReport(
      articles: _newestFirst(articles, at),
      errors: errors,
      counts: counts,
      seen: seen,
    );
  }

  static Future<_Download> _downloadOne(
      http.Client client, NewsSource src, Duration timeout) async {
    final uri = Uri.tryParse(src.url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      return const _Download.failed('invalid feed URL');
    }
    final abort = Completer<void>();
    try {
      return _Download.ok(
          await _download(client, uri, abort.future).timeout(timeout));
    } on TimeoutException {
      return _Download.failed('timeout after ${_seconds(timeout)}');
    } on _FetchError catch (e) {
      return _Download.failed(e.message);
    } on http.ClientException catch (e) {
      return _Download.failed(_short('network: ${e.message}'));
    } catch (e) {
      // TLS, DNS, anything else: one source must never sink the edition.
      return _Download.failed(_short(e.toString()));
    } finally {
      // Releases the socket after a timeout or an early exit (HTTP error,
      // size cap); a no-op once the body has been read completely.
      if (!abort.isCompleted) abort.complete();
    }
  }

  static Future<Uint8List> _download(
      http.Client client, Uri uri, Future<void> abort) async {
    final request = http.AbortableRequest('GET', uri, abortTrigger: abort)
      ..headers['User-Agent'] = userAgent
      ..headers['Accept'] = 'application/rss+xml, application/atom+xml, '
          'application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5';
    // gzip is negotiated and inflated by the platform client.
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw _FetchError('HTTP ${response.statusCode}');
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw const _FetchError('response larger than 3 MB');
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      body.add(chunk);
      if (body.length > maxBytes) {
        throw const _FetchError('response larger than 3 MB');
      }
    }
    return body.takeBytes();
  }

  static String _seconds(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds} s'
      : '${d.inMilliseconds} ms';

  static String _short(String s) =>
      s.length <= 160 ? s : '${s.substring(0, 159)}…';

  // ─────────────────────────────────────────── decoding

  /// Feeds are UTF-8 almost everywhere, and valid UTF-8 wins even over an
  /// ISO-8859-1 prolog — such labels are often stale (the CMS moved to
  /// UTF-8 years ago), while real Latin-1 text with accents is never valid
  /// UTF-8. Invalid bytes that do not claim to be UTF-8 are read as
  /// windows-1252, as browsers read Latin-1 (WHATWG), which also rescues the
  /// curly quotes and dashes pasted in from Word.
  @visibleForTesting
  static String decodeBody(List<int> bytes) {
    var body = bytes;
    if (body.length >= 3 &&
        body[0] == 0xEF &&
        body[1] == 0xBB &&
        body[2] == 0xBF) {
      body = body.sublist(3); // UTF-8 BOM
    }
    try {
      return utf8.decode(body);
    } on FormatException {
      final head = String.fromCharCodes(body.take(256));
      final label =
          _prologEncoding.firstMatch(head)?.group(1)?.toLowerCase() ?? '';
      final latin9 = label == 'iso-8859-15' || label == 'latin9';
      if (latin9 || label.isEmpty || _latin1Labels.contains(label)) {
        return _decodeSingleByte(body, latin9: latin9);
      }
      // Claims UTF-8 (or something exotic): keep the text, mark bad bytes.
      return utf8.decode(body, allowMalformed: true);
    }
  }

  static final _prologEncoding =
      RegExp(r'''^\s*<\?xml[^>]*?encoding\s*=\s*["']([\w.:-]+)["']''');

  static const _latin1Labels = {
    'iso-8859-1', 'iso8859-1', 'iso_8859-1', 'latin1', 'latin-1', 'l1',
    'cp819', 'windows-1252', 'cp1252', 'x-cp1252', 'us-ascii', 'ascii',
  };

  /// windows-1252 in 0x80–0x9F (where ISO-8859-1 has control codes).
  static const _cp1252 = <int>[
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, //
    0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178, //
  ];

  /// ISO-8859-15 differs from Latin-1 in eight places — € above all.
  static const _latin9 = <int, int>{
    0xA4: 0x20AC, 0xA6: 0x0160, 0xA8: 0x0161, 0xB4: 0x017D, //
    0xB8: 0x017E, 0xBC: 0x0152, 0xBD: 0x0153, 0xBE: 0x0178, //
  };

  static String _decodeSingleByte(List<int> bytes, {bool latin9 = false}) {
    final codes = List<int>.filled(bytes.length, 0);
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      codes[i] = b >= 0x80 && b <= 0x9F
          ? _cp1252[b - 0x80]
          : latin9
              ? (_latin9[b] ?? b)
              : b;
    }
    return String.fromCharCodes(codes);
  }

  // ─────────────────────────────────────────── parsing

  /// Makes common breakage parseable without touching well-formed input:
  /// drops C0 control characters (illegal in XML 1.0) and stray BOMs,
  /// escapes a bare `&` that starts no entity ("Tom & Jerry"), and skips
  /// junk before the first tag (PHP notices, blank lines). CDATA stays
  /// verbatim — a bare `&` is legal there.
  @visibleForTesting
  static String sanitizeXml(String xml) {
    var s = xml.replaceAll(_controlChars, '');
    final firstTag = s.indexOf('<');
    if (firstTag > 0) s = s.substring(firstTag);
    if (!s.contains('&')) return s;
    final out = StringBuffer();
    var last = 0;
    for (final m in _cdata.allMatches(s)) {
      out
        ..write(s.substring(last, m.start).replaceAll(_bareAmp, '&amp;'))
        ..write(m[0]);
      last = m.end;
    }
    out.write(s.substring(last).replaceAll(_bareAmp, '&amp;'));
    return out.toString();
  }

  static final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFEFF]');
  static final _cdata = RegExp(r'<!\[CDATA\[[\s\S]*?\]\]>');
  static final _bareAmp = RegExp(
      r'&(?!#[0-9]{1,7};|#[xX][0-9a-fA-F]{1,6};|[A-Za-z][A-Za-z0-9]{1,31};)');

  /// Articles worth retelling from one feed document (RSS 0.9x/1.0/2.0 or
  /// Atom): fresh relative to [now], not live pages, not stubs, not shop
  /// pages, one per canonical URL.
  static List<NewsArticle> parseFeed(String xml, NewsSource src,
          {DateTime? now}) =>
      _parse(xml, src, now).articles;

  static _Parsed _parse(String xml, NewsSource src, DateTime? now) {
    final at = (now ?? DateTime.now()).toUtc();
    final clean = sanitizeXml(xml.replaceAll(_unreadElement, ''));
    final items = <XmlElement>[];
    var total = 0;
    try {
      final doc = XmlDocument.parse(clean);
      items
        ..addAll(doc.findAllElements('item', namespace: '*'))
        ..addAll(doc.findAllElements('entry', namespace: '*'));
      total = items.length;
    } on XmlException {
      // One broken item must not cost the whole source: parse each alone.
      for (final m in _itemBlock.allMatches(clean)) {
        total++;
        try {
          items.add(XmlDocument.parse(m[0]!).rootElement);
        } on XmlException {
          // Only this item is lost.
        }
      }
    }
    final base = Uri.tryParse(src.url);
    final out = <NewsArticle>[];
    final hashes = <String>{};
    for (final el in items) {
      final a = _toArticle(el, src, base, at);
      if (a == null || !_isWorthKeeping(a, at) || !hashes.add(a.urlHash)) {
        continue;
      }
      out.add(a);
    }
    return _Parsed(out, total, total > 0 || _feedRoot.hasMatch(clean));
  }

  /// Elements that are never read are cut before the XML parser has to
  /// build them: the article body (`content:encoded`, Atom `<content>`) is
  /// three quarters of 20minutos' bytes, and El País adds ~9 `media:*`
  /// nodes per item. The 20minutos parse drops from ~0.5 s to ~20 ms, and
  /// the body provably never reaches the parser.
  static final _unreadElement = RegExp(
      r'<(content:encoded|content|media:group|media:content)(?=[\s>/])'
      r'[^>]*?(?:/>|>[\s\S]*?</\1\s*>)');
  static final _itemBlock =
      RegExp(r'<(item|entry)(?:\s[^>]*)?>[\s\S]*?</\1\s*>');
  static final _feedRoot =
      RegExp(r'<(?:rss|feed|rdf:RDF|channel)[\s>]', caseSensitive: false);

  static NewsArticle? _toArticle(
      XmlElement el, NewsSource src, Uri? base, DateTime now) {
    var title = '', link = '', altLink = '', guid = '', atomId = '';
    var description = '', summary = '';
    String? pubDate, dcDate, published, updated;
    final rawCategories = <String>[];
    for (final c in el.childElements) {
      final prefix = c.name.prefix;
      // The feed's own vocabulary, not media:title / itunes:summary / …
      final own = prefix == null || prefix == 'atom';
      switch (c.name.local) {
        case 'title' when own:
          title = c.innerText;
        case 'link' when own:
          final href = c.getAttribute('href');
          if (href == null) {
            if (link.isEmpty) link = c.innerText.trim();
          } else if ((c.getAttribute('rel') ?? 'alternate') == 'alternate' &&
              altLink.isEmpty) {
            altLink = href.trim();
          }
        case 'guid' when own:
          guid = c.innerText.trim();
        case 'id' when own:
          atomId = c.innerText.trim();
        case 'description' when prefix == null:
          description = c.innerText;
        case 'summary' when own:
          summary = c.innerText;
        case 'pubDate' || 'pubdate' when prefix == null:
          pubDate ??= c.innerText;
        case 'date' when prefix == 'dc':
          dcDate ??= c.innerText;
        case 'published':
          published ??= c.innerText;
        case 'updated':
          updated ??= c.innerText;
        case 'category' when own:
          final text = c.innerText.trim();
          rawCategories.add(text.isNotEmpty
              ? text
              : c.getAttribute('label') ?? c.getAttribute('term') ?? '');
        case 'subject' when prefix == 'dc':
          rawCategories.add(c.innerText);
        // content:encoded and <content> carry the article body: never read.
      }
    }

    final rawUrl = [
      link,
      altLink,
      if (_looksHttp(guid)) guid,
      if (_looksHttp(atomId)) atomId,
    ].firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final url = _absoluteUrl(_entities.decode(rawUrl), base);
    if (url == null) return null;

    final headline = cleanText(title);
    var text = _summaryText(description.isNotEmpty ? description : summary);
    // Some feeds open the description with the headline again.
    if (headline.isNotEmpty &&
        text.length > headline.length &&
        text.substring(0, headline.length).toLowerCase() ==
            headline.toLowerCase()) {
      text = text.substring(headline.length).replaceFirst(_leadingJoin, '');
    }

    DateTime? publishedAt;
    for (final raw in [pubDate, dcDate, published, updated]) {
      if (raw == null) continue;
      publishedAt = parseDate(raw);
      if (publishedAt != null) break;
    }
    // Hours ahead is a time-zone slip (sorting caps it at now); days ahead
    // (Clarín has shipped those) is not a date to trust or to rank by.
    if (publishedAt != null && publishedAt.difference(now) > _maxClockSkew) {
      publishedAt = null;
    }

    final canonical = canonicalUrl(url);
    return NewsArticle(
      url: canonical,
      urlHash: _sha1(canonical),
      sourceId: src.id,
      outlet: src.name,
      lang: src.lang,
      variety: src.variety,
      title: headline,
      lead: leadFrom(text),
      categories: _categories(rawCategories),
      publishedAt: publishedAt,
    );
  }

  static final _leadingJoin = RegExp(r'^[\s.:|–—-]+');

  /// The widest real time-zone offset: anything further ahead is bogus.
  static const _maxClockSkew = Duration(hours: 14);

  /// With several paragraphs, the first substantial one is the summary (the
  /// Guardian's standfirst, the text after a photo credit); what follows is
  /// the article itself — not needed, and not ours to keep.
  static String _summaryText(String html) {
    final paragraphs = [
      for (final p in html.split(_paragraphEnd))
        if (cleanText(p) case final text when text.isNotEmpty) text,
    ];
    return paragraphs.firstWhere((p) => p.length >= minLeadChars,
        orElse: () => paragraphs.join(' '));
  }

  static final _paragraphEnd = RegExp(
      r'</(?:p|div|li|h[1-6]|blockquote)\s*>|(?:<br\s*/?>\s*){2,}',
      caseSensitive: false);

  static bool _looksHttp(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  static String? _absoluteUrl(String raw, Uri? base) {
    final trimmed = raw.trim().replaceAll(_ws, '%20');
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final abs = uri.hasScheme ? uri : base?.resolveUri(uri);
    if (abs == null ||
        !(abs.isScheme('http') || abs.isScheme('https')) ||
        abs.host.isEmpty) {
      return null;
    }
    return abs.toString();
  }

  /// Stored joined with '|' (see [NewsArticle.toMap]), hence the swap.
  static List<String> _categories(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final r in raw) {
      final c = cleanText(r).replaceAll('|', '/');
      if (c.isEmpty || c.length > 60 || !seen.add(c.toLowerCase())) continue;
      out.add(c);
      if (out.length == 10) break;
    }
    return out;
  }

  static bool _isWorthKeeping(NewsArticle a, DateTime now) {
    if (_wordCount(a.title) <= 2) return false;
    if (a.lead.length < minLeadChars) return false;
    if (isLivePage(a.title, lead: a.lead, url: a.url)) return false;
    if (_shopUrl.hasMatch(a.url)) return false;
    final at = a.publishedAt;
    return at == null || now.difference(at) <= maxAge;
  }

  static int _wordCount(String s) =>
      s.split(_ws).where(_letterOrDigit.hasMatch).length;

  /// Shopping and branded sections (El País Escaparate, La Vanguardia
  /// Comprar, 20minutos ofertas) are advertising, not news to retell.
  static final _shopUrl = RegExp(
      r'^https?://[^/]+/(?:escaparate|comprar|compras|ofertas|'
      r'ofertas-descuentos|descuentos)(?:/|$)'
      r'|/(?:patrocinado|contenido-patrocinado|branded-content|'
      r'publirreportaje)(?:/|$)',
      caseSensitive: false);

  // Letters of the scripts the sources use: Latin with accents, Greek,
  // Cyrillic. Deliberately not `\p{L}` + `unicode: true`: such a pattern
  // takes ~1 s to compile on first use against non-Latin-1 text, and
  // every isolate (feeds are parsed in a background one) pays it again.
  static const _letters = r'A-Za-z\u00AA\u00B5\u00BA\u00C0-\u00D6'
      r'\u00D8-\u00F6\u00F8-\u024F\u0370-\u03FF\u0400-\u052F';

  /// In [pattern], `‹` and `›` become word boundaries that understand
  /// accented and Cyrillic letters (`\b` is ASCII-only in Dart).
  static RegExp _wordPattern(String pattern) => RegExp(pattern
      .replaceAll('‹', '(?<![${_letters}0-9])')
      .replaceAll('›', '(?![${_letters}0-9])'));

  static final _letterOrDigit = RegExp('[${_letters}0-9]');

  // ─────────────────────────────────────────── live pages

  /// Live blogs are endless update streams, not a story to retell. Besides
  /// headline markers, the lead ("Sigue la última hora…") and the URL slug
  /// (`/live/`, `-en-directo`) catch live pages whose headline reads like a
  /// normal story.
  static bool isLivePage(String title, {String lead = '', String url = ''}) =>
      _liveTitle.hasMatch(title.toLowerCase()) ||
      (lead.isNotEmpty && _liveLead.hasMatch(lead.toLowerCase())) ||
      (url.isNotEmpty && _liveUrl.hasMatch(url));

  // Matched against lowercased text: cheaper than case-insensitive regexes.
  static final _liveTitle = _wordPattern(
    r'‹(?:en vivo|en directo|minuto a minuto|онлайн|прямой эфир|'
    r'прямая трансляция)›'
    r'|‹directo\s*[:|]'
    r'|^\s*(?:🔴|última hora›)'
    // "live" is also a plain verb ("where people live"), so only its
    // live-blog uses count: "Live: …", "… war live: …", "… – live".
    r'|^\s*live›'
    r'|‹live\s*(?:[:|]|updates?›|blog›)'
    r'|[-–—]\s*live\s*$'
    r'|‹as it happened›',
  );

  static final _liveLead = _wordPattern(
    r'^(?:sigue|siga|sigan|consulta|follow|watch)›[^.!?]{0,80}?'
    r'‹(?:en directo|en vivo|minuto a minuto|última hora|live)›'
    r'|^última hora›',
  );

  static final _liveUrl = RegExp(
    r'/live/|/directo/|[/_-](?:en-directo|en-vivo|minuto-a-minuto)'
    r'(?=[/_.?#-]|$)|directo-ultima-hora|ultima-hora-en-directo',
    caseSensitive: false,
  );

  // ─────────────────────────────────────────── text

  static const _entities = XmlDefaultEntityMapping.html5();

  /// HTML fragment (as found in titles and descriptions) → one line of
  /// plain text: drops scripts and captions, "Leer más" links and tags,
  /// decodes entities, collapses whitespace.
  static String cleanText(String html) {
    if (html.isEmpty) return '';
    if (!html.contains('<') && !html.contains('&')) {
      // Plain text (most titles and categories): skip the markup passes.
      return html.replaceAll(_controlChars, '').replaceAll(_ws, ' ').trim();
    }
    var s = html
        .replaceAll(_dropBlocks, ' ')
        .replaceAll(_readMoreLink, ' ')
        .replaceAll(_blockTag, ' ')
        .replaceAll(_anyTag, '');
    s = _entities.decode(s);
    if (_anyTag.hasMatch(s)) {
      // Double-escaped HTML (&amp;lt;p&amp;gt;) surfaces as tags only now.
      s = _entities.decode(
          s.replaceAll(_blockTag, ' ').replaceAll(_anyTag, ''));
    }
    return s.replaceAll(_controlChars, '').replaceAll(_ws, ' ').trim();
  }

  static final _dropBlocks = RegExp(
      r'<(script|style|figcaption)\b[^>]*>[\s\S]*?</\1\s*>',
      caseSensitive: false);
  static final _readMoreLink = RegExp(
      r'<a\b[^>]*>\s*(?:leer|leer más|seguir leyendo|sigue leyendo|'
      r'continuar leyendo|read more|continue reading|читать далее|'
      r'подробнее)\s*[.…»>]*\s*</a\s*>',
      caseSensitive: false);
  static final _blockTag = RegExp(
      r'</?(?:p|br|div|li|ul|ol|h[1-6]|tr|td|th|table|blockquote|section|'
      r'article|figure|header|footer|hr)\b[^>]*>',
      caseSensitive: false);
  static final _anyTag = RegExp(r'<!--[\s\S]*?-->|</?[A-Za-z][^<>]*>');
  // JS-style \s: also NBSP, thin spaces, U+2028 and friends.
  static final _ws = RegExp(r'\s+');

  /// Plain text → lead: at most the first two sentences and [maxLeadChars],
  /// cut on a word boundary with '…'. Trailing "Leer más" and WordPress
  /// footers are removed first.
  static String leadFrom(String text) {
    final t = text
        .replaceAll(_ws, ' ')
        .trim()
        .replaceFirst(_wpFooter, '')
        .replaceFirst(_readMoreTail, '')
        .trim();
    if (t.isEmpty) return '';
    return _truncate(splitSentences(t).take(2).join(' '), maxLeadChars);
  }

  static final _readMoreTail = RegExp(
      r'\s*(?:\[\s*(?:…|\.\.\.)\s*\]|(?:leer más|seguir leyendo|sigue leyendo|'
      r'continuar leyendo|read more|continue reading|читать далее)'
      r'\s*[.…»>]*)\s*$',
      caseSensitive: false);
  static final _wpFooter = RegExp(
      r'\s*(?:The post|La entrada|El artículo) [^\n]{1,300}? '
      r'(?:appeared first on|se publicó primero en) [^\n]{1,120}$');

  /// Splits on . ! ? … followed by a capitalised word, but not after
  /// abbreviations — Spanish news is full of "EE. UU.", "Sr." and initials,
  /// and a lead cut at "EE." would be nonsense.
  static List<String> splitSentences(String text) {
    final out = <String>[];
    var start = 0;
    for (final m in _sentenceBreak.allMatches(text)) {
      if (!_opensSentence(text, m.end)) continue;
      if (m[1] == '.' && _isAbbreviation(text, start, m)) continue;
      // A quotation may hold several sentences: son «la Iglesia de hoy. Y…».
      if (_quoteStillOpen(text, start, m.end)) continue;
      out.add(text.substring(start, m.end).trim());
      start = m.end;
    }
    final rest = text.substring(start).trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static final _sentenceBreak = RegExp(r'''([.!?…]+)["'”’»)\]]*\s+''');
  static final _lastWord = RegExp('([$_letters.]+)\$');
  static final _doubledCapsNext = RegExp(
      r'^\s*([A-Z\u00C0-\u00D6\u00D8-\u00DE\u0391-\u03A9\u0400-\u042F])\1\.');

  static const _openers = '«"“‘\'([¿¡—–-';

  /// « » and “ ” nest; straight double quotes only pair up. Apostrophes are
  /// ignored — in English they are mostly "don't", not quotes. A quote that
  /// never closes (feeds cut descriptions mid-quotation) does not count,
  /// or it would swallow the rest of the text.
  static bool _quoteStillOpen(String text, int from, int to) {
    var guillemets = 0, curly = 0, straight = 0;
    for (var i = from; i < to; i++) {
      switch (text.codeUnitAt(i)) {
        case 0xAB: // «
          guillemets++;
        case 0xBB: // »
          guillemets--;
        case 0x201C: // “
          curly++;
        case 0x201D: // ”
          curly--;
        case 0x22: // "
          straight++;
      }
    }
    return (guillemets > 0 && text.indexOf('»', to) >= 0) ||
        (curly > 0 && text.indexOf('”', to) >= 0) ||
        (straight.isOdd && text.indexOf('"', to) >= 0);
  }

  /// Does a sentence start at [i]: a capital letter or a digit, possibly
  /// after opening quotes, brackets, ¿ or ¡?
  static bool _opensSentence(String text, int i) {
    while (i < text.length && _openers.contains(text[i])) {
      i++;
    }
    if (i >= text.length) return false;
    final c = text[i];
    final unit = c.codeUnitAt(0);
    return (unit >= 0x30 && unit <= 0x39) || c.toLowerCase() != c;
  }

  static bool _isAbbreviation(String text, int start, RegExpMatch m) {
    final w = _lastWord.firstMatch(text.substring(start, m.start))?[1] ?? '';
    if (w.isEmpty) return false; // "… en 2025." is a real end
    if (w.contains('.')) return true; // EE.UU. · a.m. · S.A. · т.е.
    if (w.length == 1) return true; // initials, a. C., d. C.
    // Plural initialisms come in pairs: EE. UU., FF. AA., CC. OO.; the
    // second half ends the sentence normally ("… de EE. UU. El …").
    if (w.length == 2 &&
        w[0] == w[1] &&
        w != w.toLowerCase() &&
        _doubledCapsNext.hasMatch(text.substring(m.end))) {
      return true;
    }
    return _abbreviations.contains(w.toLowerCase());
  }

  static const _abbreviations = {
    // es
    'sr', 'sra', 'srta', 'sres', 'dr', 'dra', 'dres', 'ud', 'uds', 'vd',
    'dña', 'lic', 'ing', 'arq', 'prof', 'gral', 'cnel', 'tte', 'sgto',
    'mons', 'pdte', 'av', 'avda', 'núm', 'pág', 'págs', 'pp', 'ej', 'etc',
    'aprox', 'art', 'arts', 'cía', 'ltda', 'vol', 'tel', 'fig', 'dpto',
    'depto', 'admón', 'sta', 'sto',
    // en
    'mr', 'mrs', 'ms', 'st', 'jr', 'vs', 'inc', 'ltd', 'co', 'corp', 'gov',
    'gen', 'sen', 'rep', 'lt', 'col', 'capt', 'sgt', 'approx', 'dept',
    'jan', 'feb', 'aug', 'sept', 'oct', 'nov', 'dec',
    // ru
    'гг', 'др', 'пр', 'им', 'ул', 'см', 'млн', 'млрд', 'тыс', 'руб',
    'долл', 'стр', 'вв', 'ст', 'проф', 'акад', 'ген',
  };

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    var cut = s.substring(0, max - 1); // room for '…'
    final space = cut.lastIndexOf(' ');
    if (space >= max ~/ 2) {
      cut = cut.substring(0, space);
    } else {
      final last = cut.codeUnitAt(cut.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        cut = cut.substring(0, cut.length - 1); // never split a surrogate pair
      }
    }
    cut = cut.replaceFirst(_dangling, '');
    // Cut right after a full stop: the sentence is complete as it is.
    return _sentenceEnd.hasMatch(cut) ? cut : '$cut…';
  }

  static final _dangling = RegExp(r'''[\s,;:(«"“'‘—–-]+$''');
  static final _sentenceEnd = RegExp(r'''[.!?…]["'”’»)]*$''');

  // ─────────────────────────────────────────── dates

  /// RFC-822 (RSS) and ISO-8601 (Atom, dc:date) → UTC. Tolerates what feeds
  /// really emit: no weekday, no seconds, two-digit years, named zones (GMT,
  /// CEST, EST…), Spanish and Russian month names. Unparseable → null: an
  /// undated item is kept rather than given a guessed date.
  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (_isoStart.hasMatch(s)) {
      final d = DateTime.tryParse(s);
      if (d == null || d.isUtc) return d;
      // No zone designator: feeds mean UTC far more often than device time.
      return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second,
          d.millisecond, d.microsecond);
    }
    return _parseRfc822(s);
  }

  static final _isoStart = RegExp(r'^\d{4}-\d{2}-\d{2}');
  static final _rfc822 = RegExp(
    r'^(?:[^\s\d.,]+\.?,?\s+)?' // weekday in any language: "Sat," "vie.,"
    r'(\d{1,2})\s+([^\s\d.,]+)\.?,?\s+(\d{2,4})' // 26 Sep 2026 · 26 sept. 26
    r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?' // 17:01[:41[.000]]
    r'\s*(?:([+-])(\d{2}):?(\d{2})|([A-Za-z]{1,5}))?', // +0200 · +02:00 · GMT
  );

  static DateTime? _parseRfc822(String s) {
    final m = _rfc822.firstMatch(s);
    if (m == null) return null;
    final monthName = m[2]!.toLowerCase();
    final month = _months[
        monthName.length > 3 ? monthName.substring(0, 3) : monthName];
    final day = int.parse(m[1]!);
    var year = int.parse(m[3]!);
    if (year < 100) year += 2000;
    final hour = int.tryParse(m[4] ?? '') ?? 0;
    final minute = int.tryParse(m[5] ?? '') ?? 0;
    var second = int.tryParse(m[6] ?? '') ?? 0;
    if (month == null || hour > 23 || minute > 59 || second > 60) return null;
    if (second == 60) second = 59; // leap second
    final local = DateTime.utc(year, month, day, hour, minute, second);
    if (local.day != day) return null; // 31 Feb
    int offset;
    if (m[7] != null) {
      offset = int.parse(m[8]!) * 60 + int.parse(m[9]!);
      if (m[7] == '-') offset = -offset;
    } else {
      offset = _zones[(m[10] ?? '').toUpperCase()] ?? 0;
    }
    return local.subtract(Duration(minutes: offset));
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12, //
    'ene': 1, 'abr': 4, 'ago': 8, 'set': 9, 'dic': 12, // es
    'янв': 1, 'фев': 2, 'мар': 3, 'апр': 4, 'май': 5, 'мая': 5, // ru
    'июн': 6, 'июл': 7, 'авг': 8, 'сен': 9, 'окт': 10, 'ноя': 11, 'дек': 12,
  };

  /// Minutes east of UTC. Unknown names count as UTC.
  static const _zones = {
    'Z': 0, 'UT': 0, 'UTC': 0, 'GMT': 0, 'WET': 0, 'WEST': 60, 'BST': 60,
    'CET': 60, 'MET': 60, 'CEST': 120, 'MEST': 120, 'EET': 120,
    'EEST': 180, 'MSK': 180, 'EST': -300, 'EDT': -240, 'CST': -360,
    'CDT': -300, 'MST': -420, 'MDT': -360, 'PST': -480, 'PDT': -420,
    'ART': -180, 'BRT': -180, 'CLT': -240, 'COT': -300, 'PET': -300,
  };

  // ─────────────────────────────────────────── urls

  /// Canonical form used for dedupe: lowercase scheme and host, no
  /// fragment, no tracking parameters (utm_*, BBC's at_*, DW's maca, click
  /// ids). Every outlet appends its own trackers to RSS links, so without
  /// this the same story would come back under several URLs.
  static String canonicalUrl(String url) {
    final raw = url.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return raw;
    final kept = [
      for (final p in uri.query.split('&'))
        if (p.isNotEmpty && !_isTracking(p.split('=').first)) p,
    ];
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: kept.isEmpty ? null : kept.join('&'),
    ).toString();
  }

  /// sha1 hex of [canonicalUrl] — the `news_articles.url_hash` key.
  static String hashUrl(String url) => _sha1(canonicalUrl(url));

  static String _sha1(String canonical) =>
      sha1.convert(utf8.encode(canonical)).toString();

  static bool _isTracking(String key) {
    final k = key.toLowerCase();
    return k.startsWith('utm_') ||
        k.startsWith('at_') ||
        k.startsWith('ns_') ||
        _trackingParams.contains(k);
  }

  static const _trackingParams = {
    'fbclid', 'gclid', 'dclid', 'msclkid', 'yclid', 'igshid', 'mc_cid',
    'mc_eid', 'maca', 'ocid', 'cmpid', '_ga',
  };

  // ─────────────────────────────────────────── picking

  /// Chooses [count] stories for an edition: newest first, but round-robin
  /// across outlets so one prolific site (20minutos posts ~200 items a day)
  /// cannot fill the edition, skipping near-duplicate headlines (Jaccard ≥
  /// 0.5 over lowercase words of ≥ 4 letters) — the same event from five
  /// outlets would make five near-identical items.
  ///
  /// An outlet is the brand prefix of the source id (`elpais-ciencia` →
  /// `elpais`), so an outlet's section feeds share one turn. Articles older
  /// than [maxAge] relative to [now] are skipped; undated ones rank last.
  /// Input order is ignored: callers that must avoid reusing stories should
  /// filter the used ones out before calling.
  static List<NewsArticle> pickStories(
    List<NewsArticle> articles, {
    int count = 12,
    DateTime? now,
  }) {
    if (count <= 0 || articles.isEmpty) return <NewsArticle>[];
    final at = (now ?? DateTime.now()).toUtc();
    final fresh = [
      for (final a in articles)
        if (a.publishedAt == null || at.difference(a.publishedAt!) <= maxAge)
          a,
    ];
    // Insertion order = order of each outlet's newest story.
    final byOutlet = <String, List<NewsArticle>>{};
    for (final a in _newestFirst(fresh, at)) {
      (byOutlet[_outletKey(a)] ??= []).add(a);
    }
    final queues = byOutlet.values.toList();
    final cursor = List<int>.filled(queues.length, 0);

    final picked = <NewsArticle>[];
    final pickedWords = <Set<String>>[];
    final pickedTitles = <String>{};
    final pickedHashes = <String>{};
    bool isDuplicate(NewsArticle a, Set<String> words) =>
        pickedHashes.contains(a.urlHash) ||
        pickedTitles.contains(a.title.toLowerCase()) ||
        pickedWords.any((w) => _jaccard(w, words) >= 0.5);

    while (picked.length < count) {
      // One turn per outlet per round, the freshest candidate first.
      final order = [
        for (var i = 0; i < queues.length; i++)
          if (cursor[i] < queues[i].length) i,
      ]..sort((x, y) {
          final c =
              _compareNewest(queues[x][cursor[x]], queues[y][cursor[y]], at);
          return c != 0 ? c : x.compareTo(y);
        });
      if (order.isEmpty) break;
      for (final i in order) {
        while (cursor[i] < queues[i].length) {
          final a = queues[i][cursor[i]++];
          final words = _titleWords(a.title);
          if (isDuplicate(a, words)) continue;
          picked.add(a);
          pickedWords.add(words);
          pickedTitles.add(a.title.toLowerCase());
          pickedHashes.add(a.urlHash);
          break;
        }
        if (picked.length >= count) break;
      }
    }
    return picked;
  }

  static String _outletKey(NewsArticle a) {
    final id = a.sourceId.trim().toLowerCase();
    if (id.isEmpty) return a.outlet.trim().toLowerCase();
    final dash = id.indexOf('-');
    return dash > 0 ? id.substring(0, dash) : id;
  }

  static final _word = RegExp('[${_letters}0-9]+');

  static Set<String> _titleWords(String title) => {
        for (final m in _word.allMatches(title.toLowerCase()))
          if (m[0]!.length >= 4) m[0]!,
      };

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final shared = a.where(b.contains).length;
    return shared / (a.length + b.length - shared);
  }

  /// Newest first, undated last, stable for ties (List.sort is not stable).
  static List<NewsArticle> _newestFirst(List<NewsArticle> list, DateTime now) {
    final order = List<int>.generate(list.length, (i) => i)
      ..sort((x, y) {
        final c = _compareNewest(list[x], list[y], now);
        return c != 0 ? c : x.compareTo(y);
      });
    return [for (final i in order) list[i]];
  }

  static int _compareNewest(NewsArticle a, NewsArticle b, DateTime now) {
    final da = a.publishedAt, db = b.publishedAt;
    if (da == null || db == null) {
      return da == null ? (db == null ? 0 : 1) : -1;
    }
    // A date in the future is a feed's time-zone slip, not a scoop.
    final ea = da.isAfter(now) ? now : da;
    final eb = db.isAfter(now) ? now : db;
    return eb.compareTo(ea);
  }
}

// ─────────────────────────────────────────── internals

class _SourceResult {
  final List<NewsArticle> articles;
  final int seen;
  final String? error;
  const _SourceResult(this.articles, this.seen) : error = null;
  const _SourceResult.failed(String this.error)
      : articles = const [],
        seen = 0;
}

class _Download {
  final Uint8List? bytes;
  final String? error;
  const _Download.ok(Uint8List this.bytes) : error = null;
  const _Download.failed(String this.error) : bytes = null;
}

class _FetchError implements Exception {
  final String message;
  const _FetchError(this.message);
  @override
  String toString() => message;
}

class _ParseJob {
  final Uint8List bytes;
  final NewsSource source;
  final DateTime now;
  const _ParseJob(this.bytes, this.source, this.now);
}

class _Parsed {
  final List<NewsArticle> articles;
  final int seen;
  final bool isFeed;
  const _Parsed(this.articles, this.seen, this.isFeed);
}

/// Top-level so [compute] can run it in a background isolate.
Map<String, _SourceResult> _parseAllInBackground(List<_ParseJob> jobs) => {
      for (final job in jobs) job.source.id: _parseOne(job),
    };

_SourceResult _parseOne(_ParseJob job) {
  try {
    final parsed = NewsSourceService._parse(
        NewsSourceService.decodeBody(job.bytes), job.source, job.now);
    return parsed.isFeed
        ? _SourceResult(parsed.articles, parsed.seen)
        : const _SourceResult.failed('not an RSS/Atom feed');
  } catch (e) {
    // A parser bug triggered by one feed must not cost the others.
    return _SourceResult.failed(NewsSourceService._short('parse error: $e'));
  }
}
