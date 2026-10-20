package com.mediahro.mediahro.platform.text

import android.content.Context
import android.os.Bundle
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.SpeechHostApi
import com.mediahro.mediahro.pigeon.SpeechVoiceMsg
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred

/**
 * SpeechSynthesisFacade on Android (SUB-040: spoken subtitles): the
 * system TextToSpeech engine with the user's default voice and rate unless
 * the caller picks a voice or a relative rate.
 */
class SpeechModule(private val context: Context) : SpeechHostApi {
    private var tts: TextToSpeech? = null
    private val ready = CompletableDeferred<TextToSpeech>()
    private val pending = ConcurrentHashMap<String, CompletableDeferred<Unit>>()

    private suspend fun engine(): TextToSpeech {
        if (tts == null) {
            tts = TextToSpeech(context.applicationContext) { status ->
                val engine = tts
                if (status == TextToSpeech.SUCCESS && engine != null) {
                    engine.setOnUtteranceProgressListener(progress)
                    ready.complete(engine)
                } else {
                    ready.completeExceptionally(FlutterError("unavailable", "No text-to-speech engine"))
                }
            }
        }
        return ready.await()
    }

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {}

        override fun onDone(utteranceId: String) {
            pending.remove(utteranceId)?.complete(Unit)
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) {
            pending.remove(utteranceId)?.completeExceptionally(FlutterError("speechFailed", "Speech failed"))
        }

        override fun onError(utteranceId: String, errorCode: Int) {
            pending.remove(utteranceId)?.completeExceptionally(FlutterError("speechFailed", "Speech failed ($errorCode)"))
        }

        override fun onStop(utteranceId: String, interrupted: Boolean) {
            pending.remove(utteranceId)?.complete(Unit)
        }
    }

    override suspend fun voices(): List<SpeechVoiceMsg> =
        engine().voices.orEmpty()
            .filterNot { it.isNetworkConnectionRequired }
            .map { SpeechVoiceMsg(it.name, it.name, it.locale.toLanguageTag()) }
            .sortedWith(compareBy({ it.languageTag }, { it.name }))

    override suspend fun speak(text: String, languageTag: String?, voiceId: String?, rate: Double) {
        val engine = engine()
        // Offline voices only: a network voice would send subtitle text off the device.
        val voice = voiceId?.let { id -> engine.voices.orEmpty().firstOrNull { it.name == id && !it.isNetworkConnectionRequired } }
        when {
            voice != null -> engine.voice = voice
            languageTag != null -> engine.setLanguage(Locale.forLanguageTag(languageTag))
        }
        // Relative to the user's own default rate (Settings > Text-to-speech).
        engine.setSpeechRate((systemRate() * rate).toFloat().coerceIn(0.1f, 4f))
        val id = UUID.randomUUID().toString()
        val done = CompletableDeferred<Unit>()
        pending[id] = done
        val params = Bundle()
        if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, id) != TextToSpeech.SUCCESS) {
            pending.remove(id)
            throw FlutterError("speechFailed", "The speech engine refused the text")
        }
        done.await()
    }

    /** The user's default speech rate; 100 means 1.0. */
    @Suppress("DEPRECATION")
    private fun systemRate(): Double =
        Settings.Secure.getInt(context.contentResolver, Settings.Secure.TTS_DEFAULT_RATE, 100) / 100.0

    override fun stop() {
        tts?.stop()
        pending.values.forEach { it.complete(Unit) }
        pending.clear()
    }

    fun dispose() {
        stop()
        tts?.shutdown()
        tts = null
    }
}
