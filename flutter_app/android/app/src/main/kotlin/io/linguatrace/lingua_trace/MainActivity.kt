package io.linguatrace.lingua_trace

import android.content.Intent
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "io.linguatrace/share_intent"
    private var initialSharedText: String? = null
    private var longSpeech: LongSpeech? = null
    private var speaker: Speaker? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Read intent on launch
        initialSharedText = extractText(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialText" -> result.success(initialSharedText)
                    "reset"         -> { initialSharedText = null; result.success(null) }
                    else            -> result.notImplemented()
                }
            }

        // Device channel — keep the screen on while dictating
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.linguatrace/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Long dictation («Идеи»): the native recogniser loop + a foreground
        // service so it keeps hearing with the screen off.
        LongSpeech.restoreSound(applicationContext)
        val speechChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.linguatrace/long_speech")
        longSpeech?.shutdown()
        val speech = LongSpeech(applicationContext, speechChannel).also { longSpeech = it }
        speech.onStopped = { DictationService.stop(applicationContext) }
        // A discussion: Claude's answer is read aloud while the recogniser
        // hears silence, then dictation goes on.
        speaker?.shutdown()
        val voice = Speaker(applicationContext) { id, ok ->
            speech.pauseForSpeech(false)
            try {
                speechChannel.invokeMethod(
                    "event", mapOf("type" to "spoken", "id" to id, "ok" to ok)
                )
            } catch (_: Exception) {
            }
        }.also { speaker = it }
        speechChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val err = speech.start(
                        call.argument<String>("lang") ?: "ru-RU",
                        call.argument<Boolean>("mute") ?: true,
                        call.argument<Boolean>("bluetooth") ?: false
                    )
                    if (err == null) DictationService.start(applicationContext)
                    result.success(err)
                }
                "stop" -> speech.stop(result)
                "flush" -> {
                    speech.flush()
                    result.success(null)
                }
                "speak" -> {
                    speech.pauseForSpeech(true)
                    voice.speak(
                        call.argument<String>("text") ?: "",
                        call.argument<String>("lang") ?: "ru-RU",
                        call.argument<String>("id") ?: ""
                    )
                    result.success(null)
                }
                "stopSpeaking" -> {
                    voice.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Browser channel — open URLs in external browser
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.linguatrace/browser")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.arguments as? String
                        if (url != null) {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(true)
                        } else {
                            result.error("INVALID_URL", "URL is null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        longSpeech?.shutdown()
        longSpeech = null
        speaker?.shutdown()
        speaker = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = extractText(intent) ?: return
        // Send to Flutter via channel
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("onSharedText", text)
        }
    }

    private fun extractText(intent: Intent?): String? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_SEND ->
                if (intent.type == "text/plain")
                    intent.getStringExtra(Intent.EXTRA_TEXT)
                else null
            Intent.ACTION_PROCESS_TEXT ->
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            else -> null
        }
    }
}
