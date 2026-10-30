import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/app_paths.dart';
import '../core/config.dart';
import '../core/startup_timings.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/claude_code_client.dart';
import '../services/exchange_service.dart';
import '../services/exchange_platform.dart';
import '../services/feed_task_grader.dart';
import '../services/local_llm_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _deeplKeyCtrl = TextEditingController();
  final _yandexKeyCtrl = TextEditingController();
  final _anthropicKeyCtrl = TextEditingController();
  final _openaiKeyCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  final _customModelCtrl = TextEditingController();
  final _customKeyCtrl = TextEditingController();
  final _relayUrlCtrl = TextEditingController();
  final _relayCodeCtrl = TextEditingController();

  String _aiProvider = 'claude';
  String _anthropicModel = 'claude-opus-5-5';
  String _fastModel = 'claude-sonnet-5-5';
  String _learningLang = 'es';
  bool _autoCheck = true;

  String _preferredTranslator = 'google';
  bool _googleEnabled = true;
  bool _deeplEnabled = false;
  bool _yandexEnabled = false;
  bool _offlineMode = false;
  String _themeMode = 'dark';
  double _fontSize = 15.0;

  Timer? _keysDebounce;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _deeplKeyCtrl.text = cfg.deeplApiKey;
    _yandexKeyCtrl.text = cfg.yandexApiKey;
    _preferredTranslator = cfg.preferredTranslator;
    _googleEnabled = cfg.googleEnabled;
    _deeplEnabled = cfg.deeplEnabled;
    _yandexEnabled = cfg.yandexEnabled;
    _offlineMode = cfg.offlineMode;
    _themeMode = cfg.themeMode;
    _fontSize = cfg.fontSize;
    _aiProvider = cfg.aiProvider;
    if (_aiProvider == 'claude_code' && !ClaudeCodeClient.platformSupported) {
      _aiProvider = 'claude';
    }
    _anthropicModel = kClaudeModels.containsKey(cfg.anthropicModel)
        ? cfg.anthropicModel
        : 'claude-opus-5-5';
    _fastModel = kClaudeModels.containsKey(cfg.fastModel)
        ? cfg.fastModel
        : 'claude-sonnet-5-5';
    _learningLang = cfg.learningLang == 'en' ? 'en' : 'es';
    _autoCheck = cfg.autoCheckOwnText;
    _anthropicKeyCtrl.text = cfg.anthropicApiKey;
    _openaiKeyCtrl.text = cfg.openaiApiKey;
    _customUrlCtrl.text = cfg.customApiBaseUrl;
    _customModelCtrl.text = cfg.customModel;
    _customKeyCtrl.text = cfg.customApiKey;
    _relayUrlCtrl.text = cfg.relayUrl;
    _relayCodeCtrl.text = cfg.relayClientCode;
    // API keys autosave with a debounce — every setting persists on change,
    // the old explicit "Save" button silently lost whatever you forgot.
    _deeplKeyCtrl.addListener(_scheduleKeySave);
    _yandexKeyCtrl.addListener(_scheduleKeySave);
    _anthropicKeyCtrl.addListener(_scheduleKeySave);
    _openaiKeyCtrl.addListener(_scheduleKeySave);
    _customUrlCtrl.addListener(_scheduleKeySave);
    _customModelCtrl.addListener(_scheduleKeySave);
    _customKeyCtrl.addListener(_scheduleKeySave);
    _relayUrlCtrl.addListener(_scheduleKeySave);
    _relayCodeCtrl.addListener(_scheduleKeySave);
  }

  @override
  void dispose() {
    _keysDebounce?.cancel();
    _deeplKeyCtrl.dispose();
    _yandexKeyCtrl.dispose();
    _anthropicKeyCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _customUrlCtrl.dispose();
    _customModelCtrl.dispose();
    _customKeyCtrl.dispose();
    _relayUrlCtrl.dispose();
    _relayCodeCtrl.dispose();
    super.dispose();
  }

  void _scheduleKeySave() {
    _keysDebounce?.cancel();
    _keysDebounce = Timer(const Duration(milliseconds: 500), () {
      final cfg = ref.read(configProvider);
      cfg.deeplApiKey = _deeplKeyCtrl.text.trim();
      cfg.yandexApiKey = _yandexKeyCtrl.text.trim();
      cfg.anthropicApiKey = _anthropicKeyCtrl.text.trim();
      cfg.openaiApiKey = _openaiKeyCtrl.text.trim();
      cfg.customApiBaseUrl = _customUrlCtrl.text.trim();
      cfg.customModel = _customModelCtrl.text.trim();
      cfg.customApiKey = _customKeyCtrl.text.trim();
      cfg.relayUrl = _relayUrlCtrl.text.trim();
      cfg.relayClientCode = _relayCodeCtrl.text.trim();
      cfg.save();
    });
  }

  /// Apply a change to the config and persist immediately.
  void _persist(void Function(dynamic cfg) apply) {
    final cfg = ref.read(configProvider);
    apply(cfg);
    cfg.save();
  }

  void _setTheme(String mode) {
    setState(() => _themeMode = mode);
    final cfg = ref.read(configProvider);
    cfg.themeMode = mode;
    cfg.save();
  }

  void _setFontSize(double size) {
    setState(() => _fontSize = size);
    final cfg = ref.read(configProvider);
    cfg.fontSize = size;
    cfg.save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // A settings write used to fail silently (that is how an API key
          // could vanish on restart). Now it is impossible to miss.
          if (ref.watch(configProvider).lastSaveError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.error.withOpacity(0.4)),
              ),
              child: Text(
                l.settingsSaveFailed(ref.read(configProvider).lastSaveError!),
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ),
          // ── Appearance ──
          _section(l.sectionAppearance, cs, [
            // Theme selector
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.themeLabel, style: TextStyle(color: cs.onSurface, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _themeChip(l.themeDark, 'dark', const Color(0xFF1e1e2e), cs),
                      const SizedBox(width: 6),
                      _themeChip(l.themeMedium, 'medium', const Color(0xFF24273a), cs),
                      const SizedBox(width: 6),
                      _themeChip(l.themeLight, 'light', const Color(0xFFeff1f5), cs),
                      const SizedBox(width: 6),
                      _themeChip(l.themeExtra, 'extra-light', Colors.white, cs),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Font size
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  Text(l.fontSizeLabel, style: TextStyle(color: cs.onSurface, fontSize: 13)),
                  const Spacer(),
                  Text('${_fontSize.round()}', style: TextStyle(color: cs.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Slider(
              value: _fontSize,
              min: 12,
              max: 22,
              divisions: 10,
              activeColor: cs.primary,
              inactiveColor: cs.outline.withOpacity(0.3),
              onChanged: _setFontSize,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                l.fontPreview,
                style: TextStyle(color: cs.onSurface, fontSize: _fontSize),
              ),
            ),
          ]),

          // ── Offline Translation ──
          _section(l.sectionOfflineTranslation, cs, [
            SwitchListTile(
              dense: true,
              title: Text(l.preferOffline),
              subtitle: Text(
                l.preferOfflineDesc,
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
              value: _offlineMode,
              onChanged: (v) {
                setState(() => _offlineMode = v);
                // Persist immediately — burying this behind "Save" made the
                // toggle look broken.
                final cfg = ref.read(configProvider);
                cfg.offlineMode = v;
                cfg.save();
              },
            ),
            const Divider(height: 1),
            const _MlKitModelsTile(),
            const Divider(height: 1),
            _LocalLlmTile(),
          ]),

          // ── What I'm developing (learner profile) ──
          _section(l.sectionLearning, cs, [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                      child: Text(l.learningLangLabel,
                          style: TextStyle(color: cs.onSurface, fontSize: 13))),
                  DropdownButton<String>(
                    value: _learningLang,
                    dropdownColor: cs.surface,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: 13, color: cs.primary),
                    items: const [
                      DropdownMenuItem(value: 'es', child: Text('Español')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (v) {
                      setState(() => _learningLang = v!);
                      _persist((cfg) => cfg.learningLang = v!);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              title: Text(l.autoCheckLabel(
                  _learningLang == 'en' ? 'English' : 'Español')),
              subtitle: Text(l.autoCheckDesc,
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              value: _autoCheck,
              onChanged: (v) {
                setState(() => _autoCheck = v);
                _persist((cfg) => cfg.autoCheckOwnText = v);
              },
            ),
          ]),

          // ── AI assistant ──
          _section(l.sectionAiAssistant, cs, [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                l.aiKeyDesc,
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                      child: Text(l.providerLabel,
                          style:
                              TextStyle(color: cs.onSurface, fontSize: 13))),
                  Flexible(
                    child: DropdownButton<String>(
                      value: _aiProvider,
                      isExpanded: true,
                      dropdownColor: cs.surface,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(fontSize: 13, color: cs.primary),
                      items: [
                        if (ClaudeCodeClient.platformSupported)
                          DropdownMenuItem(
                              value: 'claude_code',
                              child: Text(l.providerClaudeCode,
                                  overflow: TextOverflow.ellipsis)),
                        if (!AppPaths.isDesktop || _aiProvider == 'pc_relay')
                          DropdownMenuItem(
                              value: 'pc_relay',
                              child: Text(l.providerPcRelay,
                                  overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(
                            value: 'claude',
                            child: Text(l.providerClaudeApi,
                                overflow: TextOverflow.ellipsis)),
                        const DropdownMenuItem(
                            value: 'chatgpt', child: Text('ChatGPT')),
                        DropdownMenuItem(
                            value: 'custom', child: Text(l.providerCustom)),
                        DropdownMenuItem(
                            value: 'auto', child: Text(l.providerAuto)),
                      ],
                      onChanged: (v) {
                        setState(() => _aiProvider = v!);
                        _persist((cfg) => cfg.aiProvider = v!);
                        final cfg = ref.read(configProvider);
                        final missing =
                            (v == 'claude' && cfg.anthropicApiKey.isEmpty) ||
                                (v == 'chatgpt' && cfg.openaiApiKey.isEmpty);
                        if (missing) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(l.providerKeyMissing(
                                v == 'claude' ? 'Claude' : 'ChatGPT')),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_aiProvider == 'claude_code' ||
                _aiProvider == 'claude' ||
                _aiProvider == 'auto')
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(l.claudeModelLabel,
                            style: TextStyle(
                                color: cs.onSurface, fontSize: 13))),
                    DropdownButton<String>(
                      value: _anthropicModel,
                      dropdownColor: cs.surface,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(fontSize: 13, color: cs.primary),
                      items: [
                        for (final e in kClaudeModels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) {
                        setState(() => _anthropicModel = v!);
                        _persist((cfg) => cfg.anthropicModel = v!);
                      },
                    ),
                  ],
                ),
              ),
            if (_aiProvider == 'claude_code' ||
                _aiProvider == 'claude' ||
                _aiProvider == 'auto')
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(l.fastModelLabel,
                            style: TextStyle(
                                color: cs.onSurface, fontSize: 13))),
                    DropdownButton<String>(
                      value: _fastModel,
                      dropdownColor: cs.surface,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(fontSize: 13, color: cs.primary),
                      items: [
                        for (final e in kClaudeModels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) {
                        setState(() => _fastModel = v!);
                        _persist((cfg) => cfg.fastModel = v!);
                      },
                    ),
                  ],
                ),
              ),
            if (_aiProvider == 'claude_code' ||
                _aiProvider == 'claude' ||
                _aiProvider == 'auto')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(l.fastModelHint,
                    style: TextStyle(fontSize: 11, color: cs.outline)),
              ),
            if (AppPaths.isDesktop &&
                (_aiProvider == 'claude_code' || _aiProvider == 'auto'))
              SwitchListTile(
                dense: true,
                title: Text(l.claudeWarmLabel,
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
                subtitle: Text(l.claudeWarmHint,
                    style: TextStyle(fontSize: 11, color: cs.outline)),
                value: ref.watch(configProvider).claudeWarm,
                onChanged: (v) {
                  final cfg = ref.read(configProvider);
                  setState(() => cfg.claudeWarm = v);
                  cfg.save();
                  if (!v) ref.read(claudeCodeProvider).shutdownWarm();
                },
              ),
            if (_aiProvider == 'claude_code' || _aiProvider == 'auto')
              const _ClaudeCodeTile(),
            if (_aiProvider == 'claude' || _aiProvider == 'auto')
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _anthropicKeyCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.anthropicKeyLabel,
                    hintText: 'sk-ant-api03-… · console.anthropic.com → API keys',
                    hintStyle:
                        TextStyle(fontSize: 11, color: cs.outlineVariant),
                    helperText: l.anthropicKeyHelp,
                    helperMaxLines: 4,
                    helperStyle: TextStyle(fontSize: 11, color: cs.outline),
                    isDense: true,
                  ),
                ),
              ),
            if (_aiProvider == 'chatgpt' || _aiProvider == 'auto')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: TextField(
                  controller: _openaiKeyCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.openaiKeyLabel,
                    hintText: 'platform.openai.com → API keys',
                    hintStyle:
                        TextStyle(fontSize: 11, color: cs.outlineVariant),
                    isDense: true,
                  ),
                ),
              ),
            if (_aiProvider == 'custom') ..._customProviderFields(cs, l),
            if (_aiProvider == 'pc_relay' || (_aiProvider == 'auto' && !AppPaths.isDesktop))
              ..._relayClientFields(cs, l),
            // «Идеи»: the background research may search the web.
            SwitchListTile(
              dense: true,
              title: Text(l.ideasWebLabel,
                  style: TextStyle(fontSize: 13, color: cs.onSurface)),
              subtitle: Text(l.ideasWebHint,
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              value: ref.watch(configProvider).ideasWebSearch,
              onChanged: (v) {
                final cfg = ref.read(configProvider);
                setState(() => cfg.ideasWebSearch = v);
                cfg.save();
              },
            ),
            const _ConnectionTestTile(),
            if (AppPaths.isDesktop) ...[
              const Divider(height: 1),
              const _RelayServerTile(),
            ],
            const Divider(height: 1),
            const _OllamaTile(),
          ]),

          // ── Exchange between devices ──
          _section(l.sectionExchange, cs, [const _ExchangeTile()]),

          // ── Data and diagnostics ──
          _section(l.sectionDiagnostics, cs, [const _DiagnosticsTile()]),

          // ── Online Translators ──
          _section(l.sectionOnlineTranslators, cs, [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(l.preferredLabel, style: TextStyle(color: cs.onSurface, fontSize: 13))),
                  DropdownButton<String>(
                    value: _preferredTranslator,
                    dropdownColor: cs.surface,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: 13, color: cs.primary),
                    items: const ['google', 'deepl', 'yandex']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _preferredTranslator = v!);
                      _persist((cfg) => cfg.preferredTranslator = v!);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              title: const Text('Google Translate'),
              subtitle: Text(l.googleFreeDesc, style: TextStyle(fontSize: 11, color: cs.outline)),
              value: _googleEnabled,
              onChanged: (v) {
                setState(() => _googleEnabled = v);
                _persist((cfg) => cfg.googleEnabled = v);
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true, title: const Text('DeepL'),
              value: _deeplEnabled,
              onChanged: (v) {
                setState(() => _deeplEnabled = v);
                _persist((cfg) => cfg.deeplEnabled = v);
              },
            ),
            if (_deeplEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _deeplKeyCtrl, obscureText: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.apiKeyLabel, hintText: 'deepl.com/pro#developer',
                    hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant), isDense: true,
                  ),
                ),
              ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true, title: const Text('Yandex Translate'),
              value: _yandexEnabled,
              onChanged: (v) {
                setState(() => _yandexEnabled = v);
                _persist((cfg) => cfg.yandexEnabled = v);
              },
            ),
            if (_yandexEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextField(
                  controller: _yandexKeyCtrl, obscureText: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l.apiKeyLabel, hintText: 'translate.yandex.com/developers',
                    hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant), isDense: true,
                  ),
                ),
              ),
          ]),

          // ── About ──
          _section(l.sectionAbout, cs, [
            const ListTile(
              dense: true,
              title: Text('LinguaTrace'),
              subtitle: Text('v2.0.0'),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _themeChip(String label, String mode, Color preview, ColorScheme cs) {
    final selected = _themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setTheme(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withOpacity(0.15) : cs.outline.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? cs.primary : cs.outline.withOpacity(0.3),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: preview,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outline),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? cs.primary : cs.onSurface,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fields for an arbitrary OpenAI-compatible endpoint, with one-tap presets
  /// for the services that have a real free tier.
  List<Widget> _relayClientFields(ColorScheme cs, AppLocalizations l) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(l.relayClientDesc,
              style: TextStyle(fontSize: 11, color: cs.outline, height: 1.35)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextField(
            controller: _relayUrlCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: l.relayAddressLabel,
              hintText: '192.168.1.23:8765',
              hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: TextField(
            controller: _relayCodeCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: l.relayCodeLabel,
              hintText: 'abcde-fghjk',
              hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
              isDense: true,
            ),
          ),
        ),
      ];

  List<Widget> _customProviderFields(ColorScheme cs, AppLocalizations l) {
    const presets = <String, List<String>>{
      // label: [baseUrl, model]
      'Gemini (free)': [
        'https://generativelanguage.googleapis.com/v1beta/openai',
        'gemini-2.0-flash',
      ],
      'Groq (free)': ['https://api.groq.com/openai/v1', 'llama-3.3-70b-versatile'],
      'OpenRouter (free)': [
        'https://openrouter.ai/api/v1',
        'meta-llama/llama-3.3-70b-instruct:free',
      ],
      'LM Studio': ['http://localhost:1234/v1', 'local-model'],
    };

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text(l.customApiHint,
            style: TextStyle(fontSize: 11, color: cs.outline)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in presets.entries)
              ActionChip(
                label: Text(entry.key, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _customUrlCtrl.text = entry.value[0];
                  _customModelCtrl.text = entry.value[1];
                  _scheduleKeySave();
                },
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          controller: _customUrlCtrl,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            labelText: l.customBaseUrlLabel,
            hintText: 'https://api.groq.com/openai/v1',
            hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
            isDense: true,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
          controller: _customModelCtrl,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            labelText: l.customModelLabel,
            hintText: 'gemini-2.0-flash',
            hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
            isDense: true,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: TextField(
          controller: _customKeyCtrl,
          obscureText: true,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            labelText: l.customKeyLabel,
            isDense: true,
          ),
        ),
      ),
    ];
  }

  Widget _section(String title, ColorScheme cs, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ollama — the free, local backend for Correct / Context / Training.
// There used to be no UI for it at all, so `ollamaEnabled` could never be
// turned on and the whole free tier was unreachable.
// ─────────────────────────────────────────────────────────────────────────────

class _OllamaTile extends ConsumerStatefulWidget {
  const _OllamaTile();

  @override
  ConsumerState<_OllamaTile> createState() => _OllamaTileState();
}

class _OllamaTileState extends ConsumerState<_OllamaTile> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _modelCtrl;
  Timer? _debounce;
  bool _checking = false;
  String? _status;
  bool _statusOk = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _urlCtrl = TextEditingController(text: cfg.ollamaUrl);
    _modelCtrl = TextEditingController(text: cfg.ollamaModel);
    _urlCtrl.addListener(_scheduleSave);
    _modelCtrl.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final cfg = ref.read(configProvider);
      cfg.ollamaUrl = _urlCtrl.text.trim();
      cfg.ollamaModel = _modelCtrl.text.trim();
      cfg.save();
    });
  }

  /// Ping /api/tags: distinguishes "Ollama isn't running" from "running but
  /// the model was never pulled" — the two failures look identical otherwise.
  Future<void> _check() async {
    final l = AppLocalizations.of(context)!;
    final url = _urlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final model = _modelCtrl.text.trim();
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$url/api/tags'))
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final names = ((data['models'] as List?) ?? const [])
          .map((m) => (m as Map)['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      if (names.isEmpty) {
        _setStatus(l.ollamaNoModels(model.isEmpty ? 'qwen2.5:3b' : model),
            ok: false);
      } else if (model.isNotEmpty &&
          !names.any((n) => n == model || n.startsWith('$model:'))) {
        _setStatus(l.ollamaModelMissing(model), ok: false);
      } else {
        _setStatus(l.ollamaOk(names.join(', ')), ok: true);
      }
    } catch (_) {
      _setStatus(l.ollamaUnreachable(url), ok: false);
    }
  }

  void _setStatus(String text, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = text;
      _statusOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final cfg = ref.watch(configProvider);

    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: Text(l.ollamaTitle),
          subtitle: Text(l.ollamaDesc,
              style: TextStyle(fontSize: 11, color: cs.outline)),
          value: cfg.ollamaEnabled,
          onChanged: (v) async {
            cfg.ollamaEnabled = v;
            await cfg.save();
            if (!mounted) return;
            setState(() {});
            if (v) _check();
          },
        ),
        if (cfg.ollamaEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _urlCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: l.ollamaUrlLabel,
                hintText: 'http://localhost:11434',
                hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _modelCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: l.ollamaModelLabel,
                hintText: 'qwen2.5:3b',
                hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                  label: Text(_checking ? l.ollamaChecking : l.ollamaCheck),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _status!,
                style: TextStyle(
                  fontSize: 11,
                  color: _statusOk ? cs.primary : cs.error,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ML Kit offline model manager — per-language download / delete / status.
// Without pre-downloaded models the offline tier of the translation pipeline
// never fires and everything silently goes through online Google.
// ─────────────────────────────────────────────────────────────────────────────

class _MlKitModelsTile extends ConsumerStatefulWidget {
  const _MlKitModelsTile();

  @override
  ConsumerState<_MlKitModelsTile> createState() => _MlKitModelsTileState();
}

class _MlKitModelsTileState extends ConsumerState<_MlKitModelsTile> {
  final _mgr = OnDeviceTranslatorModelManager();

  // Core languages of the app. bcpCode == ISO-639-1 for all three.
  static const _langs = [
    ('en', 'English'),
    ('ru', 'Русский'),
    ('es', 'Español'),
  ];

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final Map<String, bool> _downloaded = {};
  String? _busy; // language code currently downloading/deleting
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_supported) _refresh();
  }

  Future<void> _refresh() async {
    for (final (code, _) in _langs) {
      try {
        final ok = await _mgr.isModelDownloaded(code);
        if (mounted) setState(() => _downloaded[code] = ok);
      } catch (_) {/* plugin missing — row stays unknown */}
    }
  }

  Future<void> _download(String code) async {
    setState(() { _busy = code; _error = null; });
    try {
      await _mgr.downloadModel(code, isWifiRequired: false);
      if (mounted) setState(() => _downloaded[code] = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context)!
            .downloadFailedWithError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _delete(String code) async {
    setState(() { _busy = code; _error = null; });
    try {
      await _mgr.deleteModel(code);
      if (mounted) setState(() => _downloaded[code] = false);
    } catch (e) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context)!
            .deleteFailedWithError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    if (!_supported) {
      return ListTile(
        dense: true,
        title: Text(l.mlkitModelsTitle),
        subtitle: Text(
          l.mlkitOnlyMobile,
          style: TextStyle(fontSize: 11, color: cs.outline),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(l.mlkitModelsSize,
              style: TextStyle(color: cs.onSurface, fontSize: 13)),
        ),
        for (final (code, label) in _langs)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text(label, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              _downloaded[code] == true
                  ? l.modelDownloadedOffline
                  : l.modelNotDownloaded,
              style: TextStyle(
                fontSize: 11,
                color: _downloaded[code] == true ? cs.secondary : cs.outline,
              ),
            ),
            trailing: _busy == code
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _downloaded[code] == true
                    ? IconButton(
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 20, color: cs.error),
                        tooltip: l.deleteModel,
                        onPressed: _busy != null ? null : () => _delete(code),
                      )
                    : IconButton(
                        icon: Icon(Icons.download_rounded,
                            size: 20, color: cs.primary),
                        tooltip: l.downloadModel,
                        onPressed: _busy != null ? null : () => _download(code),
                      ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(_error!,
                style: TextStyle(color: cs.error, fontSize: 11)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// On-device LLM (flutter_gemma) tile — download / delete / progress
// ─────────────────────────────────────────────────────────────────────────────

class _LocalLlmTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LocalLlmTile> createState() => _LocalLlmTileState();
}

class _LocalLlmTileState extends ConsumerState<_LocalLlmTile> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _tokenCtrl;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(configProvider);
    _urlCtrl = TextEditingController(text: cfg.localLlmModelUrl);
    _tokenCtrl = TextEditingController(text: cfg.huggingFaceToken);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final cfg = ref.watch(configProvider);
    final llm = ref.watch(localLlmProvider);
    final state = llm.state;

    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: Text(l.onDeviceLlmTitle),
          subtitle: Text(
            state.installed
                ? l.llmInstalledReady(cfg.localLlmModelName)
                : l.llmDownloadDesc,
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
          value: cfg.localLlmEnabled,
          onChanged: (v) async {
            cfg.localLlmEnabled = v;
            await cfg.save();
            if (!mounted) return;
            setState(() {});
          },
        ),
        // Progress / actions
        if (state.downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null,
                  color: cs.primary,
                  backgroundColor: cs.outline.withOpacity(0.15),
                ),
                const SizedBox(height: 6),
                Text(
                  l.downloadingPercent(
                      (state.progress * 100).toStringAsFixed(1)),
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                if (!state.installed)
                  FilledButton.icon(
                    onPressed: () => _install(llm),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(l.downloadModel),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _delete(llm),
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: cs.error),
                    label: Text(l.deleteModel,
                        style: TextStyle(color: cs.error)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: cs.error.withOpacity(0.4)),
                    ),
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                  icon: Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(l.modelTokenButton),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        if (state.error != null && state.error!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              state.error!.contains('401') ||
                      state.error!.toLowerCase().contains('authentication')
                  ? l.modelGatedHint
                  : state.error!,
              style: TextStyle(color: cs.error, fontSize: 11),
            ),
          ),
        if (_showAdvanced)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: l.modelUrlLabel,
                    hintText: 'https://huggingface.co/.../model.task',
                    hintStyle:
                        TextStyle(fontSize: 11, color: cs.outlineVariant),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: l.hfTokenLabel,
                    hintText: 'hf_…',
                    hintStyle:
                        TextStyle(fontSize: 11, color: cs.outlineVariant),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      cfg.localLlmModelUrl = _urlCtrl.text.trim();
                      cfg.huggingFaceToken = _tokenCtrl.text.trim();
                      await cfg.save();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(AppLocalizations.of(context)!
                                  .modelSettingsSaved)),
                        );
                      }
                    },
                    child: Text(l.saveUrlToken),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _install(LocalLlmService llm) async {
    // Persist URL/token first if user typed them
    final cfg = ref.read(configProvider);
    cfg.localLlmModelUrl = _urlCtrl.text.trim().isEmpty
        ? cfg.localLlmModelUrl
        : _urlCtrl.text.trim();
    cfg.huggingFaceToken = _tokenCtrl.text.trim();
    await cfg.save();

    final ok = await llm.installModel();
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    // A bare "download failed" is useless — show the real reason, and for
    // 401 (license-gated model on Hugging Face) explain what to do.
    String message;
    if (ok) {
      message = l.modelInstalled;
    } else {
      final err = llm.state.error ?? '';
      final gated = err.contains('401') ||
          err.toLowerCase().contains('authentication');
      message = gated
          ? l.modelGatedHint
          : (err.isEmpty
              ? l.modelDownloadFailed
              : l.downloadFailedWithError(
                  err.length > 200 ? '${err.substring(0, 200)}…' : err));
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: ok ? 3 : 8),
    ));
  }

  Future<void> _delete(LocalLlmService llm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.deleteOnDeviceModelQuestion),
        content: Text(AppLocalizations.of(ctx)!.deleteOnDeviceModelDesc),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.delete),
          ),
        ],
      ),
    );
    if (ok == true) await llm.deleteModel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// «Claude для телефона»: this PC answers the phone's AI requests.
// ─────────────────────────────────────────────────────────────────────────────

class _RelayServerTile extends ConsumerWidget {
  const _RelayServerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final cfg = ref.watch(configProvider);
    final host = ref.watch(relayHostProvider);
    final small = TextStyle(fontSize: 11, color: cs.outline, height: 1.35);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l.relayServerTitle,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
            subtitle: Text(l.relayServerDesc, style: small),
            value: cfg.relayServerEnabled,
            onChanged: (v) async {
              cfg.relayServerEnabled = v;
              await cfg.save();
              await host.apply();
            },
          ),
          if (cfg.relayServerEnabled) ...[
            if (host.error != null)
              SelectableText(host.error!,
                  style: TextStyle(fontSize: 12, color: cs.error))
            else if (host.running) ...[
              Text(l.relayServerRunning,
                  style: TextStyle(fontSize: 12, color: cs.primary)),
              const SizedBox(height: 4),
              SelectableText(
                  host.addresses.isEmpty
                      ? l.relayNoNetwork
                      : host.addresses
                          .map((a) => '$a:${host.port}')
                          .join('   ·   '),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text('${l.relayCodeLabel}: ', style: small),
                SelectableText(cfg.relayCode,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: cs.onSurface)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => host.newCode(),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: Text(l.relayNewCode,
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l.relayServerHint, style: small),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Claude Code (subscription route): installed? logged in? which plan?
// ─────────────────────────────────────────────────────────────────────────────

class _ClaudeCodeTile extends ConsumerStatefulWidget {
  const _ClaudeCodeTile();

  @override
  ConsumerState<_ClaudeCodeTile> createState() => _ClaudeCodeTileState();
}

class _ClaudeCodeTileState extends ConsumerState<_ClaudeCodeTile>
    with WidgetsBindingObserver {
  ClaudeCodeStatus? _status;
  bool _loading = false;
  late final TextEditingController _tokenCtrl;
  Timer? _tokenDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tokenCtrl =
        TextEditingController(text: ref.read(configProvider).claudeCodeToken);
    if (ClaudeCodeClient.platformSupported) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenDebounce?.cancel();
    _tokenCtrl.dispose();
    super.dispose();
  }

  /// Back from the sign-in console window: check again by itself (only
  /// while not signed in — each check starts the CLI twice).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !(_status?.ready ?? false)) {
      _refresh(force: true);
    }
  }

  Future<void> _refresh({bool force = false}) async {
    setState(() => _loading = true);
    final s = await ref.read(claudeCodeProvider).status(refresh: force);
    if (mounted) {
      setState(() {
        _status = s;
        _loading = false;
      });
    }
  }

  void _onToken(String v) {
    _tokenDebounce?.cancel();
    _tokenDebounce = Timer(const Duration(milliseconds: 600), () {
      final cfg = ref.read(configProvider);
      cfg.claudeCodeToken = v.trim();
      cfg.save();
      _refresh(force: true);
    });
  }

  Future<void> _console(List<String> args, List<String> intro) async {
    final path = _status?.path;
    if (path == null) return;
    try {
      await ClaudeCodeClient.openConsole(path, args,
          dir: p.join(AppPaths.dataDir, 'claude-cwd'), intro: intro);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    if (!ClaudeCodeClient.platformSupported) return const SizedBox.shrink();
    final s = _status;
    final ok = s?.ready ?? false;
    final small = TextStyle(fontSize: 11, color: cs.outline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (ok ? cs.primary : cs.error).withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    size: 16, color: ok ? cs.primary : cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l.claudeCodeTitle,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ),
                TextButton(
                  onPressed: _loading ? null : () => _refresh(force: true),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: Text(l.refresh, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_loading && s == null)
              Text(l.claudeCodeChecking, style: small)
            else ...[
              if (ok)
                Text(
                  s!.loggedIn
                      ? l.claudeCodeReady(s.version ?? '?', s.subscription ?? '—')
                      : l.claudeCodeTokenInUse(s.version ?? '?'),
                  style: TextStyle(fontSize: 11, color: cs.onSurface),
                )
              else
                SelectableText(
                  s?.error ?? ClaudeCodeClient.kNotLoggedInHint,
                  style: TextStyle(fontSize: 11, color: cs.onSurface),
                ),
              if (s?.installed == true) ...[
                const SizedBox(height: 2),
                SelectableText(
                    [
                      if (s!.email != null) s.email!,
                      s.path!,
                    ].join(' · '),
                    style: small),
              ],
              if (s?.installed == true && Platform.isWindows) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (!ok)
                      FilledButton.tonalIcon(
                        onPressed: () => _console(['auth', 'login'], [
                          l.claudeCodeConsoleLogin1,
                          l.claudeCodeConsoleLogin2,
                        ]),
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: Text(l.claudeCodeLogin,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _console(['setup-token'], [
                        l.claudeCodeConsoleToken1,
                        l.claudeCodeConsoleToken2,
                      ]),
                      icon: const Icon(Icons.key_rounded, size: 16),
                      label: Text(l.claudeCodeSetupToken,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
              if (s?.installed == true) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  onChanged: _onToken,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l.claudeCodeTokenLabel,
                    helperText: l.claudeCodeTokenHelp,
                    helperMaxLines: 3,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// «Проверить подключение»: one tiny request through the real chain, showing
// which backend answered — or the exact reason it didn't.
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionTestTile extends ConsumerStatefulWidget {
  const _ConnectionTestTile();

  @override
  ConsumerState<_ConnectionTestTile> createState() =>
      _ConnectionTestTileState();
}

class _ConnectionTestTileState extends ConsumerState<_ConnectionTestTile> {
  bool _running = false;
  String? _message;
  bool _ok = false;
  (int, int, double)? _usage;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final u = await ref.read(databaseProvider).aiUsageThisMonth();
      if (mounted) setState(() => _usage = u);
    } catch (_) {}
  }

  Future<void> _test() async {
    final l = AppLocalizations.of(context)!;
    setState(() {
      _running = true;
      _message = null;
    });
    final sw = Stopwatch()..start();
    try {
      final r = await ref.read(llmRouterProvider).completeResult(
            system: 'Answer with exactly one word: ok',
            user: 'ping',
            maxTokens: 2000,
            effort: 'low',
            timeout: const Duration(minutes: 2),
            allowOnDevice: false,
            feature: 'connection_test',
            // The chosen provider only: no minutes-long wait on a fallback.
            fallback: false,
            tier: 'fast',
          );
      final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
      _set(l.connectionOk(r.backend, secs), ok: true);
    } catch (e) {
      _set(e.toString(), ok: false);
    }
    _loadUsage();
  }

  void _set(String m, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _message = m;
      _ok = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final u = _usage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _running ? null : _test,
            icon: _running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt_rounded, size: 18),
            label: Text(_running ? l.checkingConnection : l.checkConnection),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(_message!,
                  style: TextStyle(
                      fontSize: 11, color: _ok ? cs.primary : cs.error)),
            ),
          if (u != null && u.$1 > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.aiUsageMonth(u.$1, u.$2, u.$3.toStringAsFixed(2)),
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Where the user's data lives — one visible folder, easy to back up.
// ─────────────────────────────────────────────────────────────────────────────

class _DiagnosticsTile extends ConsumerWidget {
  const _DiagnosticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final cfg = ref.watch(configProvider);
    String dir;
    try {
      dir = AppPaths.dataDir;
    } catch (_) {
      dir = '—';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.dataFolderLabel,
              style: TextStyle(fontSize: 12, color: cs.onSurface)),
          SelectableText(dir,
              style: TextStyle(fontSize: 11, color: cs.outline)),
          const SizedBox(height: 6),
          if (StartupTimings.phases.isNotEmpty) ...[
            Text(l.startupTimesLabel,
                style: TextStyle(fontSize: 11, color: cs.outline)),
            SelectableText(StartupTimings.summary(),
                style: TextStyle(fontSize: 12, color: cs.onSurface)),
            const SizedBox(height: 8),
          ],
          Text(l.settingsFileLabel,
              style: TextStyle(fontSize: 12, color: cs.onSurface)),
          SelectableText(cfg.storeLocation,
              style: TextStyle(fontSize: 11, color: cs.outline)),
          if (!kIsWeb && Platform.isWindows && dir != '—') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Process.run('explorer.exe', [dir]),
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: Text(l.openFolder),
              style:
                  OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exchange between devices: one file per device, merged on the other one.
// Desktop: a folder (point it at OneDrive to make it the single shared
// place). Phone: send the file through the share sheet / load a file.
// ─────────────────────────────────────────────────────────────────────────────

class _ExchangeTile extends ConsumerStatefulWidget {
  const _ExchangeTile();

  @override
  ConsumerState<_ExchangeTile> createState() => _ExchangeTileState();
}

class _ExchangeTileState extends ConsumerState<_ExchangeTile> {
  late final TextEditingController _dirCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  Timer? _debounce;
  Timer? _serverDebounce;
  bool _busy = false;
  String? _message;
  bool _ok = true;

  // Taken once: an import can outlive this tile (scrolled away in the
  // settings list), and `ref` is unusable after dispose.
  late final ExchangeService _exchange = ref.read(exchangeProvider);
  late final FeedTaskGrader _grader = ref.read(feedTaskGraderProvider);
  late final StateController<int> _history =
      ref.read(historyVersionProvider.notifier);

  bool get _desktop => !kIsWeb && AppPaths.isDesktop;

  @override
  void initState() {
    super.initState();
    _exchange;
    _grader;
    _history;
    _dirCtrl = TextEditingController(
        text: AppPaths.exchangeDirFor(ref.read(configProvider).exchangeDir));
    _dirCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        final cfg = ref.read(configProvider);
        final v = _dirCtrl.text.trim();
        cfg.exchangeDir = v == AppPaths.defaultExchangeDir ? '' : v;
        cfg.save();
      });
    });
    final cfg = ref.read(configProvider);
    _urlCtrl = TextEditingController(text: cfg.syncServerUrl);
    _keyCtrl = TextEditingController(text: cfg.syncServerKey);
    for (final c in [_urlCtrl, _keyCtrl]) {
      c.addListener(() {
        _serverDebounce?.cancel();
        _serverDebounce = Timer(const Duration(milliseconds: 600), _saveServer);
      });
    }
  }

  void _saveServer() {
    final cfg = ref.read(configProvider);
    if (cfg.syncServerUrl == _urlCtrl.text.trim() &&
        cfg.syncServerKey == _keyCtrl.text.trim()) {
      return;
    }
    cfg.syncServerUrl = _urlCtrl.text.trim();
    cfg.syncServerKey = _keyCtrl.text.trim();
    cfg.save();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_serverDebounce?.isActive ?? false) _saveServer();
    _serverDebounce?.cancel();
    _dirCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<String> _syncServerNow() async {
    final l = AppLocalizations.of(context)!;
    _saveServer();
    final r = await _exchange.syncServer(_urlCtrl.text, _keyCtrl.text);
    ExchangeService.lastServerError = null;
    final graded = await _grader.gradePending();
    return [
      _describe(r, l),
      if (r.uploaded) l.syncServerSent,
      if (graded > 0) l.exchangeGraded(graded),
    ].join('\n');
  }

  String _describe(ExchangeReport r, AppLocalizations l) {
    if (r.total == 0 && r.errors.isEmpty) return l.exchangeNothingNew;
    final b = StringBuffer(l.exchangeReport(
        r.items, r.mistakes, r.feedItems, r.tasksUpdated, r.translations));
    if (r.errors.isNotEmpty) b.write('\n${r.errors.join('\n')}');
    return b.toString();
  }

  Future<void> _run(Future<String> Function() job) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await job();
      if (mounted) setState(() {
        _message = msg;
        _ok = true;
      });
    } catch (e) {
      if (mounted) setState(() {
        _message = e.toString();
        _ok = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _history.state++;
    }
  }

  Future<String> _syncDesktop() async {
    final l = AppLocalizations.of(context)!;
    final dir = AppPaths.exchangeDirFor(_dirCtrl.text);
    final r = await _exchange.syncFolder(dir);
    final graded = await _grader.gradePending();
    if (graded > 0) {
      // Push the grades back out for the other device.
      await _exchange.exportTo(dir);
    }
    final text = _describe(r, l);
    return graded > 0 ? '$text\n${l.exchangeGraded(graded)}' : text;
  }

  Future<String> _share() async {
    final path = await _exchange.exportTo(AppPaths.defaultExchangeDir);
    await shareExchangeFile(path);
    return path;
  }

  Future<String> _load() async {
    final l = AppLocalizations.of(context)!;
    final path = await pickExchangeFile();
    if (path == null) return '';
    try {
      final size = await File(path).length();
      if (size > ExchangeService.maxFileBytes) {
        return Future.error(l.exchangeTooLarge(size ~/ (1024 * 1024)));
      }
      final r = await _exchange.importFile(path);
      await _grader.gradePending();
      return _describe(r, l);
    } finally {
      // The picker copied the file into the app cache: do not keep it.
      await clearPickedFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final oneDrive = !kIsWeb && Platform.isWindows
        ? Platform.environment['OneDrive'] ?? ''
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.exchangeDesc,
              style: TextStyle(fontSize: 11, color: cs.outline, height: 1.35)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(l.exchangeFullHistory,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(l.exchangeFullHistoryHint,
                style: TextStyle(fontSize: 11, color: cs.outline, height: 1.3)),
            value: ref.watch(configProvider).exchangeFullHistory,
            onChanged: (v) {
              final cfg = ref.read(configProvider);
              setState(() => cfg.exchangeFullHistory = v);
              cfg.save();
            },
          ),
          const SizedBox(height: 6),
          // ── Sync server: every device's data in one place, automatically.
          Text(l.syncServerTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(l.syncServerHint,
              style: TextStyle(fontSize: 11, color: cs.outline, height: 1.35)),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: l.syncServerUrlLabel,
              hintText: 'https://lt.example.com',
              hintStyle: TextStyle(fontSize: 11, color: cs.outlineVariant),
              isDense: true,
            ),
          ),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: l.syncServerKeyLabel,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _run(_syncServerNow),
            icon: const Icon(Icons.cloud_sync_rounded, size: 18),
            label: Text(_busy ? l.exchangeSyncing : l.syncServerNow),
          ),
          if (ExchangeService.lastServerError != null && _message == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(ExchangeService.lastServerError!,
                  style: TextStyle(fontSize: 11, color: cs.error)),
            ),
          const Divider(height: 24),
          if (_desktop) ...[
            TextField(
              controller: _dirCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: l.exchangeFolderLabel,
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _run(_syncDesktop),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: Text(_busy ? l.exchangeSyncing : l.exchangeSyncNow),
                ),
                if (oneDrive.isNotEmpty)
                  OutlinedButton(
                    onPressed: () => _dirCtrl.text =
                        '$oneDrive${Platform.pathSeparator}LinguaTrace',
                    child: Text(l.exchangeUseOneDrive),
                  ),
                if (Platform.isWindows)
                  OutlinedButton.icon(
                    onPressed: () {
                      final dir = AppPaths.exchangeDirFor(_dirCtrl.text);
                      Directory(dir).createSync(recursive: true);
                      Process.run('explorer.exe', [dir]);
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: Text(l.openFolder),
                  ),
              ],
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _run(_load),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(l.exchangeLoad),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_share),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(l.exchangeShare),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l.exchangePhoneHint,
                style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
          if (_message != null && _message!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(_message!,
                  style: TextStyle(
                      fontSize: 11.5, color: _ok ? cs.primary : cs.error)),
            ),
        ],
      ),
    );
  }
}
