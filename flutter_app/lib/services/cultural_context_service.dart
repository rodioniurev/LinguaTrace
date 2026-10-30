/// Cultural-context lookup — explains the origin, meaning, and cultural
/// background of an expression, quote, idiom, or proverb through whichever
/// LLM backend is available (on-device → Ollama → cloud).
///
/// Example: «По-итальянски я разговариваю с женщинами, по-французски — с
/// солдатами...» → identifies the (apocryphal) Charles V quip, its history,
/// variants, and what it says about European language attitudes.
library;

import 'llm_router.dart';

class CulturalContextService {
  final LlmRouter _llm;
  final _cache = <String, String>{};

  CulturalContextService(this._llm);

  bool get isAvailable => _llm.hasQualityBackend;
  String get providerName => _llm.backendName;
  String get unavailableReason => _llm.unavailableReason;

  /// Backend that produced the last answer (not just the first in line).
  String? lastBackend;

  static const _system = '''
Ты — филолог, этнограф и культуролог, помогаешь русскоязычному человеку,
изучающему испанский язык. Тебе дают выражение: пословицу, идиому, крылатую
фразу, цитату или просто необычный оборот — на русском, испанском или другом
языке.

Определи культурный контекст и ответь ПО-РУССКИ, кратко и структурно:

**Что это.** Тип выражения (пословица / крылатая фраза / идиома / цитата).
Если это известная цитата — автор, эпоха, обстоятельства, историческая
достоверность (в т.ч. если атрибуция апокрифична — скажи об этом).

**Образ и смысл.** Буквальный образ и переносное значение; почему выбран
именно этот образ (исторические/бытовые корни).

**Культурный контекст.** Коннотации, в каких ситуациях уместно, регистр
(разговорное/книжное/устаревшее), региональные особенности если есть.

**Аналоги.** Устоявшиеся аналоги в русском, испанском и английском —
только реально существующие; если аналога нет, скажи прямо и предложи,
как передать смысл описательно.

Правила: не выдумывай атрибуции и «эквиваленты»; при неуверенности прямо
отмечай сомнение. Объём — до 250 слов. Без вводных фраз, сразу по делу.''';

  Future<String> explain(String text) async {
    final key = text.trim().toLowerCase();
    final cached = _cache[key];
    if (cached != null) return cached;

    final r = await _llm.completeResult(
      system: _system,
      user: text.trim(),
      maxTokens: 6000,
      // Snappy lookups matter more than maximum depth here.
      effort: 'low',
      // Small local models hallucinate attributions.
      allowOnDevice: false,
      feature: 'context',
      tier: 'fast',
    );
    lastBackend = r.backend;
    _cache[key] = r.text;
    return r.text;
  }
}
