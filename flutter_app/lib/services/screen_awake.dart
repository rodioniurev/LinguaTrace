/// Keeps the screen on during a dictation: with the screen off Android
/// pauses the app and the recogniser stops.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class ScreenAwake {
  ScreenAwake._();

  static const _channel = MethodChannel('io.linguatrace/device');

  static Future<void> set(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('keepScreenOn', on);
    } catch (_) {
      // Older build of the Android side: the dictation still works.
    }
  }
}
