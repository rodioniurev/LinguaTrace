package io.linguatrace.lingua_trace

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * Claude's answers read aloud during a discussion («Идеи»), with the phone's
 * text-to-speech. [onDone] reports each utterance id when it is spoken (or
 * failed, or was stopped), so the dictation can listen again.
 */
class Speaker(context: Context, private val onDone: (id: String, ok: Boolean) -> Unit) :
    TextToSpeech.OnInitListener {

    private val handler = Handler(Looper.getMainLooper())
    private val tts = TextToSpeech(context.applicationContext, this)
    private var ready = false
    private var failed = false
    private val waiting = mutableListOf<Triple<String, String, String>>()

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        failed = !ready
        if (ready) {
            tts.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(
                        if (Build.VERSION.SDK_INT >= 26) AudioAttributes.USAGE_ASSISTANT
                        else AudioAttributes.USAGE_MEDIA
                    )
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) = done(utteranceId, true)

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = done(utteranceId, false)
                override fun onError(utteranceId: String?, errorCode: Int) = done(utteranceId, false)
                override fun onStop(utteranceId: String?, interrupted: Boolean) =
                    done(utteranceId, false)
            })
        }
        val queued = waiting.toList()
        waiting.clear()
        for ((text, lang, id) in queued) speak(text, lang, id)
    }

    private fun done(id: String?, ok: Boolean) {
        handler.post { onDone(id ?: "", ok) }
    }

    /** [lang] is a tag such as "ru-RU". */
    fun speak(text: String, lang: String, id: String) {
        if (failed) {
            done(id, false)
            return
        }
        if (!ready) {
            waiting.add(Triple(text, lang, id))
            return
        }
        try {
            tts.setLanguage(Locale.forLanguageTag(lang))
        } catch (_: Exception) {
        }
        val r = tts.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), id)
        if (r != TextToSpeech.SUCCESS) done(id, false)
    }

    fun stop() {
        try {
            tts.stop()
        } catch (_: Exception) {
        }
    }

    fun shutdown() {
        try {
            tts.stop()
            tts.shutdown()
        } catch (_: Exception) {
        }
    }
}
