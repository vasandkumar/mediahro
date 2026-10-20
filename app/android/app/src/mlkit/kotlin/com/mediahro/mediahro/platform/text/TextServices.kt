package com.mediahro.mediahro.platform.text

import android.content.Context
import android.graphics.Bitmap
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.RecognizedLineMsg
import com.mediahro.mediahro.pigeon.TextRecognitionHostApi
import com.mediahro.mediahro.pigeon.TranslationHostApi
import com.mediahro.mediahro.pigeon.TranslationPairMsg
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

/**
 * ML Kit text services for the `store` and `direct` builds (ADR-025 §5:
 * ML Kit is proprietary). The `foss` and `enterprise` builds compile the
 * stub in `src/nomlkit`, and SUB-051 falls back to Tesseract over FFI.
 * Models run on the device: recognisers and language ID come with Google
 * Play services; translation models download only through [prepare] after
 * the user agrees (PRIV-004).
 */
object TextServices {
    const val ML_KIT = true

    fun recognition(context: Context): TextRecognitionHostApi = MlKitTextRecognition(context.applicationContext)

    fun translation(): TranslationHostApi = MlKitTranslation()
}

internal class MlKitTextRecognition(private val context: Context) : TextRecognitionHostApi {
    private enum class Script { LATIN, CHINESE, DEVANAGARI, JAPANESE, KOREAN }

    private val recognizers = ConcurrentHashMap<Script, TextRecognizer>()
    private val languageId by lazy { LanguageIdentification.getClient() }

    private val playServices: Boolean
        get() = GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    private fun scriptOf(tag: String): Script? {
        val lang = Locale.forLanguageTag(tag).language
        return when {
            lang == "zh" -> Script.CHINESE
            lang == "ja" -> Script.JAPANESE
            lang == "ko" -> Script.KOREAN
            lang in DEVANAGARI -> Script.DEVANAGARI
            lang in LATIN -> Script.LATIN
            else -> null
        }
    }

    private fun recognizer(script: Script): TextRecognizer = recognizers.getOrPut(script) {
        when (script) {
            Script.LATIN -> TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            Script.CHINESE -> TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
            Script.DEVANAGARI -> TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
            Script.JAPANESE -> TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
            Script.KOREAN -> TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
        }
    }

    override suspend fun isSupported(languageTag: String): Boolean = playServices && scriptOf(languageTag) != null

    override suspend fun recognize(rgba: ByteArray, width: Long, height: Long, languageTags: List<String>): List<RecognizedLineMsg> {
        if (!playServices) throw FlutterError("unsupported", "Google Play services are not available")
        val w = width.toInt()
        val h = height.toInt()
        if (w <= 0 || h <= 0 || rgba.size < w * h * 4) throw FlutterError("invalidArgument", "Bad RGBA buffer ${w}x$h")
        val script = languageTags.firstNotNullOfOrNull(::scriptOf) ?: Script.LATIN
        val bitmap = withContext(Dispatchers.Default) {
            // ARGB_8888 is RGBA in memory, so the subtitle bytes copy as is.
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply {
                copyPixelsFromBuffer(ByteBuffer.wrap(rgba, 0, w * h * 4))
            }
        }
        val text = try {
            recognizer(script).process(InputImage.fromBitmap(bitmap, 0)).await()
        } catch (e: Exception) {
            throw FlutterError("ocrFailed", e.message)
        } finally {
            bitmap.recycle()
        }
        return text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
            val box = line.boundingBox ?: return@mapNotNull null
            RecognizedLineMsg(
                text = line.text,
                confidence = line.confidence.toDouble().coerceIn(0.0, 1.0),
                left = box.left.toLong(),
                top = box.top.toLong(),
                width = box.width().toLong(),
                height = box.height().toLong(),
            )
        }
    }

    override suspend fun identifyLanguage(text: String): String? {
        if (!playServices || text.isBlank()) return null
        val tag = try {
            languageId.identifyLanguage(text).await()
        } catch (e: Exception) {
            return null
        }
        return tag.takeUnless { it == "und" }
    }

    companion object {
        /** Languages ML Kit's Latin recogniser reads. */
        private val LATIN = setOf(
            "af", "sq", "bs", "ca", "hr", "cs", "da", "nl", "en", "et", "fil", "tl", "fi", "fr", "gl", "de", "hu",
            "is", "id", "ga", "it", "lv", "lt", "ms", "mt", "no", "nb", "nn", "pl", "pt", "ro", "sr", "sk", "sl",
            "es", "sw", "sv", "tr", "cy", "eu", "lb", "la",
        )
        private val DEVANAGARI = setOf("hi", "mr", "ne", "sa", "bho", "mai", "kok", "doi")
    }
}

internal class MlKitTranslation : TranslationHostApi {
    private val translators = ConcurrentHashMap<Pair<String, String>, Translator>()

    private fun code(tag: String): String =
        TranslateLanguage.fromLanguageTag(tag) ?: throw FlutterError("unsupported", "No translation for $tag")

    private fun translator(from: String, to: String): Translator = translators.getOrPut(from to to) {
        Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(from).setTargetLanguage(to).build())
    }

    override fun supportedPairs(): List<TranslationPairMsg> {
        val langs = TranslateLanguage.getAllLanguages().sorted()
        return langs.flatMap { from -> langs.filter { it != from }.map { TranslationPairMsg(from, it) } }
    }

    override suspend fun isReady(from: String, to: String): Boolean {
        val needed = setOf(code(from), code(to)) - TranslateLanguage.ENGLISH
        if (needed.isEmpty()) return true
        val downloaded = RemoteModelManager.getInstance()
            .getDownloadedModels(TranslateRemoteModel::class.java).await()
            .map { it.language }.toSet()
        return downloaded.containsAll(needed)
    }

    override suspend fun prepare(from: String, to: String) {
        try {
            translator(code(from), code(to)).downloadModelIfNeeded(DownloadConditions.Builder().build()).await()
        } catch (e: FlutterError) {
            throw e
        } catch (e: Exception) {
            throw FlutterError("downloadFailed", e.message)
        }
    }

    override suspend fun translate(lines: List<String>, from: String, to: String): List<String> {
        // Never download implicitly: prepare() runs only after consent.
        if (!isReady(from, to)) throw FlutterError("notReady", "Download the $from-$to language pack first")
        val t = translator(code(from), code(to))
        return lines.map { line ->
            if (line.isBlank()) {
                line
            } else {
                try {
                    t.translate(line).await()
                } catch (e: Exception) {
                    throw FlutterError("translateFailed", e.message)
                }
            }
        }
    }
}
