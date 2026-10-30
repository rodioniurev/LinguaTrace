/// Structural and consistency checks for the cold-start seed list:
/// field values from the closed sets, unique keys, and — the one that
/// catches real mistakes — every example sentence actually realises its
/// searchForm (verb inflected, the rest fixed, in order).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/seed_idioms.dart';

String _fold(String s) {
  const from = 'áéíóúüÁÉÍÓÚÜ';
  const to = 'aeiouuAEIOUU';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().toLowerCase();
}

List<String> _words(String s) => _fold(s)
    .replaceAll(RegExp(r'[^a-zñ0-9]+'), ' ')
    .trim()
    .split(' ')
    .where((w) => w.isNotEmpty)
    .toList();

/// Stems that inflected forms of the verbs used in the list start with.
/// Irregular ones spelled out; regular ones fall back to infinitive − 2.
const _stems = <String, List<String>>{
  'dar': ['da', 'de', 'di', 'do'],
  'poner': ['pon', 'pus', 'puest'],
  'hacer': ['hac', 'hic', 'hiz', 'hech', 'har', 'hag'],
  'tener': ['ten', 'tien', 'tuv', 'tendr', 'teng'],
  'cerrar': ['cerr', 'cierr'],
  'mover': ['mov', 'muev'],
  'rendir': ['rend', 'rind'],
  'salir': ['sal'],
  'sacar': ['sac', 'saq'],
  'tocar': ['toc', 'toq'],
};

bool _isInfinitive(String w) => RegExp(r'(ar|er|ir)(se)?$').hasMatch(w);

/// True if [text] contains [searchForm]: optional leading verb (any
/// inflection, clitic «se» may precede it), then the fixed tail in order,
/// allowing up to 4 words (a direct object) between verb and tail.
bool realises(String searchForm, String text) {
  final sf = _words(searchForm);
  final tw = _words(text);
  var verb = '';
  var tail = sf;
  if (sf.length > 1 && _isInfinitive(sf.first) && sf.first != 'a') {
    verb = sf.first.endsWith('se') && sf.first.length > 4
        ? sf.first.substring(0, sf.first.length - 2)
        : sf.first;
    tail = sf.sublist(1);
  }
  bool tailAt(int i) {
    if (i + tail.length > tw.length) return false;
    for (var k = 0; k < tail.length; k++) {
      if (tw[i + k] != tail[k]) return false;
    }
    return true;
  }

  final stems = _stems[verb] ??
      (verb.isEmpty ? const <String>[] : [verb.substring(0, verb.length - 2)]);
  for (var i = 0; i < tw.length; i++) {
    if (!tailAt(i)) continue;
    if (verb.isEmpty) return true;
    for (var j = i - 1; j >= 0 && j >= i - 5; j--) {
      if (stems.any((s) => tw[j].startsWith(s))) return true;
    }
  }
  return false;
}

void main() {
  const list = kSeedExpressionsEs;

  test('size and mix as specified (50–70; idioms and collocations)', () {
    expect(list.length, inInclusiveRange(50, 70));
    final idioms = list.where((s) => s.kind == 'idiom').length;
    final colls = list.where((s) => s.kind == 'collocation').length;
    expect(idioms + colls, list.length);
    expect(idioms, greaterThanOrEqualTo(35));
    expect(colls, greaterThanOrEqualTo(20));
  });

  test('closed-set fields', () {
    for (final s in list) {
      expect(['neutral', 'coloquial', 'culto'], contains(s.register),
          reason: s.canonical);
      expect(['', 'es-ES'], contains(s.region), reason: s.canonical);
    }
    // Mostly neutral register, as the feed is news prose.
    final neutral = list.where((s) => s.register == 'neutral').length;
    expect(neutral / list.length, greaterThan(0.7));
  });

  test('no empty or untidy strings', () {
    for (final s in list) {
      for (final f in [s.canonical, s.searchForm, s.glossRu, s.example]) {
        expect(f.trim(), f, reason: 'whitespace: $f');
        expect(f, isNotEmpty);
        expect(f.contains('  '), isFalse, reason: 'double space: $f');
      }
      expect(s.searchForm, s.searchForm.toLowerCase(), reason: s.searchForm);
      expect(RegExp(r'[а-яё]', caseSensitive: false).hasMatch(s.glossRu),
          isTrue,
          reason: 'gloss must be Russian: ${s.glossRu}');
      expect(RegExp(r'^[A-ZÁÉÍÓÚÑ¿¡]').hasMatch(s.example), isTrue,
          reason: s.example);
      expect(s.example.endsWith('.'), isTrue, reason: s.example);
      expect(_words(s.example).length, lessThanOrEqualTo(20),
          reason: 'keep examples short: ${s.example}');
    }
  });

  test('searchForm is a unique key (it becomes the learning item text)', () {
    final seen = <String>{};
    for (final s in list) {
      expect(seen.add(_fold(s.searchForm)), isTrue,
          reason: 'duplicate ${s.searchForm}');
    }
  });

  test('canonical contains the searchForm words', () {
    for (final s in list) {
      expect(realises(s.searchForm, s.canonical.replaceAll(RegExp(r'[()]'), '')),
          isTrue,
          reason: '${s.canonical} ⊅ ${s.searchForm}');
    }
  });

  test('every example realises its searchForm', () {
    for (final s in list) {
      expect(realises(s.searchForm, s.example), isTrue,
          reason: '«${s.example}» does not contain «${s.searchForm}»');
    }
  });

  test('known traps are taught in their correct form', () {
    String? form(String sf) =>
        list.where((s) => s.searchForm == sf).firstOrNull?.searchForm;
    // DPD: «contra reloj», never «a contrarreloj».
    expect(form('contra reloj'), isNotNull);
    expect(list.any((s) => _fold(s.example).contains('a contrarreloj')), isFalse);
    // DPD/FundéuRAE: «hacer agua» (not «hacer aguas» = orinar).
    expect(form('hacer agua'), isNotNull);
    expect(list.any((s) => s.searchForm.contains('aguas')), isFalse);
    // «en el marco de» is singular (калька «в рамках» → *en los marcos).
    expect(list.any((s) => _fold(s.example).contains('los marcos')), isFalse);
  });

  test('matcher sanity (so the test above means something)', () {
    expect(realises('dar luz verde', 'El pleno dio luz verde al plan.'), isTrue);
    expect(realises('poner sobre la mesa',
        'Pone una propuesta sobre la mesa.'), isTrue);
    expect(realises('lavarse las manos', 'Se lava las manos.'), isTrue);
    expect(realises('dar luz verde', 'Hay luz verde en el cruce.'), isFalse);
    expect(realises('en punto muerto', 'Sigue en un punto muerto.'), isFalse);
  });
}
