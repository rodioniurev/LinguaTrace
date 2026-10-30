import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'settings_store.dart';

// Default on-device LLM. Must be an UNGATED Hugging Face repo — verified by
// HEAD request: litert-community Qwen2.5 returns 302 (open), while
// Gemma3-1B-IT / Llama-3.2 return 401 (license-gated, need a token).
const kGatedGemmaUrl =
    'https://huggingface.co/litert-community/Gemma3-1B-IT/'
    'resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv2048.task';
const kQwen15bUrl =
    'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/'
    'resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task';
const kQwen05bUrl =
    'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/'
    'resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task';

/// URLs the app itself has ever shipped as a default — only these get
/// migrated, so a URL the user typed by hand is never overwritten.
const kShippedDefaultUrls = {kGatedGemmaUrl, kQwen15bUrl, kQwen05bUrl};

bool get kIsMobileTarget =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Phones get the 0.5B build (~550 MB): the 1.5B one is a 1.6 GB download and
/// needs about as much RAM again to run, which is too much for a handset.
String get kDefaultLocalLlmUrl => kIsMobileTarget ? kQwen05bUrl : kQwen15bUrl;
String get kDefaultLocalLlmName => kIsMobileTarget
    ? 'Qwen2.5 0.5B (q8, ~550 МБ)'
    : 'Qwen2.5 1.5B (q8, ~1,6 ГБ)';

/// Claude models offered in Settings (same ids for the API and for the
/// Claude Code CLI). Order = recommendation order in the picker.
const kClaudeModels = <String, String>{
  'claude-opus-5-5': 'Claude Opus 5.5',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5',
  'claude-haiku-5-5': 'Claude Haiku 5.5',
  'claude-opus-5': 'Claude Opus 5',
  'claude-sonnet-5': 'Claude Sonnet 5',
};

class ConfigService extends ChangeNotifier {
  SettingsStore? _store;

  /// Where settings are persisted (shown in Diagnostics).
  String get storeLocation => _store?.location ?? '—';

  /// Last persistence failure, or null. Surfaced in Settings — a settings
  /// write used to fail silently, which is how an API key could vanish.
  String? lastSaveError;

  // ── language pair
  String sourceLang = 'auto';
  String targetLang = 'ru';

  // ── learner profile: what the app is developing
  /// The user's native language (explanations are written in it).
  String nativeLang = 'ru';
  /// The language whose idioms/mistakes/feed the app trains.
  String learningLang = 'es';
  /// Check text the user writes in [learningLang] in the background and
  /// record real mistakes — the main source of "my problem constructions".
  bool autoCheckOwnText = true;

  // ── exchange: one file per device in one folder (desktop)
  /// Folder holding the exchange files; empty = <data>/exchange. Pointing
  /// it at a cloud-synced folder (OneDrive) makes it the single shared place.
  String exchangeDir = '';
  /// Put every translation into the exchange file, not only short lookups
  /// (long texts — letters — stay on the device by default).
  bool exchangeFullHistory = false;

  // ── preferred translator
  String preferredTranslator = 'google'; // google | deepl | yandex | ollama

  // ── API keys
  String deeplApiKey = '';
  String yandexApiKey = '';

  // ── Ollama
  String ollamaUrl = 'http://localhost:11434';
  String ollamaModel = 'qwen2.5:3b';

  // ── enabled translators
  bool googleEnabled = true;
  bool deeplEnabled = false;
  bool yandexEnabled = false;
  bool ollamaEnabled = false;

  // ── offline mode: use ML Kit on-device translation (no internet required)
  bool offlineMode = false;

  // ── On-device LLM (flutter_gemma + LiteRT-LM)
  /// Whether to prefer the local LLM over ML Kit when both are available.
  bool localLlmEnabled = false;
  /// Source URL for the .task / .litertlm model file.
  /// Default: Qwen2.5 1.5B Instruct q8 (~1.6 GB) — the litert-community
  /// Gemma/Llama builds are gated on Hugging Face (download dies with 401
  /// unless the user has a token + accepted license); Qwen is open AND
  /// stronger for RU/ES.
  String localLlmModelUrl = kDefaultLocalLlmUrl;
  /// Display name shown in Settings.
  String localLlmModelName = kDefaultLocalLlmName;
  /// Set to true once a model finishes downloading.
  bool localLlmInstalled = false;
  /// Optional HuggingFace token — needed for gated models (e.g. Gemma 2/3 raw).
  String huggingFaceToken = '';

  // ── Cloud AI assistant (cultural context, corrections, training corpus)
  /// 'claude_code' (Claude via the user's subscription, through the local
  /// Claude Code CLI — desktop only) | 'claude' (API key) | 'chatgpt' |
  /// 'custom' | 'auto'.
  String aiProvider = AppPaths.isDesktop ? 'claude_code' : 'claude';
  /// Optional explicit path to the `claude` executable (else PATH lookup).
  String claudeCodePath = '';
  /// Long-lived subscription token from `claude setup-token` (optional):
  /// replaces the CLI's own login, which can expire. Not an API key.
  String claudeCodeToken = '';

  // ── «Идеи»: dictated thoughts for articles and inventions
  /// Dictation language (ru | es | en).
  String ideasLang = 'ru';
  /// Let the background research search the web (API: $10 per 1,000
  /// searches, at most 5 per note; subscription: Claude Code's search).
  bool ideasWebSearch = true;
  /// Mute the media sound while dictating: the recogniser beeps whenever it
  /// (re)starts.
  bool dictationMuteBeeps = true;
  /// Dictate through the Bluetooth headset's microphone (Android 12+).
  bool dictationBluetooth = false;

  // ── Sync server (server/ in the project): every device's exchange file
  // in one place, synced automatically.
  String syncServerUrl = '';
  String syncServerKey = '';
  bool get syncServerOn =>
      syncServerUrl.trim().isNotEmpty && syncServerKey.trim().isNotEmpty;

  // ── «Claude для телефона»: the PC answers the phone's AI requests
  /// PC side: serve the phone (LAN / Tailscale) with this PC's Claude.
  bool relayServerEnabled = false;
  int relayPort = 8765;
  /// PC side: the pairing code the phone must send.
  String relayCode = '';
  /// Phone side: the PC's address ("192.168.1.23:8765") and pairing code.
  String relayUrl = '';
  String relayClientCode = '';
  String anthropicApiKey = '';
  String openaiApiKey = '';
  String anthropicModel = 'claude-opus-5-5';
  /// Model for quick, interactive answers (text check, hints, word choice,
  /// origins): much faster than Opus, still strong. [anthropicModel] writes
  /// the feed and trainings.
  String fastModel = 'claude-sonnet-5-5';
  /// Keep Claude Code running between requests (desktop): answers in ~1–3 s
  /// instead of ~10+ s, at the cost of ~150–250 MB of memory per process.
  bool claudeWarm = true;
  String openaiModel = 'gpt-4o-mini';

  /// Any OpenAI-compatible endpoint. Lets the app use free services without
  /// new code: Google Gemini free tier, Groq, OpenRouter free models, or a
  /// local LM Studio / llama.cpp server. Base URL ends before
  /// `/chat/completions`, e.g.
  /// `https://generativelanguage.googleapis.com/v1beta/openai`.
  String customApiBaseUrl = '';
  String customApiKey = '';
  String customModel = '';

  // ── theme
  String themeMode = 'dark'; // 'dark', 'medium', 'light'

  // ── font size
  double fontSize = 15.0;

  /// [store] is for tests; production picks the platform store.
  Future<void> init({SettingsStore? store}) async {
    _store = store ??
        (AppPaths.isDesktop
            ? await JsonFileSettingsStore.open(
                AppPaths.settingsPath,
                seedFrom: () => _legacySeed,
              )
            : await PrefsSettingsStore.open());
    final s = _store!;
    sourceLang = s.getString('source_lang') ?? 'auto';
    targetLang = s.getString('target_lang') ?? 'ru';
    nativeLang = s.getString('native_lang') ?? 'ru';
    learningLang = s.getString('learning_lang') ?? 'es';
    autoCheckOwnText = s.getBool('auto_check_own_text') ?? true;
    exchangeDir = s.getString('exchange_dir') ?? '';
    exchangeFullHistory = s.getBool('exchange_full_history') ?? false;
    preferredTranslator = s.getString('preferred_translator') ?? 'google';
    deeplApiKey = s.getString('deepl_api_key') ?? '';
    yandexApiKey = s.getString('yandex_api_key') ?? '';
    ollamaUrl = s.getString('ollama_url') ?? 'http://localhost:11434';
    // 3B, not 7B: the default has to be usable on a CPU-only machine.
    ollamaModel = s.getString('ollama_model') ?? 'qwen2.5:3b';
    googleEnabled = s.getBool('google_enabled') ?? true;
    deeplEnabled = s.getBool('deepl_enabled') ?? false;
    yandexEnabled = s.getBool('yandex_enabled') ?? false;
    ollamaEnabled = s.getBool('ollama_enabled') ?? false;
    offlineMode = s.getBool('offline_mode') ?? false;
    localLlmEnabled = s.getBool('local_llm_enabled') ?? false;
    localLlmModelUrl = s.getString('local_llm_model_url') ?? localLlmModelUrl;
    localLlmModelName = s.getString('local_llm_model_name') ?? localLlmModelName;
    localLlmInstalled = s.getBool('local_llm_installed') ?? false;
    // Move a stale shipped default onto the current one — the gated Gemma URL
    // (401 on download) and the desktop-sized model on a phone. Only exact
    // matches migrate, and only while nothing is installed.
    if (!localLlmInstalled &&
        kShippedDefaultUrls.contains(localLlmModelUrl) &&
        localLlmModelUrl != kDefaultLocalLlmUrl) {
      localLlmModelUrl = kDefaultLocalLlmUrl;
      localLlmModelName = kDefaultLocalLlmName;
    }
    huggingFaceToken = s.getString('hugging_face_token') ?? '';
    aiProvider = s.getString('ai_provider') ?? aiProvider;
    claudeCodePath = s.getString('claude_code_path') ?? '';
    claudeCodeToken = s.getString('claude_code_oauth_token') ?? '';
    ideasLang = s.getString('ideas_lang') ?? 'ru';
    ideasWebSearch = s.getBool('ideas_web_search') ?? true;
    dictationMuteBeeps = s.getBool('dictation_mute_beeps') ?? true;
    dictationBluetooth = s.getBool('dictation_bluetooth') ?? false;
    // A new key: 'sync_server_url' held the old Python server's address.
    syncServerUrl = s.getString('sync_server_address') ?? '';
    syncServerKey = s.getString('sync_server_key') ?? '';
    relayServerEnabled = s.getBool('relay_server_enabled') ?? false;
    relayPort = int.tryParse(s.getString('relay_port') ?? '') ?? 8765;
    relayCode = s.getString('relay_code') ?? '';
    relayUrl = s.getString('relay_url') ?? '';
    relayClientCode = s.getString('relay_client_code') ?? '';
    anthropicApiKey = s.getString('anthropic_api_key') ?? '';
    // Desktop: "Claude" without an API key was the state in which Claude
    // "never worked". The subscription route needs no key, so move there.
    if (AppPaths.isDesktop &&
        aiProvider == 'claude' &&
        anthropicApiKey.isEmpty) {
      aiProvider = 'claude_code';
    }
    openaiApiKey = s.getString('openai_api_key') ?? '';
    anthropicModel = s.getString('anthropic_model') ?? 'claude-opus-5-5';
    fastModel = s.getString('fast_model') ?? 'claude-sonnet-5-5';
    // Opus 5.5 and Sonnet 5.5 succeed the old defaults (newer; Opus is
    // cheaper too): move once, a later explicit choice is kept.
    if (!(s.getBool('claude_models_55') ?? false)) {
      if (anthropicModel == 'claude-opus-5') anthropicModel = 'claude-opus-5-5';
      if (fastModel == 'claude-sonnet-5') fastModel = 'claude-sonnet-5-5';
    }
    if (!kClaudeModels.containsKey(anthropicModel)) {
      anthropicModel = 'claude-opus-5-5';
    }
    if (!kClaudeModels.containsKey(fastModel)) fastModel = 'claude-sonnet-5-5';
    claudeWarm = s.getBool('claude_warm') ?? true;
    openaiModel = s.getString('openai_model') ?? 'gpt-4o-mini';
    customApiBaseUrl = s.getString('custom_api_base_url') ?? '';
    customApiKey = s.getString('custom_api_key') ?? '';
    customModel = s.getString('custom_model') ?? '';
    themeMode = s.getString('theme_mode') ?? 'dark';
    fontSize = s.getDouble('font_size') ?? 15.0;
  }

  /// SharedPreferences values from before the desktop JSON store existed,
  /// loaded by main() so the first run keeps the user's old settings.
  static Map<String, Object?> _legacySeed = const {};
  static set legacySeed(Map<String, Object?> raw) {
    // The Windows plugin stores keys as 'flutter.<key>'.
    _legacySeed = {
      for (final e in raw.entries)
        (e.key.startsWith('flutter.') ? e.key.substring(8) : e.key): e.value,
    };
  }

  Future<void> save() async {
    final s = _store;
    if (s != null) {
      s
        ..set('source_lang', sourceLang)
        ..set('target_lang', targetLang)
        ..set('native_lang', nativeLang)
        ..set('learning_lang', learningLang)
        ..set('auto_check_own_text', autoCheckOwnText)
        ..set('exchange_dir', exchangeDir)
        ..set('exchange_full_history', exchangeFullHistory)
        ..set('preferred_translator', preferredTranslator)
        ..set('deepl_api_key', deeplApiKey)
        ..set('yandex_api_key', yandexApiKey)
        ..set('ollama_url', ollamaUrl)
        ..set('ollama_model', ollamaModel)
        ..set('google_enabled', googleEnabled)
        ..set('deepl_enabled', deeplEnabled)
        ..set('yandex_enabled', yandexEnabled)
        ..set('ollama_enabled', ollamaEnabled)
        ..set('offline_mode', offlineMode)
        ..set('local_llm_enabled', localLlmEnabled)
        ..set('local_llm_model_url', localLlmModelUrl)
        ..set('local_llm_model_name', localLlmModelName)
        ..set('local_llm_installed', localLlmInstalled)
        ..set('hugging_face_token', huggingFaceToken)
        ..set('ai_provider', aiProvider)
        ..set('claude_code_path', claudeCodePath)
        ..set('claude_code_oauth_token', claudeCodeToken)
        ..set('ideas_lang', ideasLang)
        ..set('ideas_web_search', ideasWebSearch)
        ..set('dictation_mute_beeps', dictationMuteBeeps)
        ..set('dictation_bluetooth', dictationBluetooth)
        ..set('sync_server_address', syncServerUrl)
        ..set('sync_server_key', syncServerKey)
        ..set('relay_server_enabled', relayServerEnabled)
        ..set('relay_port', '$relayPort')
        ..set('relay_code', relayCode)
        ..set('relay_url', relayUrl)
        ..set('relay_client_code', relayClientCode)
        ..set('anthropic_api_key', anthropicApiKey)
        ..set('openai_api_key', openaiApiKey)
        ..set('anthropic_model', anthropicModel)
        ..set('fast_model', fastModel)
        ..set('claude_models_55', true)
        ..set('claude_warm', claudeWarm)
        ..set('openai_model', openaiModel)
        ..set('custom_api_base_url', customApiBaseUrl)
        ..set('custom_api_key', customApiKey)
        ..set('custom_model', customModel)
        ..set('theme_mode', themeMode)
        ..set('font_size', fontSize);
      try {
        await s.flush();
        lastSaveError = null;
      } catch (e) {
        lastSaveError = e.toString();
      }
    }
    notifyListeners();
  }
}
