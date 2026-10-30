/// Personal training-corpus generator.
///
/// Takes the user's REAL recorded mistakes (from the Correct tab) and the
/// words they repeatedly look up (patterns table), and asks the cloud LLM to
/// build a practice session targeted at exactly those weaknesses — rule
/// recaps, exercises, and a saturated text that turns corrections into a
/// skill. Sessions are stored in the `trainings` table.
library;

import '../core/database.dart';
import '../models/mistake.dart';
import 'llm_router.dart';

class TrainingService {
  final LlmRouter _llm;
  final DatabaseService _db;

  TrainingService(this._llm, this._db);

  bool get isAvailable => _llm.hasQualityBackend;
  String get unavailableReason => _llm.unavailableReason;

  static const _system = '''
Ты — опытный методист испанского языка для русскоязычного ученика.
Тебе дают список его РЕАЛЬНЫХ ошибок (что написал → как правильно, причина,
сколько раз повторилась) и слова, которые он повторно ищет в словаре.

Составь персональную тренировку в Markdown, ПО-РУССКИ (испанский — только в
учебном материале):

## Разбор ошибок
3–5 самых системных ошибок: правило одним абзацем + мнемоника/опора.
Группируй однотипные ошибки в одно правило.
Ошибки с пометкой «повтор N» уже разбирались раньше — для них дай НЕ то же
объяснение, а другой заход: иной ракурс правила, другая опора, более
сложные примеры.

## Упражнения
10–12 упражнений, каждое бьёт по конкретной ошибке из списка:
пропуски (___), выбор формы (а/б), перевод короткой фразы RU→ES.
Нумеруй. Не подписывай ответы рядом с заданием.

## Текст для чтения
Связный испанский текст 100–140 слов, естественно насыщенный ПРАВИЛЬНЫМИ
употреблениями проблемных конструкций, повторно искомых слов и выражений
из тетради (каждое — естественно и к месту, не больше одного раза). После него —
русский перевод.

## Ответы
Ответы к упражнениям одной строкой на упражнение.

Правила: опирайся только на переданные ошибки и слова; не выдумывай ошибок,
которых не было; чем чаще повторялась ошибка — тем больше внимания ей.''';

  /// How many mistakes are waiting for their next review right now.
  Future<int> dueCount({String lang = ''}) => _db.dueMistakeCount(lang: lang);

  /// Generate a new practice session and persist it. Returns the entry.
  ///
  /// Selection is repetition-driven: whatever the spaced-repetition schedule
  /// says is due comes first, so the course keeps circling back to mistakes
  /// until they stop coming back. Only if nothing is due does it fall back to
  /// the plain "most frequent" list.
  Future<TrainingEntry> generate({String lang = 'es'}) async {
    var allMistakes = await _db.getDueMistakes(limit: 40, lang: lang);
    if (allMistakes.isEmpty) allMistakes = await _db.getDueMistakes(limit: 40);
    if (allMistakes.isEmpty) {
      allMistakes = await _db.getMistakes(limit: 40, lang: lang);
    }
    if (allMistakes.isEmpty) allMistakes = await _db.getMistakes(limit: 40);
    // Only short repeated lookups — paragraph drafts are not "words".
    final patterns = await _db.getTopPatterns(limit: 25, minCount: 2);
    final collected = await _db.getItems(
        statuses: const ['learning'], lang: lang, limit: 20);

    if (allMistakes.isEmpty && patterns.isEmpty && collected.isEmpty) {
      throw Exception(
          'Пока нет данных: пишите по-испански в «Переводе» или «Проверке» '
          'и добавляйте выражения в тетрадь — они начнут накапливаться');
    }

    final buf = StringBuffer('ОШИБКИ УЧЕНИКА:\n');
    if (allMistakes.isEmpty) {
      buf.writeln('(пока не записано)');
    }
    for (final m in allMistakes) {
      buf.write('- «${m.original}» → «${m.corrected}»');
      if (m.reason.isNotEmpty) buf.write(' | причина: ${m.reason}');
      if (m.category.isNotEmpty) buf.write(' | тип: ${m.category}');
      if (m.seenCount > 1) buf.write(' | повторов: ${m.seenCount}');
      if (m.practiceCount > 0) buf.write(' | повтор ${m.practiceCount}');
      if (m.construction.isNotEmpty) buf.write(' | конструкция: ${m.construction}');
      buf.writeln();
    }
    buf.writeln('\nВЫРАЖЕНИЯ, КОТОРЫЕ ОН ВЗЯЛ В ТЕТРАДЬ (ввести в активный оборот):');
    final expressions = collected.where((i) => i.kind != 'mistake').toList();
    if (expressions.isEmpty) buf.writeln('(нет)');
    for (final i in expressions) {
      buf.write('- ${i.text}');
      if (i.gloss.isNotEmpty) buf.write(' — ${i.gloss}');
      buf.writeln(' (${i.kind})');
    }
    buf.writeln('\nСЛОВА, КОТОРЫЕ ОН ИЩЕТ ПОВТОРНО:');
    if (patterns.isEmpty) {
      buf.writeln('(нет)');
    }
    for (final p in patterns) {
      buf.writeln('- ${p.phrase} (${p.count} раз)');
    }

    final result = await _llm.completeResult(
      system: _system,
      user: buf.toString(),
      maxTokens: 16000,
      effort: 'medium',
      // A full session on a CPU-only Ollama box takes minutes, not seconds.
      timeout: const Duration(minutes: 10),
      // A 1024-token on-device model cannot hold this prompt; its output
      // would be saved as a "training" regardless.
      allowOnDevice: false,
      feature: 'training',
    );
    final content = result.text;

    // Generating a session is not a review: the schedule moves when the
    // user marks the session done (TrainingScreen → markTrainingDone).
    final ids = allMistakes.map((m) => m.id).whereType<int>().toList();
    await _db.markShown(ids);

    final id = await _db.addTraining(lang, content, mistakeIds: ids);
    return TrainingEntry(id: id, lang: lang, content: content);
  }
}
