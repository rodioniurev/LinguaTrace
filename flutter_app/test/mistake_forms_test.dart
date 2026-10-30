/// Pattern mistakes in the feed: a lone function-word fix is widened with
/// its neighbours, and a reuse must sit next to its anchor — any «a» or
/// «el» somewhere in a phrase is not the construction (review 2026-09-26,
/// P1/P2/P5).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_trace/core/mistake_forms.dart';
import 'package:lingua_trace/models/feed.dart';
import 'package:lingua_trace/models/learning_item.dart';
import 'package:lingua_trace/services/feed_composer.dart';
import 'package:lingua_trace/services/feed_task_grader.dart';
import 'package:lingua_trace/services/feed_validator.dart';

void main() {
  group('widenFix: a lone function word gets its neighbours', () {
    test('a date: «a 18» → «el 18» with the verb before it', () {
      expect(widenFix('a', 'el', 'Llegaré a 18 de agosto a Santander.'),
          ('Llegaré a 18', 'Llegaré el 18'));
    });
    test('articles are skipped until a content word', () {
      expect(widenFix('en', 'a', 'Mañana voy en la universidad temprano.'),
          ('voy en la universidad', 'voy a la universidad'));
    });
    test('never across a sentence boundary', () {
      expect(widenFix('por', 'para', 'Es tarde. Por eso me voy.'),
          ('Por eso', 'Para eso'));
    });
    test('fixes with content words are left alone', () {
      expect(
          widenFix(
              'atrevo molestar', 'atrevo a molestar', 'no me atrevo molestar'),
          ('atrevo molestar', 'atrevo a molestar'));
    });
    test('not in the context, or no context: unchanged', () {
      expect(widenFix('a', 'el', 'Nada que ver.'), ('a', 'el'));
      expect(widenFix('a', 'el', ''), ('a', 'el'));
    });
  });

  group('anchors', () {
    test('verb government is pinned by the verb before the word', () {
      final a = patternAnchors('atrevo a molestar', ['a'],
          construction: 'es.regimen');
      expect(a.single.before, 'atrevo');
      expect(a.single.after, '');
    });
    test('a date is pinned by the number after the article', () {
      final a = patternAnchors('el 18', ['el']);
      expect(a.single.after, '18');
    });
    test('a bare function word has nothing to pin it', () {
      expect(patternAnchors('el', ['el']), isEmpty);
    });
    test('the prompt names the anchor', () {
      expect(
          describeAnchors(patternAnchors('atrevo a molestar', ['a'],
              construction: 'es.regimen')),
          '«a» right after a form of «atrevo»');
      expect(describeAnchors(patternAnchors('el 18', ['el'])),
          '«el» right before a number (like «18»)');
    });
  });

  group('realisesPattern', () {
    bool re(String text, String canonical, List<String> words,
            {String c = ''}) =>
        FeedValidator.realisesPattern(text, canonical, words, construction: c);

    test('«se atrevieron a rechazar» reuses «atrevo a molestar»', () {
      expect(
          re('no se atrevieron a rechazar', 'atrevo a molestar', ['a'],
              c: 'es.regimen'),
          isTrue);
    });
    test('«a los convenios» / «a un aumento» do not', () {
      for (final t in ['a los convenios', 'llegue a un aumento']) {
        expect(re(t, 'atrevo a molestar', ['a'], c: 'es.regimen'), isFalse,
            reason: t);
      }
    });
    test('«el 26 de septiembre» reuses «el 18»; «el Ejecutivo» does not', () {
      expect(re('el 26 de septiembre', 'el 18', ['el']), isTrue);
      expect(re('el Ejecutivo aprobó', 'el 18', ['el']), isFalse);
    });
    test('accents of the function word count: esta ≠ está', () {
      expect(re('esta semana cansados', 'está cansado', ['está']), isFalse);
      expect(re('están cansados', 'está cansado', ['está']), isTrue);
    });
    test('a vehicle after «en»: articles in between are fine', () {
      expect(re('viajó en el autobús nocturno', 'en autobús', ['en']), isTrue);
      expect(re('en tren', 'en autobús', ['en']), isFalse);
    });
  });

  group('validator V5 with a pattern target', () {
    const t = FeedTargetSpec(
      id: 'T1',
      itemId: 1,
      kind: 'mistake',
      canonical: 'atrevo a molestar',
      wrongForm: 'atrevo molestar',
      construction: 'es.regimen',
      mustContain: ['a'],
    );

    test('a single-word wrong form is not searched in the body', () {
      // «en» → «a» without context: "en" is in every text.
      const bare = FeedTargetSpec(
          id: 'T2',
          itemId: 2,
          kind: 'mistake',
          canonical: 'a',
          wrongForm: 'en',
          required: false);
      final d = FeedDraft.fromJson(const {
        'story_source_ids': ['S1'],
        'headline': 'x',
        'body': 'El Gobierno aprobó en marzo la subida.',
        'targets_used': [],
        'tasks': [],
      });
      final r = const FeedValidator().check(d, const [], const [bare]);
      expect(r.violations.where((v) => v.contains('wrong form')), isEmpty);
    });

    test('an unrelated «a» is rejected with the anchor in the message', () {
      final d = FeedDraft.fromJson(const {
        'story_source_ids': ['S1'],
        'headline': 'x',
        'body': 'Los sindicatos piden que la subida llegue a los convenios.',
        'targets_used': [
          {'target_id': 'T1', 'form_used': 'a los convenios', 'occurrence': 1},
        ],
        'tasks': [],
      });
      final r = const FeedValidator().check(d, const [], const [t]);
      expect(
          r.violations.where((v) => v.contains(
              "T1 form_used 'a los convenios' must reuse the corrected "
              'pattern «atrevo a molestar»: «a» right after a form of «atrevo»')),
          hasLength(1),
          reason: r.violations.join('\n'));
    });
  });

  group('grading free answers', () {
    FeedItemTarget mistake(String wrong, String right, [String c = '']) =>
        FeedItemTarget(
            feedItemId: 1,
            itemId: 1,
            start: 0,
            end: 1,
            form: right,
            kind: 'mistake',
            canonical: right,
            wrongForm: wrong,
            construction: c);

    test('a retell with any «a» is not production of «atreverse a»', () {
      final t = mistake(
          'no me atrevo molestar', 'no me atrevo a molestar', 'es.regimen');
      expect(usesTarget('No quiero molestar hoy.', t), isFalse);
      expect(usesTarget('Voy a casa.', t), isFalse);
      expect(usesTarget('Nadie se atrevió a protestar.', t), isTrue);
    });

    test('a word-form slip needs the corrected word, accents included', () {
      final t = mistake('compro', 'compré');
      expect(usesTarget('Ayer compré pan.', t), isTrue);
      expect(usesTarget('Ayer compre pan.', t), isFalse);
      expect(usesTarget('Siempre compro pan.', t), isFalse);
    });
  });

  group('sameOption: one predicate for validation and grading', () {
    test('case, spacing and punctuation do not matter', () {
      expect(FeedValidator.sameOption('A', 'a'), isTrue);
      expect(FeedValidator.sameOption(' a. ', 'a'), isTrue);
    });
    test('accents do', () {
      expect(FeedValidator.sameOption('está', 'esta'), isFalse);
    });
    test('symbol-only options compare as typed', () {
      expect(FeedValidator.sameOption('—', '—'), isTrue);
      expect(FeedValidator.sameOption('—', 'a'), isFalse);
    });
  });

  group('planner: which mistakes can be targets', () {
    LearningItem item(String wrong, String right, [String c = '']) =>
        LearningItem(
            id: 1,
            kind: 'mistake',
            lang: 'es',
            text: right,
            wrongForm: wrong,
            construction: c);

    test('a bare function word without context is left out', () {
      expect(FeedComposer.usableMistake(item('a', 'el')), isFalse);
    });
    test('a widened date fix and a slip are usable', () {
      expect(FeedComposer.usableMistake(item('Llegaré a 18', 'Llegaré el 18')),
          isTrue);
      expect(FeedComposer.usableMistake(item('compro', 'compré')), isTrue);
    });
  });
}
