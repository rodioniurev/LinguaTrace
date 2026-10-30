/// Deep explanation of a correction — the "Подробнее" button on the Correct
/// screen. The inline fix list answers *what* changed in one line; this
/// answers *why*, with the rule, examples, word history and the trap that
/// produced the mistake in the first place.
///
/// Runs through [LlmRouter], so it works on the free backends (on-device
/// model or Ollama) exactly like the rest of the AI features.
library;

import '../models/correction.dart';
import 'llm_router.dart';

class ExplanationService {
  final LlmRouter _llm;
  final _cache = <String, String>{};

  ExplanationService(this._llm);

  bool get isAvailable => _llm.hasQualityBackend;
  String get backendName => _llm.backendName;
  String get unavailableReason => _llm.unavailableReason;

  static const _system = '''
Ты — преподаватель-филолог, объясняешь русскоязычному ученику его ошибки в
иностранном тексте. Тебе дают исходное предложение, исправленный вариант и
список правок.

Разбери КАЖДУЮ правку отдельным блоком в Markdown, ПО-РУССКИ:

### «было» → «стало»
**Правило.** Суть одним абзацем: какая это категория (согласование, вид,
предлог, артикль, порядок слов…) и как правило звучит. Без формализма.

**Примеры.** 3 коротких примера НА ИЗУЧАЕМОМ ЯЗЫКЕ с переводом на русский:
два верных и один типично неверный с пометкой, почему так нельзя.

**Откуда это.** Происхождение слова или конструкции, если оно объясняет
форму: латинский/арабский/германский корень, историческое изменение,
родственные слова в других языках. Если история ничего не объясняет —
честно пропусти этот подпункт, не выдумывай этимологию.

**Ловушка.** Почему носитель русского языка ошибается здесь особенно часто
(интерференция с русским) и как это запомнить — короткая опора или мнемоника.

Правила: опирайся только на переданные правки; не придумывай ошибок, которых
не было; не выдумывай этимологию и «исторические факты» — при неуверенности
прямо пиши, что происхождение спорное. Общий объём — до 500 слов.''';

  /// Explain [fixes] made to [original] (result: [corrected]) in [langName].
  /// Cached per sentence so re-opening the panel is instant and free.
  Future<String> explain({
    required String original,
    required String corrected,
    required List<CorrectionFix> fixes,
    required String langName,
  }) async {
    final key = '$langName|$original|$corrected';
    final cached = _cache[key];
    if (cached != null) return cached;

    final buf = StringBuffer()
      ..writeln('ЯЗЫК ТЕКСТА: $langName')
      ..writeln('НАПИСАНО: $original')
      ..writeln('ИСПРАВЛЕНО: $corrected')
      ..writeln('ПРАВКИ:');
    if (fixes.isEmpty) {
      buf.writeln('(правок нет — объясни, почему предложение уже корректно, '
          'и укажи, что в нём могло бы пойти не так)');
    }
    for (final f in fixes) {
      buf.write('- «${f.original}» → «${f.fixed}»');
      if (f.reason.isNotEmpty) buf.write(' | пояснение: ${f.reason}');
      if (f.category != null && f.category!.isNotEmpty) {
        buf.write(' | тип: ${f.category}');
      }
      buf.writeln();
    }

    final result = await _llm.complete(
      system: _system,
      user: buf.toString(),
      // Room for adaptive thinking + ~500 words of answer.
      maxTokens: 8000,
      effort: 'medium',
      timeout: const Duration(minutes: 5),
      // Small on-device models invent rules and etymologies.
      allowOnDevice: false,
      feature: 'explanation',
    );
    _cache[key] = result;
    return result;
  }
}
