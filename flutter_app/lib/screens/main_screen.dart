/// Bottom-navigation host screen.
/// Handles incoming share intents (text shared from other Android apps)
/// via a native MethodChannel (no plugin needed).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../core/app_paths.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/exchange_service.dart';
import 'feed_screen.dart';
import 'ideas_screen.dart';
import 'translate_screen.dart';
import 'correction_screen.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('io.linguatrace/share_intent');

  // Exchange (folder on the PC, sync server everywhere): at start, on
  // return to the app, every 10 minutes and soon after a dictation.
  Timer? _syncTimer;
  Timer? _syncSoon;
  StreamSubscription<void>? _syncRequests;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  bool _syncing = false;

  int _currentIndex = 0;
  String? _sharedText;

  // Лента · Перевод · Идеи · Проверка · Инсайты (with the Журнал) · Настройки.
  static const _translateTab = 1;

  final _tabKeys = List.generate(6, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer =
        Timer.periodic(const Duration(minutes: 10), (_) => _syncExchange());
    _syncRequests = ExchangeService.syncRequests.listen((_) {
      _syncSoon?.cancel();
      _syncSoon = Timer(const Duration(seconds: 5), _syncExchange);
    });
    _setupShareIntent();
    // Desktop: the exchange folder is the single shared place — pull what
    // the phone sent, grade its pending answers, write our own file.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncExchange());
    // «Claude для телефона»: the PC answers the phone's AI requests.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AppPaths.isDesktop && ref.read(configProvider).relayServerEnabled) {
        ref.read(relayHostProvider).apply();
      }
    });
    // Claude Code takes ~10 s to start: start it now, in the background,
    // so the first check or hint is answered in seconds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cfg = ref.read(configProvider);
      if (!AppPaths.isDesktop || !cfg.claudeWarm) return;
      if (cfg.aiProvider != 'claude_code' && cfg.aiProvider != 'auto') return;
      Future<void>.delayed(const Duration(seconds: 3),
          () => ref.read(claudeCodeProvider).prewarm(cfg.fastModel));
    });
    // Tell the user once that their old history was carried over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final report = ref.read(importReportProvider);
      if (report == null || !mounted) return;
      ref.read(importReportProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            AppLocalizations.of(context)!.importedLegacy(report.$1, report.$2)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _syncSoon?.cancel();
    _syncRequests?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(_lastSync) > const Duration(minutes: 2)) {
      _syncExchange();
    }
  }

  Future<void> _syncExchange() async {
    final cfg = ref.read(configProvider);
    final desktop = AppPaths.isDesktop;
    if (_syncing || (!desktop && !cfg.syncServerOn)) return;
    _syncing = true;
    try {
      final ex = ref.read(exchangeProvider);
      final r = ExchangeReport();
      final dir = desktop ? AppPaths.exchangeDirFor(cfg.exchangeDir) : null;
      if (dir != null) r.add(await ex.syncFolder(dir));
      Future<void> server() async {
        if (!cfg.syncServerOn) return;
        try {
          r.add(await ex.syncServer(cfg.syncServerUrl, cfg.syncServerKey));
          ExchangeService.lastServerError = null;
        } catch (e) {
          ExchangeService.lastServerError = '$e';
        }
      }

      await server();
      final graded =
          desktop ? await ref.read(feedTaskGraderProvider).gradePending() : 0;
      // Thoughts dictated without AI (on the phone): research them where
      // Claude is — the PC by subscription, the phone with an API key.
      final ideas = await ref.read(ideaEnricherProvider).processPending();
      if (graded > 0 || ideas > 0) {
        if (dir != null) await ex.exportTo(dir);
        await server();
      }
      if (!mounted || (r.total == 0 && graded == 0 && r.errors.isEmpty)) {
        return;
      }
      ref.read(historyVersionProvider.notifier).state++;
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text([
          if (r.total > 0)
            l.exchangeReport(r.items, r.mistakes, r.feedItems, r.tasksUpdated,
                r.translations),
          if (graded > 0) l.exchangeGraded(graded),
          // A file that could not be merged (locked, from a newer version)
          // must not fail silently: the other device's work would be lost.
          if (r.errors.isNotEmpty) l.exchangeErrors(r.errors.join('; ')),
        ].join('\n')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } catch (_) {
      // Exchange is best-effort: a locked or foreign file must not bother
      // the user at startup; Settings → Exchange shows errors on demand.
    } finally {
      _syncing = false;
      _lastSync = DateTime.now();
    }
  }

  Future<void> _setupShareIntent() async {
    // Text shared while app was closed
    try {
      final text = await _channel.invokeMethod<String>('getInitialText');
      if (text != null && text.isNotEmpty) {
        await _channel.invokeMethod('reset');
        _openTranslateWithText(text);
      }
    } catch (_) {}

    // Text shared while app is running
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) {
          _openTranslateWithText(text);
        }
      }
    });
  }

  void _openTranslateWithText(String text) {
    setState(() {
      _sharedText = text;
      _currentIndex = _translateTab;
    });
    // TranslateScreen only reads initialText in initState — when the app is
    // already running the widget is alive, so hand the text over reactively.
    ref.read(sharedTextProvider.notifier).state = text;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          FeedScreen(key: _tabKeys[0]),
          TranslateScreen(
            key: _tabKeys[1],
            initialText: _sharedText,
          ),
          IdeasScreen(key: _tabKeys[2]),
          CorrectionScreen(key: _tabKeys[3]),
          AnalyticsScreen(key: _tabKeys[4]),
          SettingsScreen(key: _tabKeys[5]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        // Six tabs: labels only under the selected one, so they fit a phone.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.newspaper_rounded),
            label: l.tabFeed,
          ),
          NavigationDestination(
            icon: const Icon(Icons.translate_rounded),
            label: l.tabTranslate,
          ),
          NavigationDestination(
            icon: const Icon(Icons.lightbulb_outline_rounded),
            label: l.tabIdeas,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_fix_high_rounded),
            // NOT "Polish" — in a translator app that reads as the language.
            label: l.tabCorrect,
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_rounded),
            label: l.tabPatterns,
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune_rounded),
            label: l.tabSettings,
          ),
        ],
      ),
    );
  }
}
