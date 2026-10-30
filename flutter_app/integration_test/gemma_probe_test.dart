/// Diagnoses the on-device LLM install path on the current platform:
/// (1) FlutterGemma.initialize, (2) network download start.
/// Prints exact errors; cancels the download after first progress tick.
library;

import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lingua_trace/core/config.dart';

final _url = kDefaultLocalLlmUrl;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gemma init + download start probe', (tester) async {
    // 1. initialize
    try {
      await FlutterGemma.initialize(maxDownloadRetries: 1);
      // ignore: avoid_print
      print('PROBE initialize: OK');
    } catch (e, st) {
      // ignore: avoid_print
      print('PROBE initialize FAILED: $e\n$st');
      fail('initialize failed: $e');
    }

    try {
      final installed = await FlutterGemma.listInstalledModels();
      // ignore: avoid_print
      print('PROBE installed models: $installed');
    } catch (e) {
      // ignore: avoid_print
      print('PROBE listInstalledModels FAILED: $e');
    }

    // 2. download start — succeed on first progress tick
    final gotProgress = Completer<void>();
    try {
      final future = FlutterGemma.installModel(
        modelType: ModelType.qwen,
        fileType: ModelFileType.task,
      ).fromNetwork(_url).withProgress((pct) {
        // ignore: avoid_print
        print('PROBE progress: $pct%');
        if (!gotProgress.isCompleted && pct > 0) gotProgress.complete();
      }).install();

      await Future.any([
        gotProgress.future,
        future,
        Future.delayed(const Duration(seconds: 60), () {
          throw TimeoutException('no progress in 60s');
        }),
      ]);
      // ignore: avoid_print
      print('PROBE download: STARTED OK (progress ticking)');
    } catch (e, st) {
      // ignore: avoid_print
      print('PROBE download FAILED: $e\n$st');
      fail('download failed: $e');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
