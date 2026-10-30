import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/models/news_article.dart';
import 'package:lingua_trace/services/news_source_service.dart';
import 'package:xml/xml.dart';

final now = DateTime.utc(2026, 9, 26, 18);

String fixture(String name) =>
    File('test/fixtures/feeds/$name').readAsStringSync();

const diario = NewsSource(
  id: 'prueba',
  name: 'Diario de Prueba',
  url: 'https://diario.example/rss',
  lang: 'es',
  variety: 'es-ES',
);

/// flutter_test's binding makes every HttpClient answer 400; the stub test
/// needs real sockets (to 127.0.0.1 only).
class _RealHttp extends HttpOverrides {}

void main() {
  group('parseFeed · RSS 2.0 with CDATA and HTML', () {
    late List<NewsArticle> items;
    setUpAll(() => items =
        NewsSourceService.parseFeed(fixture('rss2_cdata.xml'), diario, now: now));

    test('both items, in feed order', () {
      expect(items.map((a) => a.title), [
        'El Gobierno aprueba el plan de vivienda & alquiler',
        'La Luna tendrá su propia zona horaria, según la ESA',
      ]);
    });

    test('lead: tags and "Leer más" stripped, &nbsp; decoded, 2 sentences',
        () {
      expect(
          items[0].lead,
          'El Consejo de Ministros aprobó este martes un plan para ampliar el '
          'parque de vivienda pública en toda España. La medida costará 3.000 '
          'millones de euros.');
    });

    test('content:encoded and media:* are never read', () {
      for (final a in items) {
        expect(a.lead, isNot(contains('CUERPO')));
        expect(a.lead, isNot(contains('multimedia')));
        expect(a.title, isNot(contains('multimedia')));
      }
    });

    test('canonical url and its sha1', () {
      const url = 'https://diario.example/economia/plan-vivienda.html?id=42';
      expect(items[0].url, url);
      expect(items[0].urlHash, sha1.convert(utf8.encode(url)).toString());
    });

    test('RFC-822 date with offset → UTC; categories deduped', () {
      expect(items[0].publishedAt, DateTime.utc(2026, 9, 26, 15, 30));
      expect(items[0].categories, ['Economía', 'Vivienda']);
    });

    test('escaped HTML + dc:date; "EE. UU." is not a sentence end', () {
      expect(
          items[1].lead,
          'La Agencia Espacial Europea propone una hora lunar común para '
          'coordinar las misiones de EE. UU. y Europa. El sistema se probará '
          'en 2028 y servirá a los futuros astronautas.');
      expect(items[1].publishedAt, DateTime.utc(2026, 9, 26, 9, 15));
    });

    test('source metadata is copied onto every article', () {
      for (final a in items) {
        expect(a.sourceId, 'prueba');
        expect(a.outlet, 'Diario de Prueba');
        expect(a.lang, 'es');
        expect(a.variety, 'es-ES');
        expect(a.id, isNull);
      }
    });
  });

  group('parseFeed · Atom', () {
    const revista = NewsSource(
        id: 'revista',
        name: 'Revista',
        url: 'https://revista.example/atom.xml',
        lang: 'es');
    late List<NewsArticle> items;
    setUpAll(() => items =
        NewsSourceService.parseFeed(fixture('atom.xml'), revista, now: now));

    test('alternate link, html title, summary (never <content>)', () {
      expect(items, hasLength(2));
      final a = items[0];
      expect(a.title, 'Madrid estrena carriles bici en la Castellana');
      expect(a.url, 'https://revista.example/madrid/carriles-bici');
      expect(
          a.lead,
          'El Ayuntamiento abre hoy doce kilómetros de carril protegido. '
          'Los ciclistas llevaban una década pidiéndolo.');
      expect(a.lead, isNot(contains('ÍNTEGRO')));
      expect(a.categories, ['Movilidad', 'madrid']);
    });

    test('<published> wins over <updated>', () {
      expect(items[0].publishedAt, DateTime.utc(2026, 9, 26, 8));
    });

    test('relative link resolved against the feed; <updated> as fallback',
        () {
      expect(items[1].url, 'https://revista.example/salud/sueno-memoria');
      expect(items[1].publishedAt, DateTime.utc(2026, 9, 25, 20));
    });
  });

  group('parseFeed · malformed XML', () {
    test('the fixture is invalid XML even after sanitising', () {
      expect(
          () => XmlDocument.parse(
              NewsSourceService.sanitizeXml(fixture('malformed.xml'))),
          throwsA(isA<XmlException>()));
    });

    test('per-item fallback keeps the good items', () {
      final items =
          NewsSourceService.parseFeed(fixture('malformed.xml'), diario, now: now);
      expect(items.map((a) => a.title), [
        'Tom & Jerry vuelven a los cines españoles este otoño',
        'El Ayuntamiento anuncia nuevas líneas de autobús nocturno',
      ]);
      expect(items[0].url, 'https://roto.example/cine/tom-jerry?a=1&b=2');
      expect(items[0].lead, contains('noviembre & promete'));
      expect(items[1].lead,
          startsWith('Las tres nuevas líneas conectarán el centro'));
    });

    test('a broken article body never reaches the parser', () {
      // Invalid XML inside content:encoded would sink this item even in the
      // per-item fallback; bodies are cut before parsing, so it survives.
      const xml = '<rss><channel><item>'
          '<title>El puerto de Vigo bate su récord de contenedores</title>'
          '<link>https://vigo.example/puerto</link>'
          '<description>El tráfico creció un 12 % hasta agosto gracias a las '
          'nuevas líneas con el norte de África.</description>'
          '<content:encoded><p>Cuerpo<br></p></content:encoded>'
          '</item></channel></rss>';
      final items = NewsSourceService.parseFeed(xml, diario, now: now);
      expect(items.map((a) => a.title),
          ['El puerto de Vigo bate su récord de contenedores']);
    });
  });

  group('parseFeed · lead from the summary paragraph', () {
    NewsArticle only(String descriptionHtml) => NewsSourceService.parseFeed(
        '<rss><channel><item><title>Una noticia con varios párrafos</title>'
        '<link>https://p.example/a</link>'
        '<description>${const HtmlEscape().convert(descriptionHtml)}'
        '</description></item></channel></rss>',
        diario,
        now: now).single;

    test('standfirst first, article paragraphs never leak into the lead', () {
      final a = only('<p>Fighting escalates after rebels form a new coalition '
          'aimed at overthrowing the government</p><p>There are growing '
          'fears of a return to civil war. Officials said on Friday.</p>');
      expect(
          a.lead,
          'Fighting escalates after rebels form a new coalition aimed at '
          'overthrowing the government');
    });

    test('a short first paragraph (photo credit) is skipped', () {
      final a = only('<p>Foto: EFE</p><p>El Gobierno aprobó ayer el nuevo '
          'plan de vivienda con una inversión récord.</p>');
      expect(a.lead,
          'El Gobierno aprobó ayer el nuevo plan de vivienda con una inversión récord.');
    });
  });

  group('parseFeed · filters', () {
    late List<NewsArticle> items;
    setUpAll(() => items =
        NewsSourceService.parseFeed(fixture('filters.xml'), diario, now: now));

    test('only the KEEP items survive', () {
      expect(items.map((a) => a.title), [
        'People who live near the volcano return to their homes',
        'Los embalses recuperan agua tras las lluvias de septiembre',
        'Los museos estatales serán gratuitos los domingos',
        'Un informe detalla el estado de las carreteras españolas',
        'Barcelona limita los cruceros en el puerto',
      ]);
    });

    test('72 h is inclusive; an undated item is kept undated', () {
      expect(items[1].publishedAt, now.subtract(const Duration(hours: 72)));
      expect(items[2].publishedAt, isNull);
    });

    test('a long lead is cut to ≤ 400 chars on a word boundary with …', () {
      final full = RegExp(r'<description>(El informe anual[^<]*)</description>')
          .firstMatch(fixture('filters.xml'))![1]!;
      final lead = items[3].lead;
      expect(lead.length, lessThanOrEqualTo(400));
      expect(lead.length, greaterThan(300));
      expect(lead, endsWith('…'));
      final kept = lead.substring(0, lead.length - 1);
      expect(full.startsWith(kept), isTrue);
      expect(full[kept.length], ' ');
    });

    test('a date days ahead is bogus (undated); hours ahead is a TZ slip', () {
      String item(String title, String date) => '<item><title>$title</title>'
          '<link>https://f.example/${Uri.encodeComponent(title)}</link>'
          '<description>Una entradilla suficientemente larga para pasar el '
          'filtro de longitud mínima.</description>'
          '<pubDate>$date</pubDate></item>';
      final items = NewsSourceService.parseFeed(
          '<rss><channel>'
          '${item('Una nota fechada dentro de cuatro días', 'Wed, 30 Sep 2026 09:05:00 +0000')}'
          '${item('Una nota con la hora local marcada como GMT', 'Sat, 26 Sep 2026 20:00:00 GMT')}'
          '</channel></rss>',
          diario,
          now: now);
      expect(items, hasLength(2));
      expect(items[0].publishedAt, isNull);
      expect(items[1].publishedAt, DateTime.utc(2026, 9, 26, 20));
    });

    test('a headline repeated at the start of the description is dropped',
        () {
      expect(
          items[4].lead,
          'El Ayuntamiento reducirá las escalas a la mitad a partir de 2027 '
          'para aliviar la presión turística.');
    });
  });

  group('isLivePage', () {
    test('headline markers', () {
      for (final t in [
        'Guerra en Ucrania, en directo',
        'Elecciones en vivo: sigue el recuento',
        'ÚLTIMA HORA: incendio en Tenerife',
        'Directo: la investidura de la presidenta',
        'Directo | Temporal en el Levante',
        'Minuto a minuto del derbi madrileño',
        '🔴 Temporal en Valencia',
        'Война в Украине. Онлайн',
        'Брифинг Минобороны: онлайн-трансляция',
        'Саммит G20: прямой эфир',
        'Russia-Ukraine war live: Zelensky meets allies',
        'Live: Champions League final',
        'Election results – live',
        'Iran strikes – as it happened',
      ]) {
        expect(NewsSourceService.isLivePage(t), isTrue, reason: t);
      }
    });

    test('ordinary headlines, including "live" as a verb', () {
      for (final t in [
        'People who live near the volcano return home',
        'Olive oil prices fall for the first time in years',
        'Liverpool wins the league',
        'El directorio de empresas crece un 4 %',
        'Pago directo a los agricultores afectados por la sequía',
        'Vivo en Madrid desde hace diez años',
      ]) {
        expect(NewsSourceService.isLivePage(t), isFalse, reason: t);
      }
    });

    test('lead and URL give live pages away too', () {
      expect(
          NewsSourceService.isLivePage('Protesta en Madrid',
              lead: 'Sigue la última hora de la protesta en Madrid.'),
          isTrue);
      expect(
          NewsSourceService.isLivePage('Protesta en Madrid',
              lead: 'Última hora y todas las noticias sobre la protesta.'),
          isTrue);
      expect(
          NewsSourceService.isLivePage('Protesta en Madrid',
              lead: 'Sigue leyendo: miles de personas marchan por la vivienda.'),
          isFalse);
      expect(
          NewsSourceService.isLivePage('Война в Украине',
              url: 'https://www.bbc.co.uk/russian/live/c9p80xp4lgykt'),
          isTrue);
      expect(
          NewsSourceService.isLivePage('Manifestación',
              url: 'https://x.example/politica/manifestacion-hoy-en-directo'),
          isTrue);
      expect(
          NewsSourceService.isLivePage('Pago directo',
              url: 'https://x.example/economia/pago-directo-agricultores'),
          isFalse);
    });
  });

  group('parseDate', () {
    final cases = <String, DateTime>{
      'Sat, 26 Sep 2026 17:01:41 GMT': DateTime.utc(2026, 9, 26, 17, 1, 41),
      'Sat, 26 Sep 2026 17:01:41 +0000': DateTime.utc(2026, 9, 26, 17, 1, 41),
      '26 Sep 2026 17:29:10 +0200': DateTime.utc(2026, 9, 26, 15, 29, 10),
      'Sat, 26 Sep 2026 19:58:28 +0300': DateTime.utc(2026, 9, 26, 16, 58, 28),
      'Sat, 26 Sep 2026 19:58:28 +03:00': DateTime.utc(2026, 9, 26, 16, 58, 28),
      'vie, 25 sept 2026 08:00:00 +0200': DateTime.utc(2026, 9, 25, 6),
      'Viernes, 25 Septiembre 2026 08:00:00 +0200': DateTime.utc(2026, 9, 25, 6),
      'Sat, 26 Sep 26 10:00 CEST': DateTime.utc(2026, 9, 26, 8),
      'Fri, 25 Sep 2026 23:00:00 EST': DateTime.utc(2026, 9, 26, 4),
      'Сб, 26 сен 2026 12:00:00 +0300': DateTime.utc(2026, 9, 26, 9),
      '  Sat, 26 Sep 2026 17:01:41 GMT  ': DateTime.utc(2026, 9, 26, 17, 1, 41),
      '2026-09-26T19:18:00+02:00': DateTime.utc(2026, 9, 26, 17, 18),
      '2026-09-26T12:22:01-05:00': DateTime.utc(2026, 9, 26, 17, 22, 1),
      '2026-09-26T09:15:00Z': DateTime.utc(2026, 9, 26, 9, 15),
      '2026-09-26T09:15:00.123Z': DateTime.utc(2026, 9, 26, 9, 15, 0, 123),
      '2026-09-26 09:15:00': DateTime.utc(2026, 9, 26, 9, 15),
      '2026-09-26': DateTime.utc(2026, 9, 26),
    };
    for (final c in cases.entries) {
      test(c.key.trim(), () {
        final d = NewsSourceService.parseDate(c.key);
        expect(d, c.value);
        expect(d!.isUtc, isTrue);
      });
    }

    test('unparseable → null (item stays undated)', () {
      for (final s in [
        '',
        'ayer',
        '31 Feb 2026 10:00:00 GMT',
        'Sat, 26 Foo 2026 10:00:00 GMT',
        '26 Sep 2026 25:00:00 GMT',
      ]) {
        expect(NewsSourceService.parseDate(s), isNull, reason: s);
      }
    });
  });

  group('canonicalUrl / hashUrl', () {
    test('lowercase scheme and host, no fragment, no trackers', () {
      expect(
          NewsSourceService.canonicalUrl(
              'HTTPS://ElPais.com/Espana/x.html?utm_source=rss&id=5#top'),
          'https://elpais.com/Espana/x.html?id=5');
      expect(
          NewsSourceService.canonicalUrl('https://www.bbc.com/mundo/articles/'
              'crx2zzgjledno?at_medium=RSS&at_campaign=rss'),
          'https://www.bbc.com/mundo/articles/crx2zzgjledno');
      expect(
          NewsSourceService.canonicalUrl('https://www.dw.com/es/misa/a-79445326'
              '?maca=spa-rss-sp-all-1122-xml-mrss'),
          'https://www.dw.com/es/misa/a-79445326');
      expect(NewsSourceService.canonicalUrl('https://x.example/a?'),
          'https://x.example/a');
      expect(NewsSourceService.canonicalUrl('https://x.example:443/a'),
          'https://x.example/a');
      expect(
          NewsSourceService.canonicalUrl(
              'https://x.example/a?b=1&UTM_Source=x&c=%20'),
          'https://x.example/a?b=1&c=%20');
    });

    test('non-ASCII paths are percent-encoded once; idempotent', () {
      final u = NewsSourceService.canonicalUrl(
          'https://www.dw.com/es/misa-en-parís/a-1');
      expect(u, 'https://www.dw.com/es/misa-en-par%C3%ADs/a-1');
      expect(NewsSourceService.canonicalUrl(u), u);
    });

    test('hash = sha1 hex of the canonical form', () {
      expect(NewsSourceService.hashUrl('https://X.example/a?utm_x=1#f'),
          NewsSourceService.hashUrl('https://x.example/a'));
      expect(NewsSourceService.hashUrl('https://x.example/a'),
          sha1.convert(utf8.encode('https://x.example/a')).toString());
      expect(NewsSourceService.hashUrl('https://x.example/b'),
          matches(RegExp(r'^[0-9a-f]{40}$')));
    });
  });

  group('text: cleanText / leadFrom / splitSentences', () {
    test('cleanText strips tags, captions, read-more links; decodes', () {
      expect(
          NewsSourceService.cleanText(
              '<p>Hola&nbsp;<b>mundo</b></p><p>Adiós&#8230;</p>'),
          'Hola mundo Adiós…');
      expect(
          NewsSourceService.cleanText('<figure><img src="x"><figcaption>'
              'Foto: EFE</figcaption></figure><p>Texto real</p>'),
          'Texto real');
      expect(
          NewsSourceService.cleanText(
              'Texto del lead&nbsp;<a href="https://x">Leer</a><img src="y">'),
          'Texto del lead');
      // Double-escaped HTML, as it looks after the XML parser's own decoding.
      expect(
          NewsSourceService.cleanText(
              '&lt;p&gt;Hola &amp;amp; adiós&lt;/p&gt;'),
          'Hola & adiós');
    });

    test('abbreviations, initials and quotes', () {
      expect(
          NewsSourceService.splitSentences(
              'El Sr. García viajó a EE. UU. ayer. La reunión duró dos horas.'),
          ['El Sr. García viajó a EE. UU. ayer.', 'La reunión duró dos horas.']);
      expect(
          NewsSourceService.splitSentences(
              'Viajó a EE. UU. El presidente lo recibió.'),
          ['Viajó a EE. UU.', 'El presidente lo recibió.']);
      expect(
          NewsSourceService.splitSentences(
              'J. K. Rowling publica libro. Sale en marzo.'),
          ['J. K. Rowling publica libro.', 'Sale en marzo.']);
      expect(
          NewsSourceService.splitSentences(
              '¿Qué pasó? Nadie lo sabe. Dijo: «Ya basta». Luego se fue.'),
          ['¿Qué pasó?', 'Nadie lo sabe.', 'Dijo: «Ya basta».', 'Luego se fue.']);
      expect(
          NewsSourceService.splitSentences(
              'Costó 3.000 millones, es decir, 3,5 veces más. Nadie lo esperaba.'),
          ['Costó 3.000 millones, es decir, 3,5 veces más.', 'Nadie lo esperaba.']);
    });

    test('no split inside a quotation', () {
      expect(
          NewsSourceService.splitSentences('Dijo que son "la Iglesia de hoy. '
              'Y el futuro". Luego se fue. Tercera.'),
          [
            'Dijo que son "la Iglesia de hoy. Y el futuro".',
            'Luego se fue.',
            'Tercera.',
          ]);
      expect(
          NewsSourceService.splitSentences(
              'Afirmó: «No cederemos. Nunca». El resto calló.'),
          ['Afirmó: «No cederemos. Nunca».', 'El resto calló.']);
      expect(
          NewsSourceService.splitSentences(
              'Escribió: “Ya basta. Se acabó”. Nadie respondió.'),
          ['Escribió: “Ya basta. Se acabó”.', 'Nadie respondió.']);
    });

    test('a quote that never closes does not swallow the text', () {
      expect(
          NewsSourceService.splitSentences(
              'Dijo que son "la Iglesia de hoy. Tras la misa, se fue. Fin.'),
          ['Dijo que son "la Iglesia de hoy.', 'Tras la misa, se fue.', 'Fin.']);
    });

    test('leadFrom drops read-more tails and WordPress footers', () {
      expect(
          NewsSourceService.leadFrom(
              'Texto de la noticia sobre la economía española. Leer más'),
          'Texto de la noticia sobre la economía española.');
      expect(
          NewsSourceService.leadFrom(
              'Texto de la noticia sobre economía y empleo […]'),
          'Texto de la noticia sobre economía y empleo');
      expect(
          NewsSourceService.leadFrom('Primera frase sobre el clima. '
              'The post Clima extremo appeared first on Blog Verde.'),
          'Primera frase sobre el clima.');
    });

    test('truncation: word boundary, never over 400', () {
      final words = NewsSourceService.leadFrom('palabra ' * 100);
      expect(words.length, lessThanOrEqualTo(400));
      expect(words, endsWith('palabra…'));
      final solid = NewsSourceService.leadFrom('a' * 500);
      expect(solid.length, 400);
      expect(solid, endsWith('…'));
      const short = 'Una frase corta. Otra frase corta.';
      expect(NewsSourceService.leadFrom(short), short);
    });
  });

  group('sanitizeXml / decodeBody', () {
    test('bare & escaped; entities and CDATA untouched', () {
      expect(
          NewsSourceService.sanitizeXml(
              '<a>Tom & Jerry &amp; &#233; &#xE9; &nbsp; &copy;</a>'),
          '<a>Tom &amp; Jerry &amp; &#233; &#xE9; &nbsp; &copy;</a>');
      expect(NewsSourceService.sanitizeXml('<a><![CDATA[a & b]]> & c</a>'),
          '<a><![CDATA[a & b]]> &amp; c</a>');
    });

    test('control characters, BOM and junk before the first tag go', () {
      expect(
          NewsSourceService.sanitizeXml(
              '\uFEFF  junk\n<?xml version="1.0"?><a>x\u0001y\u000Bz\tw</a>'),
          '<?xml version="1.0"?><a>xyz\tw</a>');
    });

    const prolog = '<?xml version="1.0" encoding="ISO-8859-1"?>';

    test('UTF-8 by default, BOM dropped', () {
      expect(
          NewsSourceService.decodeBody(
              [0xEF, 0xBB, 0xBF, ...utf8.encode('<rss>Política</rss>')]),
          '<rss>Política</rss>');
    });

    test('ISO-8859-1 prolog + Latin-1 bytes, read as windows-1252', () {
      final bytes = [
        ...latin1.encode('$prolog<t>Política española '),
        0x93, ...latin1.encode('sí'), 0x94, // curly quotes (cp1252)
        ...latin1.encode('</t>'),
      ];
      expect(NewsSourceService.decodeBody(bytes),
          '$prolog<t>Política española “sí”</t>');
    });

    test('a stale ISO-8859-1 label on UTF-8 bytes is ignored', () {
      expect(
          NewsSourceService.decodeBody(utf8.encode('$prolog<t>Política</t>')),
          '$prolog<t>Política</t>');
    });

    test('undeclared Latin-1 is rescued; declared UTF-8 keeps its text', () {
      expect(
          NewsSourceService.decodeBody(latin1.encode('<t>Política</t>')),
          '<t>Política</t>');
      final bytes = [
        ...utf8.encode('<?xml version="1.0" encoding="UTF-8"?><t>Espa'),
        0xF1, // a lone Latin-1 byte inside a UTF-8 document
        ...utf8.encode('a · Política</t>'),
      ];
      expect(NewsSourceService.decodeBody(bytes),
          endsWith('<t>Espa\uFFFDa · Política</t>'));
    });

    test('ISO-8859-15 has the euro sign at 0xA4', () {
      final bytes = [
        ...latin1.encode(
            '<?xml version="1.0" encoding="ISO-8859-15"?><t>3 caf'),
        0xE9, 0x20, 0xA4, ...latin1.encode('</t>'),
      ];
      expect(NewsSourceService.decodeBody(bytes).endsWith('<t>3 café €</t>'),
          isTrue);
    });
  });

  group('pickStories', () {
    NewsArticle art(String sourceId, String title, Duration ago) {
      final url = 'https://$sourceId.example/${Uri.encodeComponent(title)}';
      return NewsArticle(
        url: url,
        urlHash: NewsSourceService.hashUrl(url),
        sourceId: sourceId,
        outlet: sourceId,
        lang: 'es',
        title: title,
        lead: 'Una entradilla suficientemente larga para pasar los filtros.',
        publishedAt: now.subtract(ago),
      );
    }

    Duration h(num hours) => Duration(minutes: (hours * 60).round());

    test('round-robin across outlets, newest first, near-duplicates skipped',
        () {
      const veinte = [
        'Madrid amplía el horario del metro los fines de semana',
        'Sevilla prepara la Bienal de Flamenco más larga',
        'Valencia inaugura un nuevo parque junto al puerto',
        'Bilbao acoge un congreso internacional de robótica',
        'Zaragoza renueva su flota de autobuses eléctricos',
        'Málaga bate su récord de visitantes en septiembre',
      ];
      final pool = [
        for (var i = 0; i < veinte.length; i++)
          art('20minutos', veinte[i], h(i + 1)),
        art('elpais', 'Los precios del alquiler suben otra vez', h(2.5)),
        art('elpais', 'El Congreso debate la reforma fiscal', h(7)),
        art('elpais-ciencia', 'Descubren un exoplaneta con agua', h(1.5)),
        // Same event as the first 20minutos story → near-duplicate.
        art('bbc-mundo',
            'Madrid amplía el horario del metro durante los fines de semana',
            h(3)),
        art('dw-es', 'Una noticia demasiado antigua para hoy', h(80)),
      ];
      final picked = NewsSourceService.pickStories(pool, count: 5, now: now);
      expect(picked.map((a) => a.sourceId), [
        '20minutos',
        'elpais-ciencia', // same brand as elpais: one turn for both
        '20minutos',
        'elpais',
        '20minutos',
      ]);
      expect(picked.any((a) => a.sourceId == 'bbc-mundo'), isFalse);
      expect(picked.any((a) => a.sourceId == 'dw-es'), isFalse);
    });

    test('no outlet dominates while others still have stories', () {
      var n = 0;
      final pool = [
        for (final src in ['aaa', 'bbb', 'ccc'])
          for (var i = 0; i < 5; i++)
            // Unique long words per title: no accidental near-duplicates.
            art(src, 'Titular alfa${++n} beta$n gamma$n',
                h(i + (src == 'aaa' ? 0 : 0.5))),
      ];
      final picked = NewsSourceService.pickStories(pool, count: 6, now: now);
      expect(picked, hasLength(6));
      for (final src in ['aaa', 'bbb', 'ccc']) {
        expect(picked.where((a) => a.sourceId == src), hasLength(2),
            reason: src);
      }
      expect(picked.first.sourceId, 'aaa'); // freshest outlet starts
    });

    test('Jaccard threshold: ≥ 0.5 skipped, low overlap kept', () {
      final a = art('uno', 'Trump rechaza la oferta de Irán para reabrir el '
          'estrecho de Ormuz', h(1));
      final dup = art('dos', 'Trump rechaza el plan de Irán para reabrir Ormuz',
          h(2));
      final other = art('tres', 'Trump visita Japón para reunirse con su '
          'primer ministro', h(3));
      final picked = NewsSourceService.pickStories([a, dup, other], now: now);
      expect(picked, [a, other]);
    });

    test('undated last, future dates capped at now, count respected', () {
      final undated = NewsArticle(
        url: 'https://sin.example/fecha',
        urlHash: NewsSourceService.hashUrl('https://sin.example/fecha'),
        sourceId: 'sin',
        outlet: 'Sin fecha',
        lang: 'es',
        title: 'Un artículo sin fecha de publicación',
        lead: 'x' * 80,
      );
      final future = art('futuro', 'Una hora mal puesta en el feed', h(-5));
      final recent = art('reciente', 'Una noticia de hace media hora', h(0.5));
      final picked = NewsSourceService.pickStories([undated, recent, future],
          count: 10, now: now);
      expect(picked, [future, recent, undated]);
      expect(NewsSourceService.pickStories([recent], count: 0, now: now),
          isEmpty);
      expect(NewsSourceService.pickStories(const [], now: now), isEmpty);
    });
  });

  group('fetchAll · local HTTP stub (no internet)', () {
    late HttpServer server;
    late Completer<void> firstWave;
    var inFlight = 0, maxInFlight = 0;
    final agents = <String>{};

    setUp(() async {
      firstWave = Completer<void>();
      inFlight = 0;
      maxInFlight = 0;
      agents.clear();
      final rss = utf8.encode(fixture('rss2_cdata.xml'));
      final atom = utf8.encode(fixture('atom.xml'));
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response;
        try {
          agents.add(req.headers.value(HttpHeaders.userAgentHeader) ?? '');
          // Counted only before any byte is sent back, so a request the
          // client already gave up on can never inflate the number. The
          // first wave is held together so that the parallelism shows even
          // on a busy machine.
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          if (inFlight >= NewsSourceService.maxParallel &&
              !firstWave.isCompleted) {
            firstWave.complete();
          }
          await Future.any([
            firstWave.future,
            Future<void>.delayed(const Duration(seconds: 3)),
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          inFlight--;
          switch (req.uri.path) {
            case '/rss-gzip.xml':
              res.headers
                ..set(HttpHeaders.contentTypeHeader, 'application/rss+xml')
                ..set(HttpHeaders.contentEncodingHeader, 'gzip');
              res.add(gzip.encode(rss));
            case '/rss-copy.xml':
              res.add(rss);
            case '/atom.xml':
              res.add(atom);
            case '/missing.xml':
              res.statusCode = HttpStatus.notFound;
            case '/page.html':
              res.headers.contentType = ContentType.html;
              res.add(utf8.encode('<!DOCTYPE html><html><body><p>Hola</p>'
                  '</body></html>'));
            case '/huge.xml':
              res.add(utf8.encode('<?xml version="1.0"?><rss><channel>'));
              final chunk = List<int>.filled(64 * 1024, 0x20);
              for (var i = 0; i < 60; i++) {
                res.add(chunk); // ~3.75 MB, chunked: no Content-Length
                await res.flush();
              }
            case '/slow.xml':
              await Future<void>.delayed(const Duration(seconds: 3));
              res.add(rss);
          }
          await res.close();
        } catch (_) {
          // The client hung up (size cap, timeout): expected here.
        }
      });
    });

    tearDown(() => server.close(force: true));

    NewsSource stub(String id, String path) => NewsSource(
        id: id, name: id, url: 'http://127.0.0.1:${server.port}$path', lang: 'es');

    Future<FetchReport> fetch(List<NewsSource> sources, Duration timeout) =>
        HttpOverrides.runWithHttpOverrides(
          () => NewsSourceService()
              .fetchAll(sources, now: now, timeout: timeout),
          _RealHttp(),
        );

    test('≤ 4 in parallel, UA, gzip, per-source errors, cross-source dedupe',
        () async {
      final report = await fetch([
        stub('gzip', '/rss-gzip.xml'),
        stub('copy', '/rss-copy.xml'), // same items as 'gzip'
        stub('atom', '/atom.xml'),
        stub('missing', '/missing.xml'),
        stub('page', '/page.html'),
        stub('huge', '/huge.xml'),
        stub('atom', '/atom.xml'), // repeated id: ignored
        const NewsSource(id: 'bad', name: 'bad', url: 'notaurl', lang: 'es'),
      ], const Duration(seconds: 20));

      expect(maxInFlight, NewsSourceService.maxParallel);
      expect(agents, {'LinguaTrace/2.0 (personal reader)'});

      expect(report.errors, {
        'missing': 'HTTP 404',
        'page': 'not an RSS/Atom feed',
        'huge': 'response larger than 3 MB',
        'bad': 'invalid feed URL',
      });
      expect(report.counts, {
        'gzip': 2, 'copy': 0, 'atom': 2, 'missing': 0, 'page': 0, 'huge': 0,
        'bad': 0,
      });
      expect(report.seen['copy'], 2);
      expect(report.articles, hasLength(4));
      expect(report.articles.map((a) => a.sourceId).toSet(), {'gzip', 'atom'});
      final dates = [for (final a in report.articles) a.publishedAt!];
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i].isAfter(dates[i - 1]), isFalse);
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a source slower than the timeout is reported, not awaited', () async {
      final watch = Stopwatch()..start();
      final report = await fetch([stub('slow', '/slow.xml')],
          const Duration(milliseconds: 500));
      expect(report.errors, {'slow': 'timeout after 500 ms'});
      expect(report.articles, isEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('an empty source list is an empty report', () async {
      final report = await NewsSourceService().fetchAll(const []);
      expect(report.articles, isEmpty);
      expect(report.hasErrors, isFalse);
    });
  });

  // Last: initialising the test binding swaps in a 400-only HttpClient.
  group('sources.json', () {
    final raw = File('assets/feed/sources.json').readAsStringSync();

    test('bundled list is valid; 8 Spanish sources enabled by default', () {
      final all = NewsSourceService.parseSources(raw);
      expect(all, hasLength((jsonDecode(raw) as List).length));
      expect(all.map((s) => s.id).toSet(), hasLength(all.length));
      for (final s in all) {
        expect(Uri.parse(s.url).scheme, 'https', reason: s.id);
        expect(['es', 'ru', 'en'], contains(s.lang), reason: s.id);
        expect(s.variety, isNotEmpty, reason: s.id);
        expect(s.name, isNotEmpty, reason: s.id);
      }
      final enabled = all.where((s) => s.enabledByDefault).toList();
      expect(enabled.map((s) => s.id), [
        'elpais', '20minutos', 'elmundo', 'lavanguardia', 'elconfidencial',
        'bbc-mundo', 'dw-es', 'rfi-es',
      ]);
      expect(enabled.every((s) => s.lang == 'es'), isTrue);
    });

    test('parseSources skips malformed entries and repeated ids', () {
      final sources = NewsSourceService.parseSources(jsonEncode([
        {'id': 'a', 'name': 'A', 'url': 'https://a.example/rss', 'lang': 'es'},
        {'id': 'b', 'name': 'B', 'lang': 'es'}, // no url
        {'id': 'a', 'name': 'A2', 'url': 'https://a2.example', 'lang': 'es'},
        {'id': 'c', 'name': 'C', 'url': 'https://c.example', 'lang': 'es',
         'enabled': 'yes'}, // wrong type
        'not an object',
        {'id': 'd', 'name': 'D', 'url': 'https://d.example', 'lang': 'ru',
         'enabled': false, 'topic': 'ciencia'},
      ]));
      expect(sources.map((s) => s.id), ['a', 'd']);
      expect(sources[0].name, 'A');
      expect(sources[1].enabledByDefault, isFalse);
      expect(sources[1].topic, 'ciencia');
      expect(() => NewsSourceService.parseSources('{"id": "x"}'),
          throwsFormatException);
    });

    test('loadBundledSources reads the asset bundle', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bundled = await NewsSourceService.loadBundledSources();
      expect(bundled.map((s) => s.id),
          NewsSourceService.parseSources(raw).map((s) => s.id));
    });
  });
}
