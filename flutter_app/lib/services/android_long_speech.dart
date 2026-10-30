/// Android dictation through the native recogniser loop (LongSpeech.kt):
/// the app records the microphone and streams it into the recogniser as one
/// long session (no restart and no beep at every pause), trouble retried
/// natively, a foreground service so it keeps hearing with the screen off;
/// Claude's answers read aloud while the recogniser hears silence.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'long_dictation.dart';
import 'voice_service.dart';

class AndroidLongSpeech implements SpeechEngine {
  AndroidLongSpeech(this._voice, {this.muteBeeps = true});

  static const _channel = MethodChannel('io.linguatrace/long_speech');

  final VoiceService _voice;

  /// Mute the media stream while dictating (the recogniser beeps on start).
  bool muteBeeps;

  /// Listen through the Bluetooth headset's microphone (Android 12+).
  bool bluetooth = false;

  final _spoken = <String, Completer<bool>>{};
  int _utterance = 0;

  void Function(String words, bool isFinal)? _onResult;
  void Function(String code, bool permanent)? _onError;
  void Function(String? trouble)? _onTrouble;
  void Function(String line)? _onLog;

  static String localeTag(String lang) => switch (lang) {
        'es' => 'es-ES',
        'en' => 'en-US',
        _ => 'ru-RU',
      };

  @override
  Future<bool> startSegment({
    required String lang,
    required void Function(String words, bool isFinal) onResult,
    required void Function() onEnd,
    required void Function(String code, bool permanent) onError,
    void Function(String? trouble)? onTrouble,
    void Function(String line)? onLog,
  }) async {
    // The microphone permission dialog comes from the speech plugin; it
    // fails without the permission or without a recogniser on the phone.
    if (!await _voice.init()) {
      onError('error_init', true);
      return false;
    }
    _onResult = onResult;
    _onError = onError;
    _onTrouble = onTrouble;
    _onLog = onLog;
    _channel.setMethodCallHandler(_event);
    try {
      final err = await _channel.invokeMethod<String>(
          'start', {
        'lang': localeTag(lang),
        'mute': muteBeeps,
        'bluetooth': bluetooth,
      });
      if (err == null) return true;
      onError(err, true);
      return false;
    } on PlatformException catch (e) {
      onLog?.call('start: ${e.code} ${e.message ?? ''}');
      return false;
    } on MissingPluginException {
      onLog?.call('start: no native dictation in this build');
      return false;
    }
  }

  Future<void> _event(MethodCall call) async {
    if (call.method != 'event') return;
    final m = Map<String, Object?>.from(call.arguments as Map);
    switch (m['type']) {
      case 'partial':
        _onResult?.call(m['text'] as String? ?? '', false);
      case 'final':
        _onResult?.call(m['text'] as String? ?? '', true);
      case 'state':
        _onTrouble?.call(m['state'] == 'listening'
            ? null
            : (m['detail'] as String?) ?? 'waiting');
      case 'fatal':
        _onError?.call(m['code'] as String? ?? 'error', true);
      case 'log':
        _onLog?.call(m['text'] as String? ?? '');
      case 'spoken':
        _spoken.remove(m['id'])?.complete(m['ok'] == true);
    }
  }

  /// Read [text] aloud; dictation hears silence meanwhile and goes on after.
  /// True when it was spoken to the end.
  Future<bool> speak(String text, String lang) async {
    final id = 'u${++_utterance}';
    final done = _spoken[id] = Completer<bool>();
    _channel.setMethodCallHandler(_event);
    try {
      await _channel.invokeMethod<void>(
          'speak', {'text': text, 'lang': localeTag(lang), 'id': id});
    } catch (_) {
      _spoken.remove(id);
      return false;
    }
    // Never wait for ever: about 15 characters a second, plus a margin.
    final limit = Duration(milliseconds: 8000 + text.length * 90);
    return done.future.timeout(limit, onTimeout: () {
      _spoken.remove(id);
      return false;
    });
  }

  Future<void> stopSpeaking() async {
    try {
      await _channel.invokeMethod<void>('stopSpeaking');
    } catch (_) {}
  }

  @override
  Future<void> stopSegment() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  @override
  Future<void> flush() async {
    try {
      await _channel.invokeMethod<void>('flush');
    } catch (_) {}
  }
}
