import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/config.dart';
import '../core/database.dart';
import '../services/ai_client.dart';
import '../services/claude_code_client.dart';
import '../services/correction_service.dart';
import '../services/cultural_context_service.dart';
import '../services/dictionary_service.dart';
import '../services/etymology_service.dart';
import '../services/explanation_service.dart';
import '../services/exchange_service.dart';
import '../services/relay_server.dart';
import '../services/feed_composer.dart';
import '../services/feed_task_grader.dart';
import '../services/idea_enricher.dart';
import '../services/llm_router.dart';
import '../services/local_llm_service.dart';
import '../services/proverb_service.dart';
import '../services/source_ingest.dart';
import '../services/training_service.dart';
import '../services/translator_service.dart';
import '../services/linguistics_service.dart';
import '../services/voice_service.dart';
import '../services/word_choice_service.dart';

final databaseProvider = Provider<DatabaseService>((ref) {
  throw UnimplementedError('Override in main');
});

final configProvider = ChangeNotifierProvider<ConfigService>((ref) {
  throw UnimplementedError('Override in main');
});

// Services read the (single, mutable) ConfigService at call time, so they
// take it with ref.read: watching it rebuilt every service on each save —
// which disposed the loaded on-device model and orphaned installs.

final translatorProvider = Provider<TranslatorService>((ref) {
  final config = ref.read(configProvider);
  final localLlm = ref.watch(localLlmProvider);
  return TranslatorService(config, localLlm: localLlm);
});

final localLlmProvider = ChangeNotifierProvider<LocalLlmService>((ref) {
  return LocalLlmService(ref.read(configProvider));
});

/// Claude via the user's subscription (desktop, local Claude Code CLI).
final claudeCodeProvider = Provider<ClaudeCodeClient>((ref) {
  final config = ref.read(configProvider);
  return ClaudeCodeClient(
    pathOverride: () => config.claudeCodePath,
    workDir: () => p.join(AppPaths.dataDir, 'claude-cwd'),
    oauthToken: () => config.claudeCodeToken,
    warm: () => config.claudeWarm,
  );
});

final aiClientProvider = Provider<AiClient>((ref) {
  return AiClient(
    ref.read(configProvider),
    claudeCode: ClaudeCodeClient.platformSupported
        ? ref.watch(claudeCodeProvider)
        : null,
    usageLog: ref.read(databaseProvider),
  );
});

/// Cloud-first LLM chain (cloud → Ollama → on-device) used by every
/// feature that needs free-form text.
final llmRouterProvider = Provider<LlmRouter>((ref) {
  return LlmRouter(
    ref.read(configProvider),
    local: ref.watch(localLlmProvider),
    ai: ref.watch(aiClientProvider),
  );
});

/// Desktop: answers the phone's AI requests with this PC's Claude
/// («Claude для телефона»). Only the chosen provider — no slow fallbacks.
final relayHostProvider = ChangeNotifierProvider<RelayHost>((ref) {
  return RelayHost(
    ref.read(configProvider),
    (req) => ref.read(llmRouterProvider).completeResult(
          system: req.system,
          user: req.user,
          maxTokens: req.maxTokens,
          effort: req.effort,
          jsonSchema: req.jsonSchema,
          timeout: req.timeout,
          allowOnDevice: false,
          fallback: false,
          tier: req.tier,
          webSearch: req.web,
          feature: 'phone:${req.feature}',
        ),
  );
});

/// «Происхождение и история» pages (Claude + Wiktionary), stored in the DB.
final etymologyProvider = Provider<EtymologyService>((ref) {
  return EtymologyService(ref.watch(llmRouterProvider), ref.read(databaseProvider));
});

/// «Идеи»: background research for dictated notes, and article import.
final ideaEnricherProvider = Provider<IdeaEnricher>((ref) {
  return IdeaEnricher(ref.watch(llmRouterProvider), ref.read(databaseProvider),
      ref.read(configProvider));
});

final sourceIngestProvider = Provider<SourceIngest>((ref) {
  return SourceIngest(ref.watch(llmRouterProvider));
});

/// «Подбор слова»: options for a word the machine translation got wrong.
final wordChoiceProvider = Provider<WordChoiceService>((ref) {
  return WordChoiceService(ref.watch(llmRouterProvider));
});

final culturalContextProvider = Provider<CulturalContextService>((ref) {
  return CulturalContextService(ref.watch(llmRouterProvider));
});

final explanationProvider = Provider<ExplanationService>((ref) {
  return ExplanationService(ref.watch(llmRouterProvider));
});

final trainingProvider = Provider<TrainingService>((ref) {
  final llm = ref.watch(llmRouterProvider);
  final db = ref.watch(databaseProvider);
  return TrainingService(llm, db);
});

final correctionProvider = Provider<CorrectionService>((ref) {
  return CorrectionService(ref.watch(llmRouterProvider));
});

/// News-feed trainer (RSS → personal retellings with the user's targets).
final feedComposerProvider = Provider<FeedComposer>((ref) {
  return FeedComposer(ref.watch(llmRouterProvider), ref.read(databaseProvider));
});

final feedTaskGraderProvider = Provider<FeedTaskGrader>((ref) {
  return FeedTaskGrader(ref.read(databaseProvider),
      ref.watch(correctionProvider), ref.read(configProvider));
});

/// One exchange file per device: history, notebook, mistakes, trainings,
/// feed editions and answers — merged on the other device.
final exchangeProvider = Provider<ExchangeService>((ref) {
  final cfg = ref.read(configProvider);
  return ExchangeService(ref.read(databaseProvider),
      fullHistory: () => cfg.exchangeFullHistory);
});

final linguisticsProvider = Provider<LinguisticsService>((ref) {
  final config = ref.read(configProvider);
  final dictionary = ref.watch(dictionaryProvider);
  return LinguisticsService(config, dictionary: dictionary);
});

final voiceProvider = Provider<VoiceService>((ref) {
  throw UnimplementedError('Override in main');
});

final dictionaryProvider = Provider<DictionaryService>((ref) {
  throw UnimplementedError('Override in main');
});

final proverbProvider = Provider<ProverbService>((ref) {
  throw UnimplementedError('Override in main');
});

/// Bumped after every saved translation / mistake / notebook change so
/// History, Insights and Notebook know to reload — IndexedStack keeps their
/// state alive, initState never re-runs.
final historyVersionProvider = StateProvider<int>((ref) => 0);

/// Text shared into the app (Android share intent / PROCESS_TEXT) while it
/// is already running. TranslateScreen listens and consumes it.
final sharedTextProvider = StateProvider<String?>((ref) => null);

/// Legacy databases merged on this start: (files, rows) — shown once.
final importReportProvider = StateProvider<(int, int)?>((ref) => null);
