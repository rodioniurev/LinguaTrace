/// Just enough Markdown for the research notes: headings, bullets, bold
/// and links (tap opens the browser). Selectable.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MarkdownLite extends StatefulWidget {
  final String text;
  final double fontSize;
  const MarkdownLite(this.text, {super.key, this.fontSize = 14});

  @override
  State<MarkdownLite> createState() => _MarkdownLiteState();
}

class _MarkdownLiteState extends State<MarkdownLite> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static final _inline = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\((https?://[^)\s]+)\)');

  List<InlineSpan> _inlineSpans(String line, TextStyle base, ColorScheme cs) {
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > pos) spans.add(TextSpan(text: line.substring(pos, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(
            text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        final url = m.group(3)!;
        final rec = TapGestureRecognizer()
          ..onTap = () async {
            try {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            } catch (_) {}
          };
        _recognizers.add(rec);
        spans.add(TextSpan(
            text: m.group(2),
            recognizer: rec,
            style: TextStyle(
                color: cs.primary, decoration: TextDecoration.underline)));
      }
      pos = m.end;
    }
    if (pos < line.length) spans.add(TextSpan(text: line.substring(pos)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final cs = Theme.of(context).colorScheme;
    final base = TextStyle(
        fontSize: widget.fontSize, height: 1.45, color: cs.onSurface);
    final spans = <InlineSpan>[];
    final lines = widget.text.replaceAll('\r', '').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final t = raw.trimRight();
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t.trimLeft());
      if (heading != null) {
        if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
        spans.add(TextSpan(
          text: heading.group(2),
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: widget.fontSize + (heading.group(1)!.length <= 2 ? 3 : 1),
              color: cs.onSurface),
        ));
      } else {
        final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(t);
        if (bullet != null) {
          spans.add(const TextSpan(text: '  •  '));
          spans.addAll(_inlineSpans(bullet.group(1)!, base, cs));
        } else {
          spans.addAll(_inlineSpans(t, base, cs));
        }
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}
