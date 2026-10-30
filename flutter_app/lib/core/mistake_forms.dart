/// How a corrected mistake becomes a learning item and a feed target.
///
/// The corrector returns the SHORTEST wrong fragment, so a fix is often a
/// lone function word ("a" → "el"). As a learning item that says nothing:
/// every «el» mistake would merge into one item, and no text could ever be
/// checked for it (almost every Spanish sentence contains "el"). Such fixes
/// are widened with their neighbours from the sentence the user wrote
/// ("Llegaré a 18" → "Llegaré el 18").
///
/// A PATTERN mistake is one whose correction adds function words (a missing
/// «a» after atreverse, «el» before a date). The feed reuses it with other
/// words, pinned to an anchor: the governing verb before the added word, or
/// the word (a number for a number) after it.
library;

/// Spanish function words: articles, prepositions, clitics, possessives,
/// conjunctions and the copulas a Russian speaker confuses.
const kFunctionWordsEs = {
  'a',
  'al',
  'el',
  'la',
  'los',
  'las',
  'lo',
  'le',
  'les',
  'un',
  'una',
  'unos',
  'unas',
  'en',
  'de',
  'del',
  'por',
  'para',
  'con',
  'sin',
  'se',
  'que',
  'me',
  'te',
  'nos',
  'os',
  'su',
  'sus',
  'mi',
  'mis',
  'tu',
  'tus',
  'y',
  'e',
  'o',
  'u',
  'ni',
  'no',
  'hay',
  'es',
  'está',
  'son',
  'están',
};

bool isFunctionWord(String w) => kFunctionWordsEs.contains(w.toLowerCase());

class _Tok {
  final int start;
  final int end;
  final String text;
  const _Tok(this.start, this.end, this.text);
}

// Latin letters with Spanish diacritics, digits; "14:15", "1.500" stay one
// word.
final _wordRe =
    RegExp(r"[0-9A-Za-zÀ-ÖØ-öø-ÿ]+(?:[:.,'’][0-9A-Za-zÀ-ÖØ-öø-ÿ]+)*");

List<_Tok> _tokens(String s) => [
      for (final m in _wordRe.allMatches(s)) _Tok(m.start, m.end, m.group(0)!),
    ];

/// Lowercase word tokens, accents kept.
List<String> wordsOf(String s) =>
    [for (final t in _tokens(s)) t.text.toLowerCase()];

/// True when [s] has words and all of them are function words.
bool onlyFunctionWords(String s) {
  final w = wordsOf(s);
  return w.isNotEmpty && w.every(kFunctionWordsEs.contains);
}

final _sentenceBreak = RegExp(r'[.!?;:\n«»"“”()]');

/// A fix made only of function words, widened with the neighbouring words
/// of the user's sentence [context]: up to two words each side, stopping at
/// the first content word and at sentence punctuation. Returns the widened
/// (wrong, right) pair — the wrong side exactly as the user wrote it — or
/// the fix unchanged when it has content words or cannot be found.
(String, String) widenFix(String original, String corrected, String context) {
  final o = original.trim(), c = corrected.trim();
  if (o.isEmpty || c.isEmpty || context.trim().isEmpty) return (o, c);
  if (!onlyFunctionWords(o) || !onlyFunctionWords(c)) return (o, c);
  final toks = _tokens(context);
  final want = wordsOf(o);
  var at = -1;
  outer:
  for (var i = 0; i + want.length <= toks.length; i++) {
    for (var j = 0; j < want.length; j++) {
      if (toks[i + j].text.toLowerCase() != want[j]) continue outer;
    }
    at = i;
    break;
  }
  if (at < 0) return (o, c);
  final last = at + want.length - 1;
  bool joined(int a, int b) =>
      !_sentenceBreak.hasMatch(context.substring(toks[a].end, toks[b].start));
  var from = at, to = last;
  for (var k = 0; k < 2 && from > 0 && joined(from - 1, from); k++) {
    from--;
    if (!isFunctionWord(toks[from].text)) break;
  }
  for (var k = 0; k < 2 && to + 1 < toks.length && joined(to, to + 1); k++) {
    to++;
    if (!isFunctionWord(toks[to].text)) break;
  }
  if (from == at && to == last) return (o, c);
  final left = context.substring(toks[from].start, toks[at].start);
  final right = context.substring(toks[last].end, toks[to].end);
  // The user's capital at the start of a sentence stays ("Por eso" → "Para
  // eso", not "para eso").
  final written = toks[at].text;
  var fixed = c;
  if (written[0] != written[0].toLowerCase() &&
      fixed[0] == fixed[0].toLowerCase()) {
    fixed = fixed[0].toUpperCase() + fixed.substring(1);
  }
  return (
    context.substring(toks[from].start, toks[to].end).trim(),
    '$left$fixed$right'.trim(),
  );
}

/// The minimal changed fragment of a correction, with one neighbouring
/// word each side: ("no me atrevo molestar", "no me atrevo a molestar")
/// → ("atrevo molestar", "atrevo a molestar"). Long rewrites keep the
/// tail, where the error usually sits.
(String, String) keyForms(String wrong, String right) {
  final a = wrong.trim().split(RegExp(r'\s+'));
  final b = right.trim().split(RegExp(r'\s+'));
  if (wrong.trim().isEmpty) return ('', right.trim());
  String low(String s) => s.toLowerCase();
  var p = 0;
  while (p < a.length && p < b.length && low(a[p]) == low(b[p])) {
    p++;
  }
  var s = 0;
  while (s < a.length - p &&
      s < b.length - p &&
      low(a[a.length - 1 - s]) == low(b[b.length - 1 - s])) {
    s++;
  }
  List<String> key(List<String> t) {
    final from = (p - 1).clamp(0, t.length);
    final to = (t.length - s + 1).clamp(from, t.length);
    var k = t.sublist(from, to);
    if (k.length > 5) {
      k = k.sublist(k.length - (s > 0 ? 2 : 3));
    }
    return k;
  }

  final ka = key(a), kb = key(b);
  return (ka.join(' '), kb.join(' '));
}

/// Function words the correction added or changed ("a" in «atrevo a
/// molestar», "el" in «el 18»). Empty when the change is in a content
/// word (a verb ending, a noun) — then it is not a reusable pattern.
List<String> patternWords(String wrongKey, String rightKey) {
  final wrong = wordsOf(wrongKey).toSet();
  final added = wordsOf(rightKey).where((w) => !wrong.contains(w)).toList();
  if (added.isEmpty || !added.every(kFunctionWordsEs.contains)) return const [];
  return added;
}

/// Words of [rightKey] that the correction introduced (accents kept):
/// «compré» for compro → compré.
List<String> changedWords(String wrongKey, String rightKey) {
  final wrong = wordsOf(wrongKey).toSet();
  return wordsOf(rightKey).where((w) => !wrong.contains(w)).toList();
}

/// What pins a pattern to its construction: the corrected function word
/// and the content word next to it in the correct form.
class PatternAnchor {
  final String word; // the function word, lowercase, accents kept
  final String before; // governing word right before it, or ''
  final String after; // content word after it (articles skipped), or ''
  const PatternAnchor(this.word, {this.before = '', this.after = ''});

  bool get isEmpty => before.isEmpty && after.isEmpty;
}

/// Anchors of the pattern [mustContain] inside [canonical] (the correct key
/// form). Verb government (es.regimen) is pinned by the verb only: «a» after
/// a form of atreverse, not any «a».
List<PatternAnchor> patternAnchors(String canonical, List<String> mustContain,
    {String construction = ''}) {
  final toks = wordsOf(canonical);
  final out = <PatternAnchor>[];
  for (final fw in mustContain.map((w) => w.toLowerCase()).toSet()) {
    for (var j = 0; j < toks.length; j++) {
      if (toks[j] != fw) continue;
      var before = '';
      if (j > 0 && !kFunctionWordsEs.contains(toks[j - 1]))
        before = toks[j - 1];
      var after = '';
      for (var k = j + 1; k < toks.length && k <= j + 3; k++) {
        if (!kFunctionWordsEs.contains(toks[k])) {
          after = toks[k];
          break;
        }
      }
      if (construction == 'es.regimen' && before.isNotEmpty) after = '';
      final a = PatternAnchor(fw, before: before, after: after);
      if (!a.isEmpty) out.add(a);
    }
  }
  return out;
}

/// A readable rule for the model (prompt and repair messages).
String describeAnchors(List<PatternAnchor> anchors) => anchors.map((a) {
      final parts = [
        if (a.before.isNotEmpty) 'right after a form of «${a.before}»',
        if (a.after.isNotEmpty)
          _isNumber(a.after)
              ? 'right before a number (like «${a.after}»)'
              : 'before «${a.after}» (or a form of it)',
      ];
      return '«${a.word}» ${parts.join(' or ')}';
    }).join('; or ');

bool _isNumber(String w) => w.isNotEmpty && RegExp(r'^[0-9]').hasMatch(w);

bool isNumberWord(String w) => _isNumber(w);
