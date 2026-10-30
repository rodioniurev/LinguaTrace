/// A news source (RSS/Atom feed) and one item harvested from it.
///
/// Only the headline and a short lead (≤ 400 chars, HTML-stripped) are ever
/// stored or sent to a model — never the article body (copyright, and the
/// feed item is an original retelling with attribution and a link).
library;

import 'dart:convert';

class NewsSource {
  final String id; // stable key, e.g. 'elpais'
  final String name; // display name, e.g. 'El País'
  final String url;
  final String lang; // ISO 639-1 of the texts: es | ru | en
  final String variety; // es-ES | es-419 | es-AR | es-CO | es-MX | ru | en-GB | en-US
  final String topic; // general | ciencia | tecnologia | cultura | economia | …
  final bool enabledByDefault;

  const NewsSource({
    required this.id,
    required this.name,
    required this.url,
    required this.lang,
    this.variety = '',
    this.topic = 'general',
    this.enabledByDefault = true,
  });

  factory NewsSource.fromJson(Map<String, dynamic> j) => NewsSource(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        lang: j['lang'] as String,
        variety: j['variety'] as String? ?? '',
        topic: j['topic'] as String? ?? 'general',
        enabledByDefault: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lang': lang,
        'variety': variety,
        'topic': topic,
        'enabled': enabledByDefault,
      };
}

class NewsArticle {
  final int? id;
  final String url;
  final String urlHash; // sha1 hex of the canonical URL (dedupe key)
  final String sourceId;
  final String outlet; // display name of the source
  final String lang;
  final String variety;
  final String title;
  final String lead; // ≤ 400 chars, plain text
  final List<String> categories;
  final DateTime? publishedAt;

  const NewsArticle({
    this.id,
    required this.url,
    required this.urlHash,
    required this.sourceId,
    required this.outlet,
    required this.lang,
    this.variety = '',
    required this.title,
    required this.lead,
    this.categories = const [],
    this.publishedAt,
  });

  NewsArticle withId(int newId) => NewsArticle(
        id: newId,
        url: url,
        urlHash: urlHash,
        sourceId: sourceId,
        outlet: outlet,
        lang: lang,
        variety: variety,
        title: title,
        lead: lead,
        categories: categories,
        publishedAt: publishedAt,
      );

  factory NewsArticle.fromMap(Map<String, dynamic> m) => NewsArticle(
        id: m['id'] as int?,
        url: m['url'] as String? ?? '',
        urlHash: m['url_hash'] as String? ?? '',
        sourceId: m['source_id'] as String? ?? '',
        outlet: m['outlet'] as String? ?? '',
        lang: m['lang'] as String? ?? '',
        variety: m['variety'] as String? ?? '',
        title: m['title'] as String? ?? '',
        lead: m['lead'] as String? ?? '',
        categories: ((m['categories'] as String?) ?? '')
            .split('|')
            .where((c) => c.isNotEmpty)
            .toList(),
        publishedAt: DateTime.tryParse(m['published_at'] as String? ?? ''),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'url': url,
        'url_hash': urlHash,
        'source_id': sourceId,
        'outlet': outlet,
        'lang': lang,
        'variety': variety,
        'title': title,
        'lead': lead,
        'categories': categories.join('|'),
        // Always UTC so SQL string comparisons of freshness are correct.
        'published_at': publishedAt?.toUtc().toIso8601String(),
      };

  String toJsonString() => jsonEncode(toMap());
}
