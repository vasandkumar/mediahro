package com.mediahro.mediahro.platform.text

import android.content.Context
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.RecognizedLineMsg
import com.mediahro.mediahro.pigeon.TextRecognitionHostApi
import com.mediahro.mediahro.pigeon.TranslationHostApi
import com.mediahro.mediahro.pigeon.TranslationPairMsg

/**
 * The `foss` and `enterprise` builds have no proprietary ML Kit (ADR-025
 * §5): recognition reports unsupported, so SUB-051 uses Tesseract over FFI,
 * and on-device translation is unavailable.
 */
object TextServices {
    const val ML_KIT = false

    fun recognition(@Suppress("UNUSED_PARAMETER") context: Context): TextRecognitionHostApi = Unsupported

    fun translation(): TranslationHostApi = NoTranslation

    private object Unsupported : TextRecognitionHostApi {
        override suspend fun isSupported(languageTag: String) = false

        override suspend fun recognize(
            rgba: ByteArray,
            width: Long,
            height: Long,
            languageTags: List<String>,
        ): List<RecognizedLineMsg> = throw FlutterError("unsupported", "No platform text recognition in this build")

        override suspend fun identifyLanguage(text: String): String? = null
    }

    private object NoTranslation : TranslationHostApi {
        override fun supportedPairs(): List<TranslationPairMsg> = emptyList()

        override suspend fun isReady(from: String, to: String) = false

        override suspend fun prepare(from: String, to: String) =
            throw FlutterError("unsupported", "No on-device translation in this build")

        override suspend fun translate(lines: List<String>, from: String, to: String): List<String> =
            throw FlutterError("unsupported", "No on-device translation in this build")
    }
}
