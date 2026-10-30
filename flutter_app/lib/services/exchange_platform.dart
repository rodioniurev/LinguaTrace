/// Phone side of the exchange: send this device's file through the system
/// share sheet (to Drive/OneDrive/Telegram/the PC) and pick a file to merge.
library;

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareExchangeFile(String path) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(path, mimeType: 'application/json')],
    subject: 'LinguaTrace',
    text: 'LinguaTrace — файл обмена',
  ));
}

/// Returns a local path to the chosen file, or null if cancelled.
Future<String?> pickExchangeFile() async {
  // Some apps (Telegram, Drive) hand out JSON with a generic MIME type, so
  // no extension filter — the content is validated on import anyway.
  final f = await FilePicker.pickFile(type: FileType.any);
  return f?.path;
}

/// Drop the copies the picker made in the app cache (Android copies every
/// picked file there and never deletes it).
Future<void> clearPickedFiles() async {
  try {
    await FilePicker.clearTemporaryFiles();
  } catch (_) {
    // Not supported on this platform, or nothing to clear.
  }
}
