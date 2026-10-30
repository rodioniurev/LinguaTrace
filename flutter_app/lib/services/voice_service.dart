import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'long_dictation.dart';

/// Preferred locale per ISO-639-1 code — used when the device's locale list
/// can't be queried. When it can, [resolveLocale] verifies against it.
const _speechLocales = <String, String>{
  'en': 'en_US',
  'ru': 'ru_RU',
  'es': 'es_ES',
  'de': 'de_DE',
  'fr': 'fr_FR',
  'it': 'it_IT',
  'pt': 'pt_BR',
  'ja': 'ja_JP',
  'ko': 'ko_KR',
  'zh': 'zh_CN',
  'uk': 'uk_UA',
  'tr': 'tr_TR',
};

/// Human-readable messages for the raw speech_to_text error codes.
const _errorMessages = <String, String>{
  'error_no_match': 'Speech not recognized — try speaking again',
  'error_speech_timeout': 'No speech detected',
  'error_audio_error': 'Microphone error',
  'error_network': 'Speech service needs a network connection',
  'error_network_timeout': 'Speech service network timeout',
  'error_insufficient_permissions': 'Microphone permission denied',
  'error_busy': 'Speech recognizer is busy — try again',
  'error_client': 'Speech recognizer unavailable on this device',
  'error_language_not_supported': 'This language is not supported by the recognizer',
  'error_language_unavailable': 'Speech pack for this language is not installed',
};

class VoiceService implements SpeechEngine {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _isListening = false;
  String? lastError;
  List<LocaleName> _locales = const [];

  // Per-session callbacks — set by startListening, cleared on manual stop.
  void Function(String message)? _onError;
  void Function()? _onDone;
  // Long dictation (one segment at a time): raw error codes.
  void Function(String code, bool permanent)? _onSegmentError;

  bool get isListening => _isListening;
  bool get isAvailable => _initialized;

  /// speech_to_text has no Windows/Linux implementation — callers should
  /// hide the mic button entirely on those platforms.
  static bool get isSupportedPlatform =>
      kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Initialize once; safe to call repeatedly. A failed attempt (e.g. mic
  /// permission denied at first launch) is retried on the next call, so the
  /// service recovers after the user grants the permission.
  Future<bool> init() async {
    if (_initialized) return true;
    if (!isSupportedPlatform) {
      lastError = 'Voice input is not supported on this platform';
      return false;
    }
    try {
      _initialized = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
    } catch (e) {
      lastError = e.toString();
      _initialized = false;
    }
    if (_initialized) {
      try {
        _locales = await _speech.locales();
      } catch (_) {
        _locales = const [];
      }
    } else {
      lastError ??=
          'Speech recognition unavailable — check microphone permission';
    }
    return _initialized;
  }

  void _handleStatus(String status) {
    // The engine stops on its own after silence or a final result. Without
    // this hook the UI would stay stuck in the "listening" state forever.
    // A dictation segment ends only at "done": "notListening" comes at the
    // end of speech, before the final result, and starting the next
    // segment then cut that phrase off (and failed with error_client).
    final ended = _onSegmentError != null
        ? status == 'done'
        : status == 'done' || status == 'notListening';
    if (ended && _isListening) {
      _isListening = false;
      _onDone?.call();
    }
  }

  // error_client is not here: it is what a too early restart gets, and the
  // next attempt usually works.
  static const _permanentErrors = {
    'error_permission',
    'error_insufficient_permissions',
    'error_language_not_supported',
    'error_language_unavailable',
  };

  void _handleError(SpeechRecognitionError e) {
    lastError = e.errorMsg;
    final wasListening = _isListening;
    _isListening = false;
    final seg = _onSegmentError;
    if (seg != null) {
      seg(e.errorMsg, _permanentErrors.contains(e.errorMsg));
      return;
    }
    if (wasListening) {
      _onError?.call(
          _errorMessages[e.errorMsg] ?? 'Voice input error: ${e.errorMsg}');
    }
  }

  /// Best locale ID for [lang] ('ru', 'es', ...) among those actually present
  /// on the device. Returns null when the language has no speech pack at all.
  String? resolveLocale(String lang) {
    final two = lang.length >= 2
        ? lang.substring(0, 2).toLowerCase()
        : lang.toLowerCase();
    final preferred = _speechLocales[two];
    if (_locales.isEmpty) return preferred; // can't verify — trust the mapping
    String norm(String id) => id.toLowerCase().replaceAll('-', '_');
    if (preferred != null) {
      for (final l in _locales) {
        if (norm(l.localeId) == norm(preferred)) return l.localeId;
      }
    }
    for (final l in _locales) {
      final n = norm(l.localeId);
      if (n == two || n.startsWith('${two}_')) return l.localeId;
    }
    return null;
  }

  /// Start a dictation session. Returns false (after reporting through
  /// [onError]) when recognition can't start; the caller must reset its UI.
  Future<bool> startListening({
    required String lang,
    required void Function(String text, bool isFinal) onResult,
    void Function(String message)? onError,
    void Function()? onDone,
  }) async {
    if (!await init()) {
      onError?.call(lastError ?? 'Speech recognition unavailable');
      return false;
    }
    final localeId = resolveLocale(lang);
    if (localeId == null) {
      onError?.call(
          'No speech pack for "$lang" on this device — install it in system settings');
      return false;
    }

    _onError = onError;
    _onDone = onDone;
    _onSegmentError = null;
    _isListening = true;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          onResult(r.recognizedWords, r.finalResult);
          if (r.finalResult) _isListening = false;
        },
        localeId: localeId,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 60),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      return true;
    } catch (e) {
      _isListening = false;
      lastError = e.toString();
      onError?.call('Could not start voice input: $e');
      return false;
    }
  }

  /// One segment of a long dictation ([LongDictation]): as long as the
  /// platform allows, ending on a long pause; errors come as raw codes so
  /// the caller can simply start the next segment.
  @override
  Future<bool> startSegment({
    required String lang,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onEnd,
    required void Function(String code, bool permanent) onError,
    void Function(String? trouble)? onTrouble,
    void Function(String line)? onLog,
  }) async {
    if (!await init()) {
      onError('error_init', true);
      return false;
    }
    final localeId = resolveLocale(lang);
    if (localeId == null) {
      onError('error_language_unavailable', true);
      return false;
    }
    _onError = null;
    _onDone = onEnd;
    _onSegmentError = onError;
    _isListening = true;
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          onResult(r.recognizedWords, r.finalResult);
        },
        localeId: localeId,
        pauseFor: const Duration(seconds: 20),
        listenFor: const Duration(minutes: 5),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: true,
        ),
      );
      return true;
    } catch (e) {
      _isListening = false;
      lastError = e.toString();
      return false;
    }
  }

  @override
  Future<void> stopSegment() async {
    _isListening = false;
    _onDone = null;
    _onSegmentError = null;
    await _speech.stop();
  }

  /// The phrase being spoken is finished now; its final result follows and
  /// the dictation starts the next segment.
  @override
  Future<void> flush() => _speech.stop();

  /// Manual stop — suppresses the session's done/error callbacks so the
  /// caller's UI (which initiated the stop) stays authoritative.
  Future<void> stopListening() async {
    _isListening = false;
    _onDone = null;
    _onError = null;
    await _speech.stop();
  }

  void dispose() {
    _speech.stop();
  }
}
