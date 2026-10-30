/// Translation service — supports Google (free), DeepL, Yandex, Ollama.
/// Also supports offline on-device translation via Google ML Kit.
/// Mirrors the Python translators/manager.py fallback logic.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../core/config.dart';
import '../core/database.dart';
import '../core/languages.dart';
import 'local_llm_service.dart';

class TranslationResult {
  final String text;
  final String sourceLang;
  final String targetLang;
  final String translator;

  const TranslationResult({
    required this.text,
    required this.sourceLang,
    required this.targetLang,
    required this.translator,
  });
}

// ══════════════════════════════════════════════════════════
// Individual backends
// ══════════════════════════════════════════════════════════

Future<TranslationResult> _googleTranslate(
    String text, String src, String tgt) async {
  // For single words, request alternative translations + dictionary data
  final isSingle = !text.contains(' ');
  final dtParams = isSingle ? '&dt=t&dt=at&dt=bd' : '&dt=t';

  final url = Uri.parse(
    'https://translate.googleapis.com/translate_a/single'
    '?client=gtx'
    '&sl=${Uri.encodeComponent(src)}'
    '&tl=${Uri.encodeComponent(tgt)}'
    '$dtParams'
    '&q=${Uri.encodeComponent(text)}',
  );

  final resp = await http.get(url, headers: {'User-Agent': 'Mozilla/5.0'})
      .timeout(const Duration(seconds: 8));

  if (resp.statusCode != 200) {
    throw Exception('Google Translate HTTP ${resp.statusCode}');
  }

  final data = jsonDecode(resp.body);

  // Primary translation
  final buffer = StringBuffer();
  final sentences = data[0] as List;
  for (final s in sentences) {
    if (s is List && s.isNotEmpty && s[0] is String) {
      buffer.write(s[0]);
    }
  }
  var mainTranslation = buffer.toString();
  if (mainTranslation.trim().isEmpty) {
    // Some inputs (emoji, single punctuation) return only metadata.
    // Better to surface as an error so the fallback chain proceeds than to
    // store/show an empty translation that looks like success.
    throw Exception('Google Translate returned empty result');
  }

  // For single words: check dictionary data for better translation
  // data[1] contains alternative translations grouped by PoS
  if (isSingle && data.length > 1 && data[1] is List) {
    final alts = data[1] as List;
    // Check if source looks like a verb (common infinitive endings)
    final lower = text.toLowerCase();
    final looksLikeVerb = lower.endsWith('ar') || lower.endsWith('er') ||
        lower.endsWith('ir') || lower.endsWith('ть') || lower.endsWith('ться') ||
        lower.endsWith('en') || lower.endsWith('re');

    for (final group in alts) {
      if (group is! List || group.length < 3) continue;
      final pos = (group[0] as String? ?? '').toLowerCase();
      final translations = group[2] as List? ?? [];

      // If source looks like a verb, prefer verb translations
      if (looksLikeVerb && (pos == 'verb' || pos == 'глагол' || pos == 'verbo')) {
        if (translations.isNotEmpty && translations[0] is List) {
          final verbTrans = translations[0][0] as String?;
          if (verbTrans != null && verbTrans.isNotEmpty) {
            mainTranslation = verbTrans;
            break;
          }
        }
      }
    }
  }

  final detectedSrc = (data.length > 2 && data[2] != null)
      ? data[2].toString()
      : src;

  return TranslationResult(
    text: mainTranslation,
    sourceLang: detectedSrc,
    targetLang: tgt,
    translator: 'google',
  );
}

Future<TranslationResult> _deeplTranslate(
    String text, String src, String tgt, String apiKey) async {
  // DeepL free API uses api-free.deepl.com; paid uses api.deepl.com
  final host = apiKey.endsWith(':fx')
      ? 'api-free.deepl.com'
      : 'api.deepl.com';

  final resp = await http.post(
    Uri.https(host, '/v2/translate'),
    headers: {
      'Authorization': 'DeepL-Auth-Key $apiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'text': [text],
      'target_lang': tgt.toUpperCase().replaceAll('-', '_'),
      if (src != 'auto') 'source_lang': src.toUpperCase(),
    }),
  ).timeout(const Duration(seconds: 15));

  if (resp.statusCode != 200) {
    throw Exception('DeepL HTTP ${resp.statusCode}: ${resp.body}');
  }

  final data = jsonDecode(resp.body);
  final translation = data['translations'][0];
  // detected_source_language is only present when src=auto; when the caller
  // passes an explicit source DeepL omits it and `as String` would throw.
  final detected = (translation['detected_source_language'] as String?)?.toLowerCase();
  return TranslationResult(
    text: translation['text'] as String,
    sourceLang: detected ?? (src == 'auto' ? 'auto' : src),
    targetLang: tgt,
    translator: 'deepl',
  );
}

Future<TranslationResult> _yandexTranslate(
    String text, String src, String tgt, String apiKey) async {
  final resp = await http.post(
    Uri.parse('https://translate.api.cloud.yandex.net/translate/v2/translate'),
    headers: {
      'Authorization': 'Api-Key $apiKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'texts': [text],
      'targetLanguageCode': tgt,
      if (src != 'auto') 'sourceLanguageCode': src,
    }),
  ).timeout(const Duration(seconds: 15));

  if (resp.statusCode != 200) {
    throw Exception('Yandex HTTP ${resp.statusCode}: ${resp.body}');
  }

  final data = jsonDecode(resp.body);
  final translation = data['translations'][0];
  return TranslationResult(
    text: translation['text'] as String,
    sourceLang: translation['detectedLanguageCode'] as String? ?? src,
    targetLang: tgt,
    translator: 'yandex',
  );
}

Future<TranslationResult> _ollamaTranslate(
    String text, String src, String tgt, String baseUrl, String model) async {
  final tgtName = langName(tgt);
  final srcHint = src != 'auto' ? ' from ${langName(src)}' : '';
  final prompt =
      'Translate the following text$srcHint to $tgtName. '
      'Output ONLY the translation, no explanations, no quotes.\n\n$text';

  final resp = await http.post(
    Uri.parse('$baseUrl/api/generate'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'model': model,
      'prompt': prompt,
      'stream': false,
      'options': {'temperature': 0.1},
    }),
  ).timeout(const Duration(seconds: 90));

  if (resp.statusCode != 200) {
    throw Exception('Ollama HTTP ${resp.statusCode}');
  }

  final data = jsonDecode(resp.body);
  final response = (data['response'] as String?)?.trim();
  if (response == null || response.isEmpty) {
    throw Exception('Ollama returned empty response');
  }
  return TranslationResult(
    text: response,
    sourceLang: src,
    targetLang: tgt,
    translator: 'ollama/$model',
  );
}

// ══════════════════════════════════════════════════════════
// ML Kit language code mapping
// ══════════════════════════════════════════════════════════

/// Map ISO-639-1 code → ML Kit TranslateLanguage.
TranslateLanguage? _toMlKitLang(String code) {
  const map = <String, TranslateLanguage>{
    'af': TranslateLanguage.afrikaans,
    'ar': TranslateLanguage.arabic,
    'be': TranslateLanguage.belarusian,
    'bg': TranslateLanguage.bulgarian,
    'bn': TranslateLanguage.bengali,
    'ca': TranslateLanguage.catalan,
    'cs': TranslateLanguage.czech,
    'cy': TranslateLanguage.welsh,
    'da': TranslateLanguage.danish,
    'de': TranslateLanguage.german,
    'el': TranslateLanguage.greek,
    'en': TranslateLanguage.english,
    'eo': TranslateLanguage.esperanto,
    'es': TranslateLanguage.spanish,
    'et': TranslateLanguage.estonian,
    'fa': TranslateLanguage.persian,
    'fi': TranslateLanguage.finnish,
    'fr': TranslateLanguage.french,
    'ga': TranslateLanguage.irish,
    'gl': TranslateLanguage.galician,
    'gu': TranslateLanguage.gujarati,
    'he': TranslateLanguage.hebrew,
    'hi': TranslateLanguage.hindi,
    'hr': TranslateLanguage.croatian,
    'hu': TranslateLanguage.hungarian,
    'id': TranslateLanguage.indonesian,
    'is': TranslateLanguage.icelandic,
    'it': TranslateLanguage.italian,
    'ja': TranslateLanguage.japanese,
    'ka': TranslateLanguage.georgian,
    'kn': TranslateLanguage.kannada,
    'ko': TranslateLanguage.korean,
    'lt': TranslateLanguage.lithuanian,
    'lv': TranslateLanguage.latvian,
    'mk': TranslateLanguage.macedonian,
    'mr': TranslateLanguage.marathi,
    'ms': TranslateLanguage.malay,
    'mt': TranslateLanguage.maltese,
    'nl': TranslateLanguage.dutch,
    'no': TranslateLanguage.norwegian,
    'pl': TranslateLanguage.polish,
    'pt': TranslateLanguage.portuguese,
    'ro': TranslateLanguage.romanian,
    'ru': TranslateLanguage.russian,
    'sk': TranslateLanguage.slovak,
    'sl': TranslateLanguage.slovenian,
    'sq': TranslateLanguage.albanian,
    'sv': TranslateLanguage.swedish,
    'sw': TranslateLanguage.swahili,
    'ta': TranslateLanguage.tamil,
    'te': TranslateLanguage.telugu,
    'th': TranslateLanguage.thai,
    'tl': TranslateLanguage.tagalog,
    'tr': TranslateLanguage.turkish,
    'uk': TranslateLanguage.ukrainian,
    'ur': TranslateLanguage.urdu,
    'vi': TranslateLanguage.vietnamese,
    'zh': TranslateLanguage.chinese,
  };
  final key = code.length >= 2 ? code.substring(0, 2).toLowerCase() : code;
  return map[key];
}

Future<TranslationResult> _mlKitTranslate(
    String text, String src, String tgt) async {
  // For 'auto' source, default to English detection
  final srcLang = src == 'auto' ? TranslateLanguage.english : _toMlKitLang(src);
  final tgtLang = _toMlKitLang(tgt);

  if (tgtLang == null) {
    throw Exception('ML Kit: unsupported target language: $tgt');
  }

  final translator = OnDeviceTranslator(
    sourceLanguage: srcLang ?? TranslateLanguage.english,
    targetLanguage: tgtLang,
  );

  try {
    // Models must be pre-downloaded (Settings → ML Kit offline models).
    // Downloading silently mid-translation surprised users ("offline" mode
    // pulling 30 MB) and hung the UI for many seconds.
    final modelManager = OnDeviceTranslatorModelManager();
    final srcCode = (srcLang ?? TranslateLanguage.english).bcpCode;
    if (!await modelManager.isModelDownloaded(srcCode) ||
        !await modelManager.isModelDownloaded(tgtLang.bcpCode)) {
      throw Exception(
          'Offline models not downloaded — get them in Settings → ML Kit offline models');
    }

    final result = await translator.translateText(text);
    return TranslationResult(
      text: result,
      sourceLang: src,
      targetLang: tgt,
      translator: 'offline (ML Kit)',
    );
  } finally {
    translator.close();
  }
}

// ══════════════════════════════════════════════════════════
// Orchestrator (mirrors manager.py)
// ══════════════════════════════════════════════════════════

class TranslatorService {
  final ConfigService _config;
  final LocalLlmService? _localLlm;

  TranslatorService(this._config, {LocalLlmService? localLlm})
      : _localLlm = localLlm;

  /// Translate text — uses offline backends when offlineMode is enabled,
  /// otherwise tries preferred backend first, then falls back.
  Future<TranslationResult> translate(
    String text, {
    String? targetLang,
    String? sourceLang,
  }) async {
    final tgt = targetLang ?? _config.targetLang;
    final src = sourceLang ?? _config.sourceLang;

    // Offline mode: prefer local LLM (better quality), fall back to ML Kit.
    if (_config.offlineMode) {
      if (_localLlm != null && _localLlm!.isUsable) {
        try {
          final out = await _localLlm!.translate(text, src, tgt);
          return TranslationResult(
            text: out,
            sourceLang: src,
            targetLang: tgt,
            translator: 'on-device LLM',
          );
        } catch (_) {
          // Fall back to ML Kit if the LLM trips
        }
      }
      return _mlKitTranslate(text, src, tgt);
    }

    // Online mode: preferred backend with fallback chain
    final order = <String>[_config.preferredTranslator];
    for (final name in ['google', 'deepl', 'yandex', 'ollama']) {
      if (!order.contains(name)) order.add(name);
    }

    Exception? last;
    for (final name in order) {
      if (!_isEnabled(name)) continue;
      try {
        return await _callBackend(name, text, src, tgt);
      } on Exception catch (e) {
        last = e;
      }
    }
    throw last ?? Exception('No translator available');
  }

  /// Cache → online translators → on-device fallback.
  ///
  /// Online comes first when the user is not in offline mode: Google/DeepL
  /// answer in well under a second and far better than the on-device
  /// models. Before, a downloaded ML Kit model (or the on-device LLM) was
  /// preferred whenever present — slower on the phone and much weaker
  /// ("qué yo debo llevar al proyecto" for «что я должен привнести в
  /// проект»). The on-device models now step in only without a network.
  Future<TranslationResult> translateWithCache(
    String text,
    DatabaseService db, {
    String? targetLang,
    String? sourceLang,
  }) async {
    final tgt = targetLang ?? _config.targetLang;
    final src = sourceLang ?? _config.sourceLang;

    // L1: SQLite cache (~0 ms), also for an auto-detected source.
    final cached = await db.cacheLookup(
      sourceText: text,
      sourceLang: src,
      targetLang: tgt,
    );
    if (cached != null) {
      return TranslationResult(
        text: cached.translatedText,
        sourceLang: cached.sourceLang,
        targetLang: cached.targetLang,
        translator: '${cached.translator} (cached)',
      );
    }

    // Offline mode: on-device only (translate() handles it).
    if (_config.offlineMode) {
      return translate(text, targetLang: tgt, sourceLang: src);
    }

    // L2: online translators.
    try {
      return await translate(text, targetLang: tgt, sourceLang: src);
    } catch (e) {
      // L3: no network — the on-device models, if any.
      final offline = await _onDevice(text, src, tgt);
      if (offline != null) return offline;
      rethrow;
    }
  }

  /// On-device LLM, then ML Kit when its models are downloaded; null when
  /// neither is available.
  Future<TranslationResult?> _onDevice(String text, String src, String tgt) async {
    if (_localLlm != null && _localLlm!.isUsable) {
      try {
        final out = await _localLlm!.translate(text, src, tgt);
        return TranslationResult(
          text: out,
          sourceLang: src,
          targetLang: tgt,
          translator: 'on-device LLM',
        );
      } catch (_) {}
    }
    try {
      final srcLang = src == 'auto' ? null : _toMlKitLang(src);
      final tgtLang = _toMlKitLang(tgt);
      if (tgtLang != null) {
        final modelManager = OnDeviceTranslatorModelManager();
        final srcCode = (srcLang ?? TranslateLanguage.english).bcpCode;
        final srcReady = await modelManager.isModelDownloaded(srcCode);
        final tgtReady = await modelManager.isModelDownloaded(tgtLang.bcpCode);
        if (srcReady && tgtReady) {
          return await _mlKitTranslate(text, src, tgt);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Download ML Kit models for a language pair (call once per language pair).
  Future<void> downloadOfflineModels(String src, String tgt) async {
    final srcLang = src == 'auto' ? TranslateLanguage.english : _toMlKitLang(src);
    final tgtLang = _toMlKitLang(tgt);
    if (tgtLang == null) return;

    final translator = OnDeviceTranslator(
      sourceLanguage: srcLang ?? TranslateLanguage.english,
      targetLanguage: tgtLang,
    );
    try {
      final modelManager = OnDeviceTranslatorModelManager();
      final srcCode2 = (srcLang ?? TranslateLanguage.english).bcpCode;
      if (!await modelManager.isModelDownloaded(srcCode2)) {
        await modelManager.downloadModel(srcCode2);
      }
      if (!await modelManager.isModelDownloaded(tgtLang.bcpCode)) {
        await modelManager.downloadModel(tgtLang.bcpCode);
      }
    } finally {
      translator.close();
    }
  }

  bool _isEnabled(String name) {
    switch (name) {
      case 'google':
        return _config.googleEnabled;
      case 'deepl':
        return _config.deeplEnabled && _config.deeplApiKey.isNotEmpty;
      case 'yandex':
        return _config.yandexEnabled && _config.yandexApiKey.isNotEmpty;
      case 'ollama':
        return _config.ollamaEnabled;
      default:
        return false;
    }
  }

  Future<TranslationResult> _callBackend(
      String name, String text, String src, String tgt) {
    switch (name) {
      case 'google':
        return _googleTranslate(text, src, tgt);
      case 'deepl':
        return _deeplTranslate(text, src, tgt, _config.deeplApiKey);
      case 'yandex':
        return _yandexTranslate(text, src, tgt, _config.yandexApiKey);
      case 'ollama':
        return _ollamaTranslate(
            text, src, tgt, _config.ollamaUrl, _config.ollamaModel);
      default:
        throw Exception('Unknown backend: $name');
    }
  }
}
