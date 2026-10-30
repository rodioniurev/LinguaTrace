/// On-device LLM translation via flutter_gemma + LiteRT-LM.
///
/// This service is purposely defensive: every plugin call is wrapped so that
/// a missing native runtime, an absent model, or a download failure cannot
/// crash the app — the translator pipeline falls back to ML Kit / online.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../core/config.dart';
import '../core/languages.dart';

/// Reactive state of the local LLM lifecycle.
class LocalLlmState {
  final bool installed;
  final bool downloading;
  final double progress;     // 0.0 – 1.0
  final String? error;
  final bool initialized;    // model is loaded into memory

  const LocalLlmState({
    this.installed = false,
    this.downloading = false,
    this.progress = 0.0,
    this.error,
    this.initialized = false,
  });

  LocalLlmState copyWith({
    bool? installed,
    bool? downloading,
    double? progress,
    Object? error = _sentinel,
    bool? initialized,
  }) => LocalLlmState(
        installed: installed ?? this.installed,
        downloading: downloading ?? this.downloading,
        progress: progress ?? this.progress,
        error: identical(error, _sentinel) ? this.error : error as String?,
        initialized: initialized ?? this.initialized,
      );

  static const _sentinel = Object();
}

class LocalLlmService extends ChangeNotifier {
  final ConfigService _config;

  LocalLlmService(this._config) {
    _state = LocalLlmState(installed: _config.localLlmInstalled);
  }

  LocalLlmState _state = const LocalLlmState();
  LocalLlmState get state => _state;

  /// Lazy-loaded model instance — reused across translation calls.
  InferenceModel? _model;
  InferenceModelSession? _session;

  /// True iff the user has opted in AND a model is installed.
  bool get isUsable => _config.localLlmEnabled && _state.installed;

  /// Download + install the model from [overrideUrl] (or config's URL).
  /// Returns true on success. Progress is reported through [state].
  Future<bool> installModel({
    String? overrideUrl,
    String? modelTypeOverride,
  }) async {
    final url = (overrideUrl ?? _config.localLlmModelUrl).trim();
    if (url.isEmpty) {
      _update(error: 'Model URL is empty');
      return false;
    }

    _update(downloading: true, progress: 0, error: null);
    try {
      // Pick model family — wrong family means wrong chat template, so when
      // there is no explicit override, infer it from the URL.
      final modelType = _resolveModelType(modelTypeOverride, url);
      // Choose container format from the file extension.
      final lower = url.toLowerCase();
      final fileType = lower.endsWith('.litertlm')
          ? ModelFileType.litertlm
          : (lower.endsWith('.bin') || lower.endsWith('.tflite'))
              ? ModelFileType.binary
              : ModelFileType.task;

      await FlutterGemma.installModel(modelType: modelType, fileType: fileType)
          .fromNetwork(
            url,
            token: _config.huggingFaceToken.isNotEmpty
                ? _config.huggingFaceToken
                : null,
          )
          .withProgress((int pct) {
            _update(progress: pct.clamp(0, 100) / 100.0);
          })
          .install();

      _config.localLlmInstalled = true;
      await _config.save();
      _update(downloading: false, installed: true, progress: 1.0);
      return true;
    } catch (e) {
      _update(downloading: false, error: e.toString());
      return false;
    }
  }

  /// Delete the installed model + free RAM.
  Future<void> deleteModel() async {
    await _closeModel();
    try {
      // Modern API: uninstall each known model by ID
      final ids = await FlutterGemma.listInstalledModels();
      for (final id in ids) {
        try {
          await FlutterGemma.uninstallModel(id);
        } catch (_) {/* best-effort */}
      }
    } catch (_) {/* manager may not be initialized */}

    _config.localLlmInstalled = false;
    await _config.save();
    _update(installed: false, initialized: false, progress: 0);
  }

  Future<void> _ensureModelLoaded() async {
    if (_model != null && _session != null) return;

    if (!FlutterGemma.hasActiveModel()) {
      throw StateError('No active local model — install one first');
    }

    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.gpu,
      );
      _session = await _model!.createSession(
        temperature: 0.1,
        topK: 1,
      );
      _update(initialized: true);
    } catch (e) {
      _update(error: 'Model load failed: $e', initialized: false);
      rethrow;
    }
  }

  Future<void> _closeModel() async {
    try { await _session?.close(); } catch (_) {}
    try { await _model?.close(); } catch (_) {}
    _session = null;
    _model = null;
  }

  /// Run an arbitrary prompt through the on-device model. Throws when the
  /// model is unusable so callers can fall through to the next backend.
  Future<String> generate(String prompt) async {
    if (!isUsable) {
      throw StateError('Local LLM not installed or disabled');
    }
    await _ensureModelLoaded();

    try {
      await _session!.addQueryChunk(Message.text(text: prompt, isUser: true));
      final response = await _session!.getResponse();
      // Reset session so context doesn't accumulate across calls
      await _resetSession();
      return response.trim();
    } catch (e) {
      // Corrupted state — force full reload next time
      await _closeModel();
      rethrow;
    }
  }

  /// Translate via the on-device LLM. Throws on failure so the caller can
  /// fall back to the next tier (ML Kit / online).
  Future<String> translate(String text, String src, String tgt) async {
    final tgtName = langName(tgt);
    final srcHint = (src != 'auto' && src.isNotEmpty)
        ? ' from ${langName(src)}'
        : '';
    var out = await generate(
      'Translate the following text$srcHint to $tgtName. '
      'Output ONLY the translation — no quotes, no explanations.\n\n$text',
    );

    // Strip wrapping quotes — small models add them despite instructions
    if (out.length >= 2 &&
        ((out.startsWith('"') && out.endsWith('"')) ||
            (out.startsWith('«') && out.endsWith('»')))) {
      out = out.substring(1, out.length - 1).trim();
    }
    return out;
  }

  Future<void> _resetSession() async {
    try {
      await _session?.close();
      _session = await _model!.createSession(temperature: 0.1, topK: 1);
    } catch (_) {
      // Session re-creation failed — tear everything down so the next call
      // re-initializes from scratch instead of running with a stale model
      // and a state that lies about being initialized.
      await _closeModel();
      _update(initialized: false);
    }
  }

  @override
  void dispose() {
    _closeModel();
    super.dispose();
  }

  // ── internal helpers ──

  ModelType _resolveModelType(String? override, String url) {
    switch ((override ?? '').toLowerCase()) {
      case 'qwen':     return ModelType.qwen;
      case 'qwen3':    return ModelType.qwen3;
      case 'deepseek': return ModelType.deepSeek;
      case 'phi':      return ModelType.phi;
      case 'llama':    return ModelType.llama;
      case 'gemma4':   return ModelType.gemma4;
      case 'gemmait':
      case 'gemma':
        return ModelType.gemmaIt;
    }
    final u = url.toLowerCase();
    if (u.contains('qwen3')) return ModelType.qwen3;
    if (u.contains('qwen')) return ModelType.qwen;
    if (u.contains('deepseek')) return ModelType.deepSeek;
    if (u.contains('phi')) return ModelType.phi;
    if (u.contains('llama')) return ModelType.llama;
    return ModelType.gemmaIt;
  }

  void _update({
    bool? installed,
    bool? downloading,
    double? progress,
    Object? error = LocalLlmState._sentinel,
    bool? initialized,
  }) {
    _state = _state.copyWith(
      installed: installed,
      downloading: downloading,
      progress: progress,
      error: error,
      initialized: initialized,
    );
    notifyListeners();
  }
}
