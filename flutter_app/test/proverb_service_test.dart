import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/services/proverb_service.dart';

void main() {
  group('normalizeForMatch', () {
    test('strips combining stress marks (RU corpus is stress-marked)', () {
      expect(normalizeForMatch('Куда́ ни кинь, везде́ клин.'),
          'куда ни кинь везде клин');
      expect(normalizeForMatch('Не всё то зо́лото, что блести́т.'),
          'не все то золото что блестит');
      expect(normalizeForMatch('Язы́к до Кие́ва доведёт.'),
          'язык до киева доведет');
    });

    test('folds ё → е and keeps й intact', () {
      expect(normalizeForMatch('Всему свой черёд'), 'всему свой черед');
      expect(normalizeForMatch('ёж'), 'еж');
    });

    test('folds Spanish diacritics and inverted punctuation', () {
      expect(normalizeForMatch('¡No hay atajo sin trabajo!'),
          'no hay atajo sin trabajo');
      expect(normalizeForMatch('educación'), 'educacion');
      expect(normalizeForMatch('mañana será otro día'), 'manana sera otro dia');
    });

    test('drops punctuation and collapses whitespace', () {
      expect(normalizeForMatch('  Слово — серебро,   молчание — золото. '),
          'слово серебро молчание золото');
    });
  });

  group('significantTokens', () {
    test('drops RU stopwords', () {
      expect(
        significantTokens(normalizeForMatch('Не всё то золото, что блестит')),
        ['золото', 'блестит'],
      );
    });

    test('drops ES stopwords', () {
      expect(
        significantTokens(normalizeForMatch('No es oro todo lo que reluce')),
        ['oro', 'todo', 'reluce'],
      );
    });
  });
}
