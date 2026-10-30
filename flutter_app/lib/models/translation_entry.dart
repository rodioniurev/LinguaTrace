class TranslationEntry {
  final int? id;
  final String sourceText;
  final String translatedText;
  final String sourceLang;
  final String targetLang;
  final String translator;
  final String contextApp;
  final String timestamp;
  /// 'windows:<host>' / 'android' — where the lookup happened.
  final String device;

  const TranslationEntry({
    this.id,
    required this.sourceText,
    required this.translatedText,
    required this.sourceLang,
    required this.targetLang,
    required this.translator,
    this.contextApp = '',
    this.timestamp = '',
    this.device = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'source_text': sourceText,
        'translated_text': translatedText,
        'source_lang': sourceLang,
        'target_lang': targetLang,
        'translator': translator,
        'context_app': contextApp,
        'device': device,
      };

  factory TranslationEntry.fromMap(Map<String, dynamic> m) => TranslationEntry(
        id: m['id'] as int?,
        sourceText: m['source_text'] as String,
        translatedText: m['translated_text'] as String,
        sourceLang: m['source_lang'] as String,
        targetLang: m['target_lang'] as String,
        translator: m['translator'] as String,
        contextApp: m['context_app'] as String? ?? '',
        timestamp: m['timestamp'] as String? ?? '',
        device: m['device'] as String? ?? '',
      );
}
