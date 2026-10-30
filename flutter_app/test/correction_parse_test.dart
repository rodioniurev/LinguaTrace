/// What counts as "my mistake": only confident, anchored errors from a
/// trustworthy backend are recorded — upgrades and small-model guesses are
/// shown but never written to the error memory.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/services/ai_types.dart';
import 'package:lingua_trace/services/correction_service.dart';

AiResult _r(Map<String, dynamic> json, {String provider = 'claude_code', String model = 'claude-opus-5'}) =>
    AiResult(text: '', json: json, backend: 'b', provider: provider, model: model);

void main() {
  const input = 'entonces, no me atrevo molestar a su familia';
  final json = {
    'corrected': 'entonces, no me atrevo a molestar a su familia',
    'note': '',
    'fixes': [
      {
        'original': 'atrevo molestar',
        'fixed': 'atrevo a molestar',
        'reason': 'После atreverse нужен предлог a.',
        'category': 'grammar',
        'construction': 'es.regimen',
        'severity': 'error',
        'confidence': 0.95,
      },
      {
        'original': 'molestar a su familia',
        'fixed': 'importunar a su familia',
        'reason': 'Более естественно.',
        'category': 'style',
        'construction': 'es.register',
        'severity': 'upgrade',
        'confidence': 0.6,
      },
      {
        'original': 'nonexistent phrase',
        'fixed': 'x',
        'reason': '',
        'category': 'grammar',
        'construction': 'made.up.tag',
        'severity': 'error',
        'confidence': 0.9,
      },
    ],
  };

  test('only the confident, anchored error is recordable', () {
    final r = CorrectionService.parse(_r(json), input);
    expect(r.fixes.length, 3);
    final rec = r.recordable.toList();
    expect(rec.single.fixed, 'atrevo a molestar');
    expect(rec.single.construction, 'es.regimen');
    expect(r.upgrades.single.fixed, 'importunar a su familia');
    expect(r.fixes.last.construction, 'other',
        reason: 'unknown tags are normalised');
    expect(r.fixes.last.anchored, isFalse);
  });

  test('small local models are shown but never recorded', () {
    expect(CorrectionService.parse(_r(json, provider: 'local'), input)
        .recordable, isEmpty);
    expect(
        CorrectionService.isTrustworthyBackend('ollama', 'qwen2.5:3b'), isFalse);
    expect(
        CorrectionService.isTrustworthyBackend('ollama', 'qwen2.5:14b'), isTrue);
    expect(CorrectionService.isTrustworthyBackend('claude', 'claude-haiku-4-5'),
        isTrue);
  });

  test('plain-text JSON (no structured output) still parses', () {
    final r = CorrectionService.parse(
        const AiResult(
            text: 'Вот ответ:\n```json\n{"corrected": "ok", "fixes": [], "note": ""}\n```',
            backend: 'b',
            provider: 'custom'),
        'ok');
    expect(r.corrected, 'ok');
    expect(r.fixes, isEmpty);
  });

  test('lenient parsing: string confidence, deletions kept', () {
    final r = CorrectionService.parse(
        _r({
          'corrected': 'Busco un piso',
          'note': null,
          'fixes': [
            {
              'original': 'a ',
              'fixed': '',
              'reason': 'лишнее личное a',
              'category': 'grammar',
              'construction': 'es.a_personal',
              'severity': 'error',
              'confidence': '0.9',
            },
          ],
        }),
        'Busco a un piso');
    expect(r.fixes.single.fixed, '');
    expect(r.fixes.single.confidence, 0.9);
    expect(r.recordable, hasLength(1));
  });

  test('trust follows model size, not a name list', () {
    bool t(String p, String m, {bool local = false}) =>
        CorrectionService.isTrustworthyBackend(p, m, localEndpoint: local);
    expect(t('ollama', 'qwen3:1.7b'), isFalse);
    expect(t('ollama', 'gemma3:270m'), isFalse);
    expect(t('ollama', 'llama3.2'), isFalse, reason: 'unknown size, local');
    expect(t('ollama', 'qwen2.5:14b'), isTrue);
    expect(t('custom', 'local-model', local: true), isFalse);
    expect(t('custom', 'gemini-2.0-flash'), isTrue, reason: 'remote service');
    expect(t('custom', 'llama-3.3-70b-versatile'), isTrue);
    expect(t('custom', 'meta-llama/llama-3.2-1b-instruct'), isFalse);
  });
}
