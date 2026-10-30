package io.linguatrace.lingua_trace

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale

/**
 * Dictation without a time limit («Идеи»).
 *
 * Android 13+ ("stream" mode): the app records the microphone itself and
 * streams it into the recogniser (EXTRA_AUDIO_SOURCE) as one segmented
 * session, phrase after phrase. The recogniser never reopens the
 * microphone, so there is no start beep and no words are lost at pauses,
 * and a Bluetooth headset is switched on once, not at every phrase. While
 * Claude speaks (a discussion), silence is streamed instead of the mic.
 *
 * Where the recogniser ignores the app's audio and ends sessions by itself,
 * the classic loop takes over: a new session after each final result (never
 * before it — that cut phrases off and failed with ERROR_CLIENT), the media
 * sound muted against the beep. Transient trouble is retried for as long as
 * it takes; only a missing permission or language ends a dictation.
 *
 * To Dart: invokeMethod("event", {type: partial | final | state | fatal | log}).
 */
class LongSpeech(private val context: Context, private val channel: MethodChannel) :
    RecognitionListener {

    private val handler = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var recognizer: SpeechRecognizer? = null
    private var lang = "ru-RU"
    private var active = false
    private var stopping = false
    private var stopResult: MethodChannel.Result? = null
    private var ready = false
    private var sessionStart = 0L
    private var startedAt = 0L
    private var pending = ""          // words heard since the last final result
    private var sessionText = ""      // finals of this session (cumulative partials)
    private var failures = 0          // errors in a row, silence not counted
    private var restartQueued = false
    private var mutedByUs = false
    private var muteBeeps = true
    private var bluetooth = false
    private var bluetoothOn = false
    private var paused = false        // classic mode: Claude is speaking

    // Stream mode until the recogniser shows it ignores the app's audio.
    private var streamMode = false
    private var streamSegments = 0    // phrases that came through the stream
    private var streamFailures = 0    // sessions it ended without a phrase
    private var mic: MicStream? = null
    private var readEnd: ParcelFileDescriptor? = null

    @Volatile
    private var silenced = false      // stream mode: Claude is speaking

    /** Called whenever dictation ends (stop, fatal error, shutdown). */
    var onStopped: (() -> Unit)? = null

    val isActive get() = active

    /** Null when started, otherwise the reason it can't. */
    fun start(language: String, muteBeeps: Boolean, bluetooth: Boolean): String? {
        if (active) return null
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) return "error_permission"
        if (!SpeechRecognizer.isRecognitionAvailable(context)) return "error_no_recognizer"
        lang = language
        this.muteBeeps = muteBeeps
        this.bluetooth = bluetooth
        active = true
        stopping = false
        paused = false
        silenced = false
        failures = 0
        pending = ""
        streamSegments = 0
        streamFailures = 0
        startedAt = SystemClock.elapsedRealtime()
        log("start $lang · Android ${Build.VERSION.SDK_INT} · ${Build.MANUFACTURER} ${Build.MODEL}" +
            " · services=${services()}")
        if (bluetooth) bluetoothRoute(true)
        streamMode = false
        if (Build.VERSION.SDK_INT >= 33) {
            val m = MicStream()
            if (m.start()) {
                mic = m
                streamMode = true
                log("mode: stream (the app records, the recogniser listens to it)")
            } else {
                log("mode: classic (could not open the microphone for streaming)")
            }
        } else {
            log("mode: classic (Android < 13)")
        }
        if (!streamMode && muteBeeps) mute(true)
        listen()
        return null
    }

    /** Stop listening; the last phrase is delivered before [result] answers. */
    fun stop(result: MethodChannel.Result) {
        if (!active || stopping) {
            result.success(null)
            return
        }
        stopping = true
        stopResult = result
        log("stop")
        if (restartQueued || recognizer == null || paused) {
            finishStop()
            return
        }
        // Stream: the end of the audio ends the session with its last phrase.
        mic?.closePipe()
        try {
            recognizer?.stopListening()
        } catch (e: Exception) {
            log("stopListening: $e")
        }
        handler.postDelayed({ finishStop() }, 2500)
    }

    /** «Новая мысль» pressed mid-phrase: finish the phrase now, keep listening. */
    fun flush() {
        if (!active || stopping || pending.isBlank() || restartQueued || paused) return
        log("flush")
        if (streamMode) {
            mic?.closePipe() // the session ends with this phrase, the next one starts
        } else {
            try {
                recognizer?.stopListening()
            } catch (e: Exception) {
                log("stopListening: $e")
            }
        }
    }

    /** Claude speaks: the recogniser must not hear it (and must not beep). */
    fun pauseForSpeech(on: Boolean) {
        if (!active) return
        if (streamMode) {
            silenced = on
            return
        }
        if (on) {
            if (paused) return
            paused = true
            handler.removeCallbacksAndMessages(null)
            restartQueued = false
            try {
                recognizer?.cancel()
            } catch (_: Exception) {
            }
            deliver("")
            if (mutedByUs) mute(false) // the answer is heard on the media stream
        } else if (paused) {
            paused = false
            if (muteBeeps) mute(true)
            retry(null, 50)
        }
    }

    /** Everything off: recogniser, microphone, mute, foreground service. */
    fun shutdown() {
        val was = active || recognizer != null || mutedByUs || mic != null
        active = false
        stopping = false
        restartQueued = false
        paused = false
        silenced = false
        handler.removeCallbacksAndMessages(null)
        drop()
        mic?.stop()
        mic = null
        closeReadEnd()
        mute(false)
        bluetoothRoute(false)
        if (was) log("stopped")
        onStopped?.invoke()
    }

    // ─────────────────────────────────────────── the loop

    private fun listen() {
        restartQueued = false
        if (!active || stopping || paused) return
        try {
            val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(context).also {
                it.setRecognitionListener(this)
                recognizer = it
            }
            ready = false
            sessionText = ""
            sessionStart = SystemClock.elapsedRealtime()
            r.startListening(intent())
        } catch (e: Exception) {
            log("start failed: $e")
            drop()
            retry("error_start", backoff(1000))
        }
    }

    private fun intent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        val m = mic
        if (streamMode && m != null && Build.VERSION.SDK_INT >= 33) {
            closeReadEnd()
            val source = m.newPipe()
            readEnd = source
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, source)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, RATE)
            // The session lasts as long as the audio: phrases come as segments.
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
        } else {
            // Longer pauses before a phrase counts as finished (where honoured).
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
        }
    }

    override fun onReadyForSpeech(params: Bundle?) {
        ready = true
        log("ready")
        state("listening", "")
    }

    override fun onBeginningOfSpeech() {}
    override fun onRmsChanged(rmsdB: Float) {}
    override fun onBufferReceived(buffer: ByteArray?) {}
    override fun onEvent(eventType: Int, params: Bundle?) {}

    override fun onEndOfSpeech() {
        // Not the end of the session: the final result is still to come.
        if (!streamMode) log("end of speech")
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val t = fresh(best(partialResults))
        if (t.isEmpty()) return
        pending = t
        send(mapOf("type" to "partial", "text" to t))
    }

    override fun onSegmentResults(segmentResults: Bundle) {
        if (streamMode) streamSegments++
        deliver(fresh(best(segmentResults)))
    }

    override fun onEndOfSegmentedSession() {
        deliver("")
        closeReadEnd()
        log("segmented session over")
        sessionOver()
    }

    override fun onResults(results: Bundle?) {
        deliver(fresh(best(results)))
        closeReadEnd()
        log("session over")
        // The stream was ignored: the recogniser ended the session on its own.
        if (streamMode && streamSegments == 0 && !stopping) streamRefused("ended the session itself")
        sessionOver()
    }

    override fun onError(error: Int) {
        val code = codeName(error)
        val elapsed = SystemClock.elapsedRealtime() - sessionStart
        log("$code after $elapsed ms" + if (ready) "" else " (before ready)")
        closeReadEnd()
        if (stopping) {
            finishStop()
            return
        }
        if (!active || paused) return
        deliver("") // keep what was heard
        if (streamMode && streamSegments == 0) {
            // A stream session should never end on silence; twice → classic.
            streamFailures++
            if (streamFailures >= 2) {
                streamRefused(code)
                retry(null, 100)
                return
            }
        }
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                retry(null, 50)
            SpeechRecognizer.ERROR_CLIENT, SpeechRecognizer.ERROR_RECOGNIZER_BUSY, 11 -> {
                // Busy, confused or disconnected: a fresh recogniser.
                drop()
                retry(code, backoff(300))
            }
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    // Allowed, yet refused now: the app is in the background.
                    drop()
                    retry("error_background", backoff(2000))
                } else {
                    fatal("error_permission")
                }
            }
            12, 13 -> fatal(code) // language not supported / not available
            else -> { // network, server, too many requests, microphone busy…
                if (error != SpeechRecognizer.ERROR_NETWORK &&
                    error != SpeechRecognizer.ERROR_NETWORK_TIMEOUT
                ) drop()
                retry(code, backoff(1000))
            }
        }
    }

    /** The recogniser does not take the app's audio: the classic loop. */
    private fun streamRefused(why: String) {
        if (!streamMode) return
        streamMode = false
        mic?.stop()
        mic = null
        closeReadEnd()
        drop()
        log("mode: classic (the recogniser does not take the app's audio: $why)")
        if (muteBeeps) mute(true)
    }

    // ─────────────────────────────────────────── helpers

    /** A finished phrase; an empty result falls back to the words heard. */
    private fun deliver(text: String) {
        val t = text.ifBlank { pending }.trim()
        pending = ""
        if (t.isEmpty()) return
        failures = 0
        sessionText = (if (sessionText.isEmpty()) t else "$sessionText $t")
        send(mapOf("type" to "final", "text" to t))
        log("phrase, ${t.length} chars")
    }

    private fun sessionOver() {
        if (stopping) {
            finishStop()
            return
        }
        retry(null, if (streamMode) 0 else 50)
    }

    private fun retry(trouble: String?, delay: Long) {
        if (!active || stopping || paused) return
        if (trouble != null) state("waiting", trouble)
        if (restartQueued) return
        restartQueued = true
        if (delay >= 300) log("restart in $delay ms")
        handler.postDelayed({ listen() }, delay)
    }

    private fun backoff(base: Long): Long {
        failures++
        return minOf(base * failures, 5000L)
    }

    private fun finishStop() {
        if (!stopping) return
        deliver("")
        val r = stopResult
        stopResult = null
        shutdown()
        r?.success(null)
    }

    private fun fatal(code: String) {
        log("fatal $code")
        send(mapOf("type" to "fatal", "code" to code))
        shutdown()
    }

    private fun drop() {
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
    }

    private fun closeReadEnd() {
        try {
            readEnd?.close()
        } catch (_: Exception) {
        }
        readEnd = null
    }

    private fun mute(on: Boolean) {
        try {
            if (on && !mutedByUs && !audio.isStreamMute(AudioManager.STREAM_MUSIC)) {
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)
                mutedByUs = true
                prefs(context).edit().putBoolean(KEY_MUTED, true).apply()
                log("media sound off")
            } else if (!on && mutedByUs) {
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)
                mutedByUs = false
                prefs(context).edit().remove(KEY_MUTED).apply()
                log("media sound on")
            }
        } catch (e: Exception) {
            log("mute: $e")
        }
    }

    /** The headset's microphone (Android 12+), switched on once per dictation. */
    private fun bluetoothRoute(on: Boolean) {
        if (Build.VERSION.SDK_INT < 31) {
            if (on) log("bluetooth microphone: needs Android 12+")
            return
        }
        try {
            if (on) {
                val sco = audio.availableCommunicationDevices
                    .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                if (sco == null) {
                    log("bluetooth microphone: no headset connected")
                    return
                }
                bluetoothOn = audio.setCommunicationDevice(sco)
                log("bluetooth microphone: ${sco.productName} → $bluetoothOn")
            } else if (bluetoothOn) {
                audio.clearCommunicationDevice()
                bluetoothOn = false
                log("bluetooth microphone off")
            }
        } catch (e: Exception) {
            log("bluetooth microphone: $e")
        }
    }

    private fun services(): String = try {
        context.packageManager
            .queryIntentServices(Intent(RecognitionService.SERVICE_INTERFACE), 0)
            .joinToString(",") { it.serviceInfo.packageName }
    } catch (e: Exception) {
        "?"
    }

    /** Some recognisers repeat the session's earlier phrases: only the new words. */
    private fun fresh(t: String): String =
        if (sessionText.isNotEmpty() && t.startsWith(sessionText, ignoreCase = true))
            t.substring(sessionText.length).trim()
        else t

    private fun best(b: Bundle?): String =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim() ?: ""

    private fun state(s: String, detail: String) =
        send(mapOf("type" to "state", "state" to s, "detail" to detail))

    fun log(msg: String) {
        val t = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
        send(mapOf("type" to "log", "text" to String.format(Locale.US, "%6.1f s  %s", t, msg)))
    }

    /** Events go to Dart from the main thread (the microphone thread logs too). */
    private fun send(m: Map<String, Any>) {
        val post = Runnable {
            try {
                channel.invokeMethod("event", m)
            } catch (_: Exception) {
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) post.run() else handler.post(post)
    }

    private fun codeName(e: Int) = when (e) {
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "error_network_timeout"
        SpeechRecognizer.ERROR_NETWORK -> "error_network"
        SpeechRecognizer.ERROR_AUDIO -> "error_audio"
        SpeechRecognizer.ERROR_SERVER -> "error_server"
        SpeechRecognizer.ERROR_CLIENT -> "error_client"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "error_speech_timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "error_no_match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "error_busy"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "error_permission"
        10 -> "error_too_many_requests"
        11 -> "error_server_disconnected"
        12 -> "error_language_not_supported"
        13 -> "error_language_unavailable"
        else -> "error_$e"
    }

    // ─────────────────────────────────────────── the microphone

    /** The microphone, recorded by the app and streamed into the recogniser. */
    private inner class MicStream {
        private var record: AudioRecord? = null
        private var thread: Thread? = null

        @Volatile
        private var out: ParcelFileDescriptor.AutoCloseOutputStream? = null

        @Volatile
        private var running = false

        @SuppressLint("MissingPermission") // checked in start()
        fun start(): Boolean = try {
            val min = AudioRecord.getMinBufferSize(
                RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            if (min <= 0) {
                false
            } else {
                // Two seconds of room: a slow reader must not drop audio.
                val r = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(min, RATE * 2 * 2)
                )
                if (r.state != AudioRecord.STATE_INITIALIZED) {
                    r.release()
                    false
                } else {
                    route(r)
                    r.startRecording()
                    record = r
                    running = true
                    thread = Thread({ pump(r, min) }, "lt-mic").also { it.start() }
                    true
                }
            }
        } catch (e: Exception) {
            log("microphone: $e")
            false
        }

        /** A fresh pipe for the next recogniser session; returns its read end. */
        fun newPipe(): ParcelFileDescriptor {
            val pipe = ParcelFileDescriptor.createPipe()
            val old = out
            out = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
            try {
                old?.close()
            } catch (_: IOException) {
            }
            return pipe[0]
        }

        /** The end of this session's audio: the recogniser finishes it. */
        fun closePipe() {
            val o = out
            out = null
            try {
                o?.close()
            } catch (_: IOException) {
            }
        }

        private fun pump(r: AudioRecord, size: Int) {
            val buf = ByteArray(size)
            val zero = ByteArray(size)
            while (running) {
                val n = r.read(buf, 0, buf.size, AudioRecord.READ_BLOCKING)
                if (n == AudioRecord.ERROR_DEAD_OBJECT) {
                    log("microphone lost")
                    break
                }
                if (n <= 0) {
                    Thread.sleep(10)
                    continue
                }
                val o = out ?: continue
                try {
                    o.write(if (silenced) zero else buf, 0, n)
                } catch (_: IOException) {
                    // This session's pipe is closed; the next one brings its own.
                }
            }
        }

        private fun route(r: AudioRecord) {
            try {
                val inputs = audio.getDevices(AudioManager.GET_DEVICES_INPUTS)
                val want = if (bluetooth && bluetoothOn) {
                    inputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                } else {
                    inputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                }
                if (want != null) r.setPreferredDevice(want)
                val kind = if (want?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) "headset" else "phone"
                log("microphone: $kind")
            } catch (e: Exception) {
                log("microphone route: $e")
            }
        }

        fun stop() {
            running = false
            closePipe()
            try {
                record?.stop()
            } catch (_: Exception) {
            }
            try {
                thread?.join(500)
            } catch (_: Exception) {
            }
            try {
                record?.release()
            } catch (_: Exception) {
            }
            record = null
            thread = null
        }
    }

    companion object {
        private const val KEY_MUTED = "dictation_muted_music"

        /** The stream's sample rate: 16 kHz, mono, 16-bit PCM. */
        const val RATE = 16000

        private fun prefs(c: Context) =
            c.getSharedPreferences("linguatrace_native", Context.MODE_PRIVATE)

        /** The app died while dictating: give the user their sound back. */
        fun restoreSound(c: Context) {
            val p = prefs(c)
            if (!p.getBoolean(KEY_MUTED, false)) return
            try {
                (c.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                    .adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)
            } catch (_: Exception) {
            }
            p.edit().remove(KEY_MUTED).apply()
        }
    }
}
