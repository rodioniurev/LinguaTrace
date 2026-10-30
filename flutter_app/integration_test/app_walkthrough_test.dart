/// Walks the real app on a real device/desktop: every tab, every reachable
/// button that has no destructive/network side effect. Any uncaught
/// exception (including RenderFlex overflows) fails the test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:lingua_trace/main.dart' as app;
import 'package:lingua_trace/widgets/language_selector.dart';

Future<void> settle(WidgetTester t) async {
  // pumpAndSettle can hang on repeating animations (progress bars) — pump a
  // fixed number of frames instead.
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('walk all tabs and safe buttons', (tester) async {
    app.main();
    await settle(tester);
    await settle(tester);

    // ── Tab bar present, 5 destinations
    expect(find.byType(NavigationBar), findsOneWidget);
    final tabs = ['Перевод', 'Проверка', 'История', 'Инсайты', 'Настройки'];
    for (final label in tabs) {
      expect(find.text(label), findsWidgets, reason: 'tab $label missing');
    }

    // ── Translate: type text, expect action chips to appear
    final input = find.byType(TextField).first;
    await tester.enterText(input, 'buenos dias');
    await settle(tester);
    expect(find.text('Идиома'), findsOneWidget, reason: 'Idiom chip');
    expect(find.text('Контекст'), findsOneWidget, reason: 'Context chip');
    expect(find.text('Слова'), findsOneWidget, reason: 'Words chip');

    // Context button without an API key must show the hint snackbar, not crash
    await tester.tap(find.text('Контекст'));
    await settle(tester);
    // The floating snackbar covers the bottom language bar for ~4s — wait it
    // out before tapping the language chip below it.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);

    // Language chips open the picker; close it back. The source chip label
    // is "Автоопределение" only when source == auto — fall back to tapping
    // the first chip in the bottom bar otherwise.
    // Snackbars/async panels make single taps flaky — retry up to 3 times.
    var pickerOpened = false;
    for (var attempt = 0; attempt < 3 && !pickerOpened; attempt++) {
      final autoChip = find.text('Автоопределение');
      if (autoChip.evaluate().isNotEmpty) {
        await tester.tap(autoChip.first, warnIfMissed: false);
      } else {
        await tester.tap(find.byIcon(Icons.expand_more_rounded).first,
            warnIfMissed: false);
      }
      await settle(tester);
      await settle(tester); // sheet slide-in animation
      pickerOpened = find.byType(LanguagePickerSheet).evaluate().isNotEmpty;
      if (!pickerOpened) await tester.pump(const Duration(seconds: 2));
    }
    expect(pickerOpened, isTrue, reason: 'language picker should open');
    await tester.tapAt(const Offset(400, 40)); // dismiss sheet
    await settle(tester);
    await settle(tester);

    // Swap button — with auto source shows the explanatory snackbar
    await tester.tap(find.byIcon(Icons.swap_horiz_rounded), warnIfMissed: false);
    await settle(tester);

    // Clear button resets the field
    final clear = find.byIcon(Icons.clear_rounded);
    if (clear.evaluate().isNotEmpty) {
      await tester.tap(clear.first, warnIfMissed: false);
      await settle(tester);
    }

    // ── Correct tab
    await tester.tap(find.text('Проверка'));
    await settle(tester);
    expect(find.text('Проверка текста'), findsWidgets);

    // ── History tab
    await tester.tap(find.text('История'));
    await settle(tester);
    expect(find.textContaining('История'), findsWidgets);

    // ── Insights tab (+ open Training screen and back)
    await tester.tap(find.text('Инсайты'));
    await settle(tester);
    expect(find.text('Тренировка'), findsOneWidget);
    await tester.tap(find.text('Тренировка'));
    await settle(tester);
    expect(find.textContaining('тренировок', findRichText: true), findsWidgets,
        reason: 'training empty state');
    // Generate without AI key → must show error text, not crash
    final genBtn = find.textContaining('Новая тренировка');
    if (genBtn.evaluate().isNotEmpty) {
      await tester.tap(genBtn.first, warnIfMissed: false);
      await settle(tester);
    }
    // pageBack() matches the English "Back" tooltip — with the RU locale the
    // tooltip is "Назад", so find the Material BackButton by type instead.
    await tester.tap(find.byType(BackButton).first);
    await settle(tester);

    // ── Settings: switch every theme, toggle offline, open LLM advanced
    await tester.tap(find.text('Настройки'));
    await settle(tester);
    for (final theme in ['Светлая', 'Средняя', 'Белая', 'Тёмная']) {
      final chip = find.text(theme);
      if (chip.evaluate().isNotEmpty) {
        await tester.ensureVisible(chip.first);
        await tester.tap(chip.first, warnIfMissed: false);
        await settle(tester);
      }
    }
    final offline = find.text('Предпочитать офлайн-перевод');
    await tester.ensureVisible(offline);
    await tester.tap(offline, warnIfMissed: false);
    await settle(tester);
    await tester.tap(offline, warnIfMissed: false); // back off
    await settle(tester);

    final advanced = find.text('Модель / токен');
    if (advanced.evaluate().isNotEmpty) {
      await tester.ensureVisible(advanced.first);
      await tester.tap(advanced.first, warnIfMissed: false);
      await settle(tester);
    }

    // ── Back to Translate — app still alive
    await tester.tap(find.text('Перевод'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
