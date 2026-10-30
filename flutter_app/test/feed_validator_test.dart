import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/models/news_article.dart';
import 'package:lingua_trace/services/feed_validator.dart';

// ─────────────────────────────────────────── fixtures

NewsArticle _article(String id, String outlet, String title, String lead,
        {DateTime? publishedAt}) =>
    NewsArticle(
      url: 'https://example.org/$id',
      urlHash: id,
      sourceId: id,
      outlet: outlet,
      lang: 'es',
      variety: 'es-ES',
      title: title,
      lead: lead,
      publishedAt: publishedAt,
    );

final kSources = [
  _article(
    'elpais',
    'El País',
    'Miles de personas se manifiestan en Madrid para exigir viviendas asequibles',
    'Unas 180.000 personas, según la Delegación del Gobierno, recorrieron '
        'este sábado el centro de Madrid para exigir alquileres más bajos. '
        'Los organizadores, el Sindicato de Inquilinas, elevan la cifra a '
        '300.000 y advierten: «No vamos a parar hasta que bajen los precios».',
    publishedAt: DateTime.utc(2026, 9, 26, 12, 30),
  ),
  _article(
    '20minutos',
    '20minutos',
    'El Gobierno estudia limitar los contratos de temporada',
    'El Ministerio de Vivienda prepara una norma para frenar los alquileres '
        'de temporada, que se han disparado un 15% en el último año.',
  ),
  _article(
    'elmundo',
    'El Mundo',
    'La oposición acusa al Ejecutivo de avivar el conflicto con los caseros',
    'El PP critica que el Gobierno demoniza a los propietarios y pide bajar '
        'impuestos para aumentar la oferta de pisos en alquiler.',
  ),
];

const kTargets = [
  // The reader wrote "no me atrevo decir"; FeedComposer.keyForms keeps the
  // changed fragment with one neighbour each side.
  FeedTargetSpec(
    id: 'T1',
    itemId: 11,
    kind: 'mistake',
    canonical: 'atrevo a decir',
    wrongForm: 'atrevo decir',
    construction: 'atreverse_a_inf',
    gloss: 'осмелиться + инфинитив',
  ),
  FeedTargetSpec(
    id: 'T2',
    itemId: 12,
    kind: 'idiom',
    canonical: 'echar leña al fuego',
    gloss: 'подливать масла в огонь',
  ),
  FeedTargetSpec(
    id: 'T3',
    itemId: 13,
    kind: 'idiom',
    canonical: 'no dar su brazo a torcer',
    gloss: 'не уступать, стоять на своём',
  ),
];

const kHeadline = 'Madrid sale a la calle contra el precio del alquiler';

const kBody =
    'Según informa El País, unas 180.000 personas salieron este sábado a las '
    'calles de Madrid para pedir alquileres más bajos. Esa es la estimación '
    'de la Delegación del Gobierno, mientras que los convocantes hablan de '
    '300.000 asistentes.\n\n'
    'Los convocantes no dieron su brazo a torcer y repitieron su mensaje: '
    '«No vamos a parar hasta que bajen los precios». Una portavoz del '
    'Sindicato de Inquilinas se atrevió a pedir medidas inmediatas para '
    'frenar la subida de los alquileres.\n\n'
    'La marcha llega en plena discusión sobre el precio de la vivienda. '
    'Cualquier gesto brusco del Gobierno o de los propietarios podría echar '
    'leña al fuego, así que ahora todas las miradas están puestas en la '
    'respuesta política.';

const kUsed = [
  DraftTargetUse('T1', 'se atrevió a pedir', 1, 'atreverse a + infinitivo'),
  DraftTargetUse('T2', 'echar leña al fuego', 1, 'обострить конфликт'),
  DraftTargetUse('T3', 'no dieron su brazo a torcer', 1, 'не уступили'),
];

const kChoice = DraftTask(
  kind: 'choice',
  targetId: 'T1',
  promptRu: 'Выберите нужный предлог после «atreverse».',
  text: 'Una portavoz del Sindicato de Inquilinas se atrevió ____ pedir '
      'medidas inmediatas.',
  options: ['a', 'de', 'en'],
  answer: 'a',
);

const kClozeT2 = DraftTask(
  kind: 'cloze',
  targetId: 'T2',
  promptRu: 'Вставьте выражение со значением «подливать масла в огонь».',
  text: 'Cualquier gesto brusco del Gobierno o de los propietarios podría '
      '____, así que ahora todas las miradas están puestas en la respuesta '
      'política.',
  options: [],
  answer: 'echar leña al fuego',
);

const kClozeT3 = DraftTask(
  kind: 'cloze',
  targetId: 'T3',
  promptRu: 'Вставьте выражение «не уступили» в прошедшем времени.',
  text: 'Los convocantes ____ y repitieron su mensaje.',
  options: [],
  answer: 'no dieron su brazo a torcer',
);

const kRetell = DraftTask(
  kind: 'retell',
  targetId: '',
  promptRu: 'Перескажите новость в двух предложениях по-испански, используя '
      'хотя бы одно выражение.',
  text: '',
  options: [],
  answer: 'Miles de personas se manifestaron en Madrid por la vivienda. Los '
      'convocantes no dieron su brazo a torcer.',
);

const kTasks = [kChoice, kClozeT2, kClozeT3, kRetell];

FeedDraft _draft({
  List<String> ids = const ['S1'],
  String headline = kHeadline,
  String body = kBody,
  List<DraftTargetUse> used = kUsed,
  List<(String, String)> skipped = const [],
  List<DraftTask> tasks = kTasks,
}) =>
    FeedDraft(
      storySourceIds: ids,
      headline: headline,
      body: body,
      attribution: 'Según El País (26 sept.)',
      targetsUsed: used,
      skipped: skipped,
      factCheck: const [('unas 180.000 personas', 'S1')],
      tasks: tasks,
    );

ValidationReport _check(
  FeedDraft d, {
  List<FeedTargetSpec> targets = kTargets,
  List<NewsArticle>? sources,
  String lang = 'es',
  int minWords = 90,
  int maxWords = 190,
}) =>
    const FeedValidator().check(d, sources ?? kSources, targets,
        lang: lang, minWords: minWords, maxWords: maxWords);

/// [kBody] with [from] replaced — fails loudly if [from] is not there, so a
/// typo in a test cannot turn into a silently passing no-op.
String _body(String from, String to) {
  expect(kBody, contains(from));
  return kBody.replaceFirst(from, to);
}

void _expectOk(ValidationReport r) =>
    expect(r.violations, isEmpty, reason: r.violations.join('\n'));

/// Exactly one violation, containing every fragment.
void _expectOnly(ValidationReport r, List<String> fragments) {
  expect(r.violations, hasLength(1), reason: r.violations.join('\n'));
  for (final f in fragments) {
    expect(r.violations.single, contains(f));
  }
}

/// Decomposes Spanish accented letters (NFD), as some models emit them.
String _nfd(String s) {
  const map = {
    'á': 'a\u0301',
    'é': 'e\u0301',
    'í': 'i\u0301',
    'ó': 'o\u0301',
    'ú': 'u\u0301',
    'ñ': 'n\u0303',
    'ü': 'u\u0308',
    'Á': 'A\u0301',
    'É': 'E\u0301',
    'Í': 'I\u0301',
    'Ó': 'O\u0301',
    'Ú': 'U\u0301',
    'Ñ': 'N\u0303',
  };
  return s.split('').map((c) => map[c] ?? c).join();
}

void main() {
  group('happy path', () {
    test('a faithful retelling passes with sorted, exact spans', () {
      final r = _check(_draft());
      _expectOk(r);
      expect(r.ok, isTrue);
      expect(r.spans.map((s) => s.targetId), ['T3', 'T1', 'T2']);
      for (final s in r.spans) {
        expect(kBody.substring(s.start, s.end), s.form);
      }
      expect(r.spans.map((s) => s.form), [
        'no dieron su brazo a torcer',
        'se atrevió a pedir',
        'echar leña al fuego',
      ]);
    });

    test('passes with the default length settings too', () {
      _expectOk(const FeedValidator().check(_draft(), kSources, kTargets));
    });

    test(
        'decomposed accents (NFD) in the body still pass, and spans point '
        'at the original UTF-16 code units', () {
      final body = _nfd(kBody);
      expect(body.length, greaterThan(kBody.length));
      final r = _check(_draft(body: body));
      _expectOk(r);
      final t2 = r.spans.firstWhere((s) => s.targetId == 'T2');
      expect(t2.form, 'echar len\u0303a al fuego');
      expect(body.substring(t2.start, t2.end), t2.form);
      final t1 = r.spans.firstWhere((s) => s.targetId == 'T1');
      expect(t1.form, 'se atrevio\u0301 a pedir');
    });
  });

  group('V1 sources, headline, body', () {
    test('empty story_source_ids', () {
      _expectOnly(_check(_draft(ids: [])), ['story_source_ids is empty']);
    });

    test('unknown source id', () {
      _expectOnly(_check(_draft(ids: ['S1', 'S7'])),
          ["story_source_ids has unknown id 'S7'", 'S1–S3']);
    });

    test('lenient id spelling, as FeedComposer resolves ids', () {
      _expectOk(_check(_draft(ids: ['s1'])));
      _expectOk(_check(_draft(ids: [' 1 '])));
    });

    test('empty headline', () {
      _expectOnly(_check(_draft(headline: '  ')), ['headline is empty']);
    });

    test('empty body stops early without spans', () {
      final r = _check(_draft(body: ' \n '));
      expect(r.violations, ['body is empty']);
      expect(r.spans, isEmpty);
    });
  });

  group('V2 length', () {
    test('too short for the requested range', () {
      _expectOnly(_check(_draft(), minWords: 200, maxWords: 300),
          ['body has 115 words', '160–360']);
    });

    test('too long for the requested range', () {
      _expectOnly(_check(_draft(), minWords: 40, maxWords: 60),
          ['body has 115 words', '32–72']);
    });
  });

  group('V3 target bookkeeping', () {
    // A target that is not used has no task either.
    const withoutT3 = [kChoice, kClozeT2, kRetell];

    test('a required target neither used nor skipped', () {
      _expectOnly(_check(_draft(used: kUsed.sublist(0, 2), tasks: withoutT3)),
          ['required target T3', 'neither in targets_used nor in skipped']);
    });

    test('one required target may be skipped with a reason', () {
      _expectOk(_check(_draft(
          used: kUsed.sublist(0, 2),
          skipped: [('T3', 'La noticia no describe ninguna negociación.')],
          tasks: withoutT3)));
    });

    test('a skip needs a reason', () {
      _expectOnly(
          _check(_draft(
              used: kUsed.sublist(0, 2),
              skipped: [('T3', ' ')],
              tasks: withoutT3)),
          ['skipped target T3 needs a one-sentence reason']);
    });

    test('at most one required target may be skipped', () {
      _expectOnly(
          _check(_draft(used: [
            kUsed[0]
          ], skipped: [
            ('T2', 'No hay ningún conflicto que avivar.'),
            ('T3', 'Nadie resiste en esta noticia.'),
          ], tasks: [
            kChoice,
            kRetell
          ])),
          ['2 required targets skipped (T2, T3)', 'at most one']);
    });

    test('a target that was not given cannot be used', () {
      _expectOnly(
          _check(_draft(used: [
            ...kUsed,
            const DraftTargetUse('T9', 'medidas inmediatas', 1, ''),
          ])),
          ["targets_used has unknown target 'T9'", 'given: T1, T2, T3']);
    });

    test('an optional target may be ignored', () {
      _expectOk(_check(_draft(), targets: [
        ...kTargets,
        const FeedTargetSpec(
            id: 'T4',
            itemId: 14,
            kind: 'proverb',
            canonical: 'A quien madruga, Dios le ayuda',
            required: false),
      ]));
    });
  });

  group('V4 spans', () {
    test('a form that is not in the body', () {
      _expectOnly(
          _check(_draft(used: [
            kUsed[0],
            const DraftTargetUse('T2', 'echaron leña al fuego', 1, ''),
            kUsed[2],
          ])),
          ["T2 form_used 'echaron leña al fuego' not found in body"]);
    });

    test('case- and accent-insensitive fallback maps to the body text', () {
      final r = _check(_draft(used: [
        kUsed[0],
        const DraftTargetUse('T2', 'ECHAR LENA AL FUEGO', 1, ''),
        kUsed[2],
      ]));
      _expectOk(r);
      final t2 = r.spans.firstWhere((s) => s.targetId == 'T2');
      expect(t2.form, 'echar leña al fuego');
      expect(kBody.substring(t2.start, t2.end), 'echar leña al fuego');
    });

    test('overlapping spans: the first is kept and the clash reported', () {
      final r = _check(
        _draft(used: [
          ...kUsed,
          const DraftTargetUse('T4', 'leña', 1, ''),
        ]),
        targets: [
          ...kTargets,
          const FeedTargetSpec(
              id: 'T4',
              itemId: 14,
              kind: 'word',
              canonical: 'leña',
              required: false),
        ],
      );
      _expectOnly(r, ["T4 form 'leña' overlaps T2 form 'echar leña al fuego'"]);
      expect(r.spans.map((s) => s.targetId), ['T3', 'T1', 'T2']);
      for (var i = 1; i < r.spans.length; i++) {
        expect(r.spans[i].start, greaterThanOrEqualTo(r.spans[i - 1].end));
      }
    });

    test('the same use listed twice yields one span and no violation', () {
      final r = _check(_draft(used: [...kUsed, kUsed[1]]));
      _expectOk(r);
      expect(r.spans, hasLength(3));
    });
  });

  group('V5 realisation', () {
    test('a partial idiom does not count', () {
      _expectOnly(
          _check(_draft(used: [
            kUsed[0],
            const DraftTargetUse('T2', 'echar leña', 1, ''),
            kUsed[2],
          ])),
          [
            "T2 form_used 'echar leña' does not realise «echar leña al fuego»",
            'missing: fuego'
          ]);
    });

    test('a mistake must reuse the corrected construction', () {
      _expectOnly(
          _check(_draft(used: [
            const DraftTargetUse('T1', 'pedir medidas inmediatas', 1, ''),
            kUsed[1],
            kUsed[2],
          ])),
          [
            "T1 form_used 'pedir medidas inmediatas' does not use the "
                'construction «atrevo a decir»',
            'shares 0 of 2'
          ]);
    });

    test("the reader's wrong form must not appear anywhere", () {
      _expectOnly(
          _check(_draft(
              body: _body(
                  'para frenar la subida de los alquileres.',
                  'para frenar la subida de los alquileres. Nadie se atrevo '
                      'decir nada más.'))),
          ["T1 the reader's wrong form «atrevo decir» appears in the body"]);
    });

    test('accent-only mistakes are compared with accents', () {
      const t5 = FeedTargetSpec(
          id: 'T5',
          itemId: 15,
          kind: 'mistake',
          canonical: 'están puestas',
          wrongForm: 'estan puestas',
          required: false);
      // The correct "están puestas" is in the body: not the wrong form.
      _expectOk(_check(_draft(), targets: [...kTargets, t5]));
      final clozeT2 = DraftTask(
          kind: 'cloze',
          targetId: 'T2',
          promptRu: kClozeT2.promptRu,
          text: kClozeT2.text.replaceFirst('están', 'estan'),
          options: const [],
          answer: kClozeT2.answer);
      _expectOnly(
          _check(
              _draft(
                  body: _body('miradas están puestas', 'miradas estan puestas'),
                  tasks: [kChoice, clozeT2, kClozeT3, kRetell]),
              targets: [...kTargets, t5]),
          ["T5 the reader's wrong form «estan puestas» appears in the body"]);
    });

    test('a whole clause is not a target form', () {
      const clause = 'Cualquier gesto brusco del Gobierno o de los '
          'propietarios podría echar leña al fuego, así que ahora todas las '
          'miradas están puestas en la respuesta política';
      _expectOnly(
          _check(_draft(used: [
            kUsed[0],
            const DraftTargetUse('T2', clause, 1, ''),
            kUsed[2],
          ])),
          ['T2 form_used is 26 words long']);
    });
  });

  group('V6 facts', () {
    test('an invented number', () {
      _expectOnly(
          _check(
              _draft(body: _body('300.000 asistentes', '200.000 asistentes'))),
          ['number 200.000 not in any source']);
    });

    test('thousands separators are normalised', () {
      _expectOk(
          _check(_draft(body: _body('180.000 personas', '180\u00A0000 personas'))));
      _expectOk(
          _check(_draft(body: _body('180.000 personas', '180 000 personas'))));
      _expectOk(
          _check(_draft(body: _body('180.000 personas', '180000 personas'))));
    });

    test('a number from a story that is not cited', () {
      final body = _body(
          'La marcha llega',
          'Además, los contratos de temporada se han disparado un 15%. La '
              'marcha llega');
      _expectOnly(_check(_draft(body: body)),
          ['number 15% appears only in S2, which is not in story_source_ids']);
      _expectOk(_check(_draft(ids: ['S1', 'S2'], body: body)));
    });

    test("the story's date is grounded", () {
      _expectOk(_check(_draft(
          body: _body('La marcha llega',
              'La protesta del 26 de septiembre fue pacífica. La marcha llega'))));
    });

    test('an invented person', () {
      _expectOnly(
          _check(_draft(
              body: _body(
                  'La marcha llega',
                  'La ministra Isabel Rodríguez no quiso comentar la marcha. '
                      'La marcha llega'))),
          [
            "name 'Isabel Rodríguez' not in any source",
            'unknown: Isabel, Rodríguez'
          ]);
    });

    test('a name from a story that is not cited', () {
      _expectOnly(
          _check(_draft(
              body: _body('La marcha llega',
                  'El Ministerio de Vivienda prepara cambios. La marcha llega'))),
          ["name 'Ministerio de Vivienda' appears only in S2"]);
    });

    test('inflected names match on a 5-letter prefix', () {
      _expectOk(_check(_draft(
          body: _body('La marcha llega',
              'El Sindicato de Inquilinos pide diálogo. La marcha llega'))));
    });

    test('a capital at the start of a sentence is not a name', () {
      _expectOk(_check(_draft(
          body: _body('La marcha llega',
              'Hoy Madrid vuelve a hablar de vivienda. La marcha llega'))));
    });

    test('names that are part of a target are exempt', () {
      final body = _body('La marcha llega',
          'Fue la mayor protesta desde Semana Santa. La marcha llega');
      const t4 = FeedTargetSpec(
          id: 'T4',
          itemId: 14,
          kind: 'word',
          canonical: 'Semana Santa',
          required: false);
      _expectOnly(_check(_draft(body: body)),
          ["name 'Semana Santa' not in any source"]);
      // The target expression itself is never an invented name…
      _expectOk(_check(_draft(body: body), targets: [...kTargets, t4]));
      // …and neither is anything inside its span.
      _expectOk(_check(
          _draft(body: body, used: [
            ...kUsed,
            const DraftTargetUse('T4', 'Semana Santa', 1, ''),
          ]),
          targets: [...kTargets, t4]));
    });

    test('a quote must be verbatim; short quoted terms are not quotes', () {
      _expectOnly(
          _check(_draft(
              body: _body('«No vamos a parar hasta que bajen los precios»',
                  '«No pararemos hasta que bajen los precios»'))),
          [
            'quote «No pararemos hasta que bajen los precios» is not verbatim '
                'in any source'
          ]);
      _expectOk(_check(_draft(
          body: _body('la subida de los alquileres',
              'la subida de los «alquileres»'))));
    });

    test('numbers in the headline are checked too', () {
      _expectOnly(
          _check(_draft(
              headline: 'Medio millón de personas piden alquileres '
                  'más bajos, 500.000 según los organizadores')),
          ['headline: number 500.000 not in any source']);
    });
  });

  group('V7 copying', () {
    test('more than 6 consecutive words from a lead', () {
      _expectOnly(
          _check(_draft(
              body: _body(
                  'salieron este sábado a las calles de Madrid para pedir',
                  'recorrieron este sábado el centro de Madrid para exigir'))),
          [
            '12 consecutive words copied from S1 lead: '
                "'recorrieron este sábado el centro de Madrid para exigir "
                "alquileres más bajos'"
          ]);
    });

    test('a verbatim quote is exempt from the copy guard', () {
      // The body shares the 9-word quote with the lead, yet passes.
      expect(FeedValidator.longestSharedRun(kBody, kSources[0].lead),
          greaterThanOrEqualTo(9));
      _expectOk(_check(_draft()));
    });

    test('the headline must be our own', () {
      final r = _check(_draft(headline: kSources[0].title));
      expect(r.violations,
          contains('headline repeats the S1 title; write your own headline'));
    });
  });

  group('V8 attribution', () {
    test('the outlet must be named', () {
      _expectOnly(
          _check(_draft(body: _body('Según informa El País, unas', 'Unas'))),
          ['the body never names the outlet', 'El País']);
    });

    test('case- and accent-insensitive', () {
      _expectOk(
          _check(_draft(body: _body('informa El País', 'informa EL PAIS'))));
    });

    test('spacing variants of an outlet name count', () {
      _expectOk(_check(_draft(
          ids: ['S1', 'S2'],
          body: _body('Según informa El País', 'Según informa 20 Minutos'))));
    });
  });

  group('V9 script', () {
    test('no Cyrillic in a Spanish body', () {
      _expectOnly(
          _check(_draft(
              body:
                  _body('respuesta política.', 'respuesta política (шутка).'))),
          ["body contains Cyrillic text ('шутка')", 'Spanish']);
    });

    test('no Cyrillic in a Spanish headline', () {
      _expectOnly(_check(_draft(headline: 'Madrid sale a la calle — новости')),
          ["headline contains Cyrillic text ('новости')"]);
    });

    test('a Russian item must be mostly Cyrillic', () {
      final r = _check(_draft(), lang: 'ru');
      expect(
          r.violations.where((x) => x.contains('must be written in Russian')),
          hasLength(1),
          reason: r.violations.join('\n'));
    });

    test('Russian text with a Latin outlet name is fine', () {
      final r = _check(
          _draft(
              body: 'По данным El País, в субботу около 180.000 человек вышли '
                  'на улицы Мадрида, требуя снизить арендную плату.'),
          lang: 'ru',
          minWords: 5,
          maxWords: 40);
      expect(
          r.violations
              .where((x) => x.contains('Cyrillic') || x.contains('written in')),
          isEmpty,
          reason: r.violations.join('\n'));
    });
  });

  group('V10 tasks', () {
    test('unknown kind', () {
      _expectOnly(
          _check(_draft(tasks: [
            ...kTasks,
            const DraftTask(
                kind: 'quiz',
                targetId: 'T2',
                promptRu: '?',
                text: '',
                options: [],
                answer: ''),
          ])),
          ["task 5 has unknown kind 'quiz'"]);
    });

    test('exactly one retell', () {
      _expectOnly(_check(_draft(tasks: [kChoice, kClozeT2, kClozeT3])),
          ['exactly one retell task (found 0)']);
      _expectOnly(_check(_draft(tasks: [...kTasks, kRetell])),
          ['exactly one retell task (found 2)']);
    });

    test('a cloze needs one blank', () {
      _expectOnly(
          _check(_draft(tasks: [
            kChoice,
            const DraftTask(
                kind: 'cloze',
                targetId: 'T2',
                promptRu: 'Вставьте выражение.',
                text: 'Cualquier gesto brusco podría complicarlo todo.',
                options: [],
                answer: 'echar leña al fuego'),
            kClozeT3,
            kRetell,
          ])),
          ["task 2 (cloze, T2): text has no '____' blank"]);
      final r = _check(_draft(tasks: [
        kChoice,
        const DraftTask(
            kind: 'cloze',
            targetId: 'T2',
            promptRu: 'Вставьте выражение.',
            text: 'podría ____ leña al ____',
            options: [],
            answer: 'echar'),
        kClozeT3,
        kRetell,
      ]));
      expect(r.violations.any((x) => x.contains('text has 2 blanks')), isTrue,
          reason: r.violations.join('\n'));
    });

    test('a filled cloze must be a sentence of the body', () {
      _expectOnly(
          _check(_draft(tasks: [
            kChoice,
            DraftTask(
                kind: 'cloze',
                targetId: 'T2',
                promptRu: kClozeT2.promptRu,
                text: kClozeT2.text,
                options: [],
                answer: 'echaron leña al fuego'),
            kClozeT3,
            kRetell,
          ])),
          [
            'task 2 (cloze, T2): with the answer filled in',
            'is not a sentence of body'
          ]);
    });

    test('a choice whose answer key restores a different sentence', () {
      _expectOnly(
          _check(_draft(tasks: [
            const DraftTask(
                kind: 'choice',
                targetId: 'T1',
                promptRu: 'Выберите предлог.',
                text: 'Una portavoz del Sindicato de Inquilinas se atrevió '
                    '____ pedir medidas inmediatas.',
                options: ['a', 'de', 'en'],
                answer: 'de'),
            kClozeT2,
            kClozeT3,
            kRetell,
          ])),
          ['task 1 (choice, T1): with the answer filled in']);
    });

    test('a choice answer must be one of the options', () {
      _expectOnly(
          _check(_draft(tasks: [
            DraftTask(
                kind: 'choice',
                targetId: 'T1',
                promptRu: 'Выберите предлог.',
                text: kChoice.text,
                options: ['de', 'en'],
                answer: 'a'),
            kClozeT2,
            kClozeT3,
            kRetell,
          ])),
          [
            "task 1 (choice, T1): answer 'a' is not one of the options "
                "('de', 'en')"
          ]);
    });

    test('a choice has 2–4 options', () {
      DraftTask withOptions(List<String> o) => DraftTask(
          kind: 'choice',
          targetId: 'T1',
          promptRu: 'Выберите предлог.',
          text: kChoice.text,
          options: o,
          answer: 'a');
      _expectOnly(
          _check(_draft(tasks: [
            withOptions(['a']),
            kClozeT2,
            kClozeT3,
            kRetell
          ])),
          ['needs 2–4 options, got 1']);
      _expectOnly(
          _check(_draft(tasks: [
            withOptions(['a', 'de', 'en', 'con', 'por']),
            kClozeT2,
            kClozeT3,
            kRetell,
          ])),
          ['needs 2–4 options, got 5']);
    });

    test('options the grader cannot tell apart', () {
      _expectOnly(
          _check(_draft(tasks: [
            const DraftTask(
                kind: 'choice',
                targetId: 'T1',
                promptRu: 'Выберите предлог.',
                text: 'Una portavoz del Sindicato de Inquilinas se atrevió '
                    '____ pedir medidas inmediatas.',
                options: ['a', 'A.', 'de'],
                answer: 'a'),
            kClozeT2,
            kClozeT3,
            kRetell,
          ])),
          ["options 'a' and 'A.' differ only in case or punctuation"]);
    });

    test('options that differ only in accents are a real choice', () {
      // «esta» / «está» can be the whole point of an accent mistake.
      const t5 = FeedTargetSpec(
          id: 'T5',
          itemId: 15,
          kind: 'mistake',
          canonical: 'están puestas',
          wrongForm: 'estan puestas',
          required: false);
      _expectOk(_check(
          _draft(used: [
            ...kUsed,
            const DraftTargetUse('T5', 'están puestas', 1, ''),
          ], tasks: [
            ...kTasks,
            const DraftTask(
                kind: 'choice',
                targetId: 'T5',
                promptRu: 'Выберите форму глагола estar.',
                text: 'Ahora todas las miradas ____ puestas en la respuesta '
                    'política.',
                options: ['están', 'estan', 'estaban'],
                answer: 'están'),
          ]),
          targets: [...kTargets, t5]));
    });

    test('a gap must be the target, not another word of the sentence', () {
      _expectOnly(
          _check(_draft(tasks: [
            kChoice,
            const DraftTask(
                kind: 'cloze',
                targetId: 'T2',
                promptRu: 'Вставьте пропущенное слово.',
                text: 'Cualquier gesto brusco del ____ o de los propietarios '
                    'podría echar leña al fuego.',
                options: [],
                answer: 'Gobierno'),
            kClozeT3,
            kRetell,
          ])),
          ["the answer 'Gobierno' is not part of T2"]);
    });

    test('every used required target gets a task', () {
      _expectOnly(_check(_draft(tasks: [kChoice, kClozeT2, kRetell])),
          ['T3 is used in body but has no task']);
    });

    test('a task may not practise a target the text does not use', () {
      _expectOnly(
          _check(
              _draft(
                  used: kUsed.sublist(0, 2),
                  skipped: [('T3', 'La noticia no describe ninguna negociación.')]),
              targets: kTargets),
          ['task 3 (cloze, T3): T3 is not used in body']);
    });

    test('prompt_ru must not give the answer away', () {
      _expectOnly(
          _check(_draft(tasks: [
            kChoice,
            DraftTask(
                kind: 'cloze',
                targetId: 'T2',
                promptRu: 'Вставьте «echar leña al fuego» в нужной форме.',
                text: kClozeT2.text,
                options: [],
                answer: 'echar leña al fuego'),
            kClozeT3,
            kRetell,
          ])),
          [
            "task 2 (cloze, T2): prompt_ru gives away the answer "
                "'echar leña al fuego'"
          ]);
    });

    test('quoting the expression in another form is a giveaway too', () {
      DraftTask cloze(DraftTask base, String prompt) => DraftTask(
          kind: 'cloze',
          targetId: base.targetId,
          promptRu: prompt,
          text: base.text,
          options: const [],
          answer: base.answer);
      // Irregular: the prompt has the infinitive, the answer "dieron".
      _expectOnly(
          _check(_draft(tasks: [
            kChoice,
            kClozeT2,
            cloze(kClozeT3,
                'Вставьте «no dar su brazo a torcer» в прошедшем времени.'),
            kRetell,
          ])),
          [
            "task 3 (cloze, T3): prompt_ru gives away the answer "
                "'no dieron su brazo a torcer'"
          ]);
      // Regular, the other way round: the prompt is inflected.
      _expectOnly(
          _check(_draft(tasks: [
            kChoice,
            cloze(kClozeT2, 'Вставьте «echaron leña al fuego» в инфинитиве.'),
            kClozeT3,
            kRetell,
          ])),
          ['task 2 (cloze, T2): prompt_ru gives away the answer']);
      // A single key word is a hint, not the answer.
      _expectOk(_check(_draft(tasks: [
        kChoice,
        cloze(kClozeT2, 'Вставьте идиому со словом «fuego».'),
        kClozeT3,
        kRetell,
      ])));
    });

    test('a choice prompt may list every option, not single one out', () {
      DraftTask withPrompt(String p) => DraftTask(
          kind: 'choice',
          targetId: 'T1',
          promptRu: p,
          text: kChoice.text,
          options: kChoice.options,
          answer: 'a');
      _expectOk(_check(_draft(tasks: [
        withPrompt('Какой предлог после atreverse: a, de или en?'),
        kClozeT2,
        kClozeT3,
        kRetell,
      ])));
      _expectOnly(
          _check(_draft(tasks: [
            withPrompt('Подсказка: после atreverse нужен предлог a.'),
            kClozeT2,
            kClozeT3,
            kRetell,
          ])),
          ["prompt_ru gives away the answer 'a'"]);
    });

    test('a task must point at a given target', () {
      final r = _check(_draft(tasks: [
        kChoice,
        DraftTask(
            kind: 'cloze',
            targetId: 'T8',
            promptRu: kClozeT2.promptRu,
            text: kClozeT2.text,
            options: [],
            answer: 'echar leña al fuego'),
        kClozeT3,
        kRetell,
      ]));
      expect(r.violations, [
        "task 2 (cloze, T8): target_id 'T8' is not one of the given targets",
        'T2 is used in body but has no task; add a cloze task for it',
      ]);
    });

    test('a rephrase needs a sentence to rewrite', () {
      _expectOnly(
          _check(_draft(tasks: [
            ...kTasks,
            const DraftTask(
                kind: 'rephrase',
                targetId: 'T3',
                promptRu: 'Перепишите, используя выражение.',
                text: ' ',
                options: [],
                answer: 'Los inquilinos no dan su brazo a torcer.'),
          ])),
          ['task 5 (rephrase, T3): text is empty']);
    });
  });

  // ─────────────────────────────────────────── shared helpers

  group('fold / nfc / words', () {
    test('fold lowercases and strips precomposed and combining accents', () {
      expect(
          FeedValidator.fold('Echaron LEÑA al Fuego'), 'echaron lena al fuego');
      expect(FeedValidator.fold('len\u0303a'), 'lena');
      expect(FeedValidator.fold('Ёлка'), 'елка');
      expect(FeedValidator.fold('и\u0306'), 'й');
      expect(FeedValidator.fold(' «Hola»\u00A0  mundo '), '"hola" mundo');
    });

    test('nfc composes decomposed Spanish letters', () {
      expect(FeedValidator.nfc('len\u0303a'), 'leña');
      expect(FeedValidator.nfc('atrevio\u0301'), 'atrevió');
      expect(FeedValidator.nfc('leña'), 'leña');
    });

    test('words keeps numbers whole and drops punctuation', () {
      expect(FeedValidator.words('Unas 180.000 personas, ¡sí!'),
          ['unas', '180.000', 'personas', 'si']);
      expect(FeedValidator.wordCount('Unas 180.000 personas, ¡sí!'), 4);
    });
  });

  group('answerMatches', () {
    test('case, punctuation and spacing do not matter', () {
      expect(
          FeedValidator.answerMatches(
              'Echaron leña al fuego', 'echaron leña al fuego'),
          (true, false));
      expect(
          FeedValidator.answerMatches(
              ' ¡echaron  leña al fuego! ', 'echaron leña al fuego'),
          (true, false));
    });

    test('missing accents are accepted but flagged', () {
      expect(
          FeedValidator.answerMatches(
              'echaron lena al fuego', 'echaron leña al fuego'),
          (true, true));
      expect(FeedValidator.answerMatches('se atrevió', 'se atrevio'),
          (true, true));
    });

    test('decomposed input is the same answer', () {
      expect(FeedValidator.answerMatches('len\u0303a', 'leña'), (true, false));
    });

    test('wrong or partial answers fail', () {
      expect(
          FeedValidator.answerMatches('echaron leña', 'echaron leña al fuego'),
          (false, false));
      expect(FeedValidator.answerMatches('', 'a'), (false, false));
      expect(FeedValidator.answerMatches('de', 'a'), (false, false));
    });

    test('alternatives in the expected answer', () {
      expect(
          FeedValidator.answerMatches('echó', 'echaron / echó'), (true, false));
      expect(FeedValidator.answerMatches('echaron', 'echaron|echó'),
          (true, false));
    });

    test('symbol-only options compare as typed', () {
      expect(FeedValidator.answerMatches('—', '—'), (true, false));
      expect(FeedValidator.answerMatches('—', 'a'), (false, false));
    });
  });

  group('locate', () {
    const body = 'La leña ardía. Echaron leña al fuego y luego más leña al '
        'fuego; el leñador miraba.';

    test('exact, by occurrence', () {
      final first = FeedValidator.locate(body, 'leña al fuego')!;
      final second =
          FeedValidator.locate(body, 'leña al fuego', occurrence: 2)!;
      expect(body.substring(first.$1, first.$2), 'leña al fuego');
      expect(second.$1, greaterThan(first.$1));
      expect(body.substring(second.$1, second.$2), 'leña al fuego');
    });

    test('an occurrence beyond the count falls back to the last one', () {
      expect(FeedValidator.locate(body, 'leña al fuego', occurrence: 9),
          FeedValidator.locate(body, 'leña al fuego', occurrence: 2));
    });

    test('whole words are preferred over parts of words', () {
      const text = 'El leñador cortó la leña.';
      final at = FeedValidator.locate(text, 'leña')!;
      expect(at.$1, text.lastIndexOf('leña'));
    });

    test('case- and accent-insensitive fallback in original offsets', () {
      final at = FeedValidator.locate(body, 'echaron lena al fuego')!;
      expect(body.substring(at.$1, at.$2), 'Echaron leña al fuego');
      final nfd = _nfd(body);
      final at2 = FeedValidator.locate(nfd, 'echaron leña al fuego')!;
      expect(nfd.substring(at2.$1, at2.$2), 'Echaron len\u0303a al fuego');
    });

    test('surrounding quotes and punctuation in the form are ignored', () {
      final at = FeedValidator.locate(body, '«echaron leña al fuego»,')!;
      expect(body.substring(at.$1, at.$2), 'Echaron leña al fuego');
    });

    test('absent forms', () {
      expect(FeedValidator.locate(body, 'echar agua al vino'), isNull);
      expect(FeedValidator.locate(body, '  '), isNull);
    });
  });

  group('realises', () {
    test('inflection of regular, irregular and stem-changing verbs', () {
      const cases = {
        'echaron leña al fuego': 'echar leña al fuego',
        'echó más leña al fuego': 'echar leña al fuego',
        'no dio su brazo a torcer': 'no dar su brazo a torcer',
        'no dieron su brazo a torcer': 'no dar su brazo a torcer',
        'se puso las pilas': 'ponerse las pilas',
        'hicieron la vista gorda': 'hacer la vista gorda',
        'tuvo en cuenta': 'tener en cuenta',
        'cierran filas': 'cerrar filas',
        'llevó a cabo': 'llevar a cabo',
        'se atrevió a denunciar': 'atreverse a + infinitivo',
        'tiró la toalla': 'echar/tirar la toalla',
        'se dio cuenta de': 'dar(se) cuenta de algo',
      };
      cases.forEach((form, canonical) {
        expect(FeedValidator.realises(form, canonical), isTrue,
            reason: '"$form" should realise "$canonical"');
      });
    });

    test('other words, missing words or scrambled order do not', () {
      expect(
          FeedValidator.realises(
              'echaron agua al fuego', 'echar leña al fuego'),
          isFalse);
      expect(FeedValidator.realises('leña al fuego', 'echar leña al fuego'),
          isFalse);
      expect(
          FeedValidator.realises(
              'al fuego echaron la leña', 'echar leña al fuego'),
          isFalse);
    });

    test('mistakes: half of the construction in any order', () {
      expect(
          FeedValidator.realises('se atrevió a pedir', 'atrevo a decir',
              kind: 'mistake'),
          isTrue);
      expect(
          FeedValidator.realises('pidió medidas', 'atrevo a decir',
              kind: 'mistake'),
          isFalse);
    });

    test('significant tokens drop stopwords, placeholders and options', () {
      expect(FeedValidator.significantTokens('echar leña al fuego'),
          ['echar', 'lena', 'fuego']);
      expect(FeedValidator.significantTokens('atreverse a + infinitivo'),
          ['atreverse']);
      expect(FeedValidator.significantTokens('dar(se) cuenta de algo'),
          ['dar', 'cuenta']);
      expect(FeedValidator.significantTokens('echar/tirar la toalla'),
          ['echar', 'toalla']);
      expect(FeedValidator.coverage('echar leña', 'echar leña al fuego'),
          closeTo(2 / 3, 1e-9));
    });
  });

  group('numberKeys', () {
    bool same(String a, String b) => FeedValidator.numberKeys(a)
        .intersection(FeedValidator.numberKeys(b, includeWords: true))
        .isNotEmpty;

    test('thousands separators', () {
      expect(same('180.000 personas', '180 000 personas'), isTrue);
      expect(same('180.000', '180000'), isTrue);
      expect(same('180\u00A0000', '180.000'), isTrue);
      expect(same('200.000', '180.000'), isFalse);
    });

    test('decimal comma or point and scale words', () {
      expect(same('1,5 millones', '1.500.000 euros'), isTrue);
      expect(same('1.5 million', '1,5 millones'), isTrue);
      expect(same('2,5 mil', '2.500'), isTrue);
      expect(same('1,5', '15'), isFalse);
    });

    test('percentages, clock times and number words', () {
      expect(same('un 15%', 'un 15 % más'), isTrue);
      expect(same('a las 10.30', 'a las 10:30 horas'), isTrue);
      expect(same('3 heridos', 'tres heridos'), isTrue);
      expect(same('500.000', 'medio millón'), isTrue);
    });

    test('"en 2024 180 casos" is two numbers, not 2024180', () {
      final keys = FeedValidator.numberKeys('en 2024 180 casos');
      expect(keys, containsAll(['2024', '180']));
    });
  });

  group('longestSharedRun', () {
    test('counts words, ignoring case, accents and punctuation', () {
      expect(
          FeedValidator.longestSharedRun(
              'Recorrieron este sábado, el centro de Madrid.',
              'ayer recorrieron este sabado el centro de madrid para'),
          7);
      expect(FeedValidator.longestSharedRun('uno dos tres', 'cuatro cinco'), 0);
    });
  });
}
