/// Shared result/error types for every LLM backend.
library;

import 'dart:convert';
import 'dart:typed_data';

class AiResult {
  final String text;

  /// Parsed structured output when a JSON schema was requested and the
  /// backend returned valid JSON; null otherwise.
  final Map<String, dynamic>? json;

  /// Human-readable backend that ACTUALLY answered ("Claude Opus 5 ·
  /// подписка", "Ollama/qwen2.5:3b", …) — shown in the UI.
  final String backend;

  /// Machine key: claude_code | claude | chatgpt | custom | ollama | local.
  final String provider;
  final String model;
  final String stopReason;
  final int inputTokens;
  final int outputTokens;

  /// Estimated pay-per-token cost; 0 for subscription and local backends.
  final double costUsd;
  final int durationMs;

  /// Answered by a model on this machine or the LAN (Ollama, LM Studio,
  /// on-device) — usually small; its corrections are not trusted blindly.
  final bool localEndpoint;

  /// Web pages the answer relied on (web search), and whether the web was
  /// searched at all.
  final List<WebSource> sources;
  final bool searchedWeb;

  const AiResult({
    required this.text,
    required this.backend,
    required this.provider,
    this.json,
    this.model = '',
    this.stopReason = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.costUsd = 0,
    this.durationMs = 0,
    this.localEndpoint = false,
    this.sources = const [],
    this.searchedWeb = false,
  });

  AiResult withJson(Map<String, dynamic>? j) => AiResult(
        text: text,
        json: j,
        backend: backend,
        provider: provider,
        model: model,
        stopReason: stopReason,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        costUsd: costUsd,
        durationMs: durationMs,
        localEndpoint: localEndpoint,
        sources: sources,
        searchedWeb: searchedWeb,
      );
}

/// A file given to the model with the request (a PDF article).
class AiDocument {
  final String mediaType; // application/pdf
  final Uint8List bytes;
  final String name;
  const AiDocument(this.mediaType, this.bytes, this.name);
}

/// One web page an answer relied on.
class WebSource {
  final String title;
  final String url;
  const WebSource(this.title, this.url);

  Map<String, String> toJson() => {'title': title, 'url': url};

  static WebSource fromJson(Map<String, dynamic> j) =>
      WebSource((j['title'] ?? '').toString(), (j['url'] ?? '').toString());
}

/// localhost / private-network base URL (LM Studio, llama.cpp, LAN Ollama).
bool isLocalUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  if (host == 'localhost' || host.endsWith('.local') || host == '::1') {
    return true;
  }
  final m = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+$').firstMatch(host);
  if (m == null) return false;
  final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
  return a == 127 || a == 10 || (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31);
}

/// Parameter count in billions guessed from a model name ("qwen3:1.7b",
/// "gemma3:270m", "llama-3.3-70b-versatile"); null when not stated.
double? modelSizeB(String model) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*([bm])(?![a-z])', caseSensitive: false)
      .allMatches(model.toLowerCase())
      .toList();
  if (m.isEmpty) return null;
  final last = m.last;
  final v = double.parse(last.group(1)!);
  return last.group(2) == 'm' ? v / 1000 : v;
}

/// An error with a message written for the user (in Russian), never a raw
/// JSON body. [detail] keeps the technical text for Diagnostics.
class AiException implements Exception {
  final String message;
  final String? detail;
  final bool retryable;

  const AiException(this.message, {this.detail, this.retryable = false});

  @override
  String toString() => message;
}

/// USD per million tokens (input, output) — Anthropic list prices.
const kClaudePrices = <String, (double, double)>{
  'claude-opus-5': (5, 25),
  'claude-opus-5-5': (4, 20),
  'claude-sonnet-5': (2, 10),
  'claude-sonnet-5-5': (2, 10),
  // Haiku 5.5: prompts up to 100K tokens (above: $0.50 / $2.50).
  'claude-haiku-5-5': (0.1, 0.5),
  'claude-haiku-4-5': (1, 5),
};

double estimateClaudeCost(String model, int inTok, int outTok) {
  final p = kClaudePrices[model];
  if (p == null) return 0;
  return inTok / 1e6 * p.$1 + outTok / 1e6 * p.$2;
}

/// Claude Haiku 4.5 rejects `output_config.effort` with a 400 (Haiku 5.5
/// takes it).
bool claudeSupportsEffort(String model) => !model.startsWith('claude-haiku-4');

String claudeModelLabel(String model) => switch (model) {
      'claude-opus-5' => 'Opus 5',
      'claude-opus-5-5' => 'Opus 5.5',
      'claude-sonnet-5' => 'Sonnet 5',
      'claude-sonnet-5-5' => 'Sonnet 5.5',
      'claude-haiku-5-5' => 'Haiku 5.5',
      'claude-haiku-4-5' => 'Haiku 4.5',
      _ => model,
    };

/// Pull the first balanced JSON object out of text that may carry code
/// fences, a preamble or trailing chatter. Returns null if none parses.
Map<String, dynamic>? extractJsonObject(String text) {
  var s = text.trim();
  s = s.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'```\s*$', multiLine: true), '');
  final start = s.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) {
        try {
          final v = jsonDecode(s.substring(start, i + 1));
          return v is Map<String, dynamic> ? v : null;
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}
