/// Writing correction: returns a corrected version plus a per-fix breakdown
/// that names the rule (in the user's native language) and tags each fix
/// with a construction from constructions.dart, so mistakes aggregate.
///
/// Goes through [LlmRouter] (cloud first). Results from small local models
/// are shown but flagged [CorrectionResult.trustworthy] = false — they must
/// not be written into the error memory.
library;

import 'dart:async';

import '../core/constructions.dart';
import '../core/languages.dart';
import '../models/correction.dart';
import 'ai_types.dart';
import 'llm_router.dart';

class CorrectionService {
  final LlmRouter _llm;

  CorrectionService(this._llm);

  /// The correction prompt (rules + construction list, ~900 tokens) does
  /// not fit the 1024-token on-device model, so it needs a real backend.
  bool get hasBackend => _llm.hasQualityBackend;
  String get unavailableReason => _llm.unavailableReason;

  static final Map<String, dynamic> schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['corrected', 'fixes', 'note'],
    'properties': {
      'corrected': {'type': 'string'},
      'note': {'type': 'string'},
      'fixes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'original', 'fixed', 'reason', 'category', 'construction',
            'severity', 'confidence',
          ],
          'properties': {
            'original': {'type': 'string'},
            'fixed': {'type': 'string'},
            'reason': {'type': 'string'},
            'category': {
              'type': 'string',
              'enum': [
                'grammar', 'word_choice', 'article', 'spelling',
                'punctuation', 'style',
              ],
            },
            'construction': {
              'type': 'string',
              'enum': [for (final c in kSpanishConstructions) c.tag],
            },
            'severity': {
              'type': 'string',
              'enum': ['error', 'upgrade'],
            },
            'confidence': {'type': 'number'},
          },
        },
      },
    },
  };

  String _system(String langName, String nativeName, bool spanish) => '''
You are a meticulous $langName editor for an adult whose native language is $nativeName.
Correct the user's text with MINIMAL edits and explain every fix.

Rules:
- "original": the SHORTEST exact substring of the user's text that is wrong (a word or a short phrase, never the whole sentence). "fixed": what replaces it. For an extra word that must be removed, include one neighbouring word in both, so "fixed" is never empty (e.g. "Busco a un" → "Busco un").
- "reason": ONE sentence in $nativeName naming the rule (e.g. «после atreverse нужен предлог a»). Never in $langName.
- "severity": "error" only if a careful native speaker or the grammar would call it wrong; "upgrade" if it is correct but a more natural or idiomatic phrasing exists (put idiom suggestions here).
- "construction": ${spanish ? 'one tag from the list below that names the underlying problem' : 'always "other"'}.
- "confidence": 0..1, how sure you are that the fix is needed.
- Never "fix" accepted variants: RAE/DPD-accepted spellings (e.g. "enseguida"), regional usage (Spain vs Latin America), or style choices that are not errors.
- Do not translate the text. Do not rewrite for style in "corrected" beyond the listed fixes.
- If the text is fully correct: "fixes" = [] and "corrected" = the input verbatim.
- "note": one short sentence in $nativeName, or "".
${spanish ? '\nConstruction tags:\n${constructionTagList()}' : ''}''';

  /// Correct [text] written in [language] (ISO 639-1). Explanations come in
  /// [nativeLang].
  Future<CorrectionResult> correct(String text, String language,
      {String nativeLang = 'ru', String feature = 'correction'}) async {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('Empty input');
    final langName = _langName(language);
    final nativeName = _langName(nativeLang);
    final spanish = language.startsWith('es');

    final r = await _llm.completeResult(
      system: _system(langName, nativeName, spanish),
      user: clean,
      maxTokens: 8000,
      effort: 'low',
      jsonSchema: schema,
      timeout: const Duration(minutes: 2),
      allowOnDevice: false,
      feature: feature,
      tier: 'fast',
    );
    return parse(r, clean);
  }

  static String _str(Object? v) => v == null ? '' : v.toString().trim();

  static double _num(Object? v, double fallback) => v is num
      ? v.toDouble()
      : (double.tryParse(_str(v)) ?? switch (_str(v).toLowerCase()) {
          'high' => 0.9,
          'medium' => 0.6,
          'low' => 0.3,
          _ => fallback,
        });

  /// Visible for tests.
  static CorrectionResult parse(AiResult r, String input) {
    final data = r.json ?? extractJsonObject(r.text);
    if (data == null) {
      throw AiException('ИИ вернул ответ не в том формате — попробуйте ещё '
          'раз.', detail: r.text);
    }
    final corrected = _str(data['corrected']);
    if (corrected.isEmpty) {
      throw const AiException('ИИ не вернул исправленный текст');
    }
    final fixes = <CorrectionFix>[];
    final rawFixes = data['fixes'];
    for (final f in rawFixes is List ? rawFixes : const []) {
      if (f is! Map) continue;
      final orig = _str(f['original']);
      final fixed = _str(f['fixed']);
      // An empty "fixed" is a deletion of an extra word — keep it.
      if (orig.isEmpty || orig == fixed) continue;
      final constr = _str(f['construction']);
      fixes.add(CorrectionFix(
        original: orig,
        fixed: fixed,
        reason: _str(f['reason']),
        category: _str(f['category']),
        construction: kConstructionByTag.containsKey(constr) ? constr : 'other',
        severity: _str(f['severity']) == 'upgrade' ? 'upgrade' : 'error',
        confidence: _num(f['confidence'], 0.5),
        // The model must quote the user's text; a fix whose "original" is
        // not in the input cannot be anchored and is likely invented.
        anchored: input.contains(orig),
      ));
    }
    final note = _str(data['note']);
    return CorrectionResult(
      corrected: corrected,
      fixes: fixes,
      note: note.isEmpty ? null : note,
      backend: r.backend,
      trustworthy: isTrustworthyBackend(r.provider, r.model,
          localEndpoint: r.localEndpoint),
    );
  }

  /// Small models confidently invent fixes — their output may be shown, but
  /// never recorded as the user's mistakes. Trust needs ≥ 7B parameters;
  /// an unknown size is trusted only for remote services.
  static bool isTrustworthyBackend(String provider, String model,
      {bool localEndpoint = false}) {
    if (provider == 'local') return false;
    if (provider.startsWith('claude')) return true;
    final size = modelSizeB(model);
    if (size != null) return size >= 7;
    return !(localEndpoint || provider == 'ollama');
  }

  String _langName(String code) {
    final two = code.length >= 2 ? code.substring(0, 2) : code;
    return (kLanguages[code] ?? kLanguages[two] ?? two).split('(').first.trim();
  }
}
