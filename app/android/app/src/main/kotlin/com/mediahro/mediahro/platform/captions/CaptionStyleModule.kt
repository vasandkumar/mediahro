package com.mediahro.mediahro.platform.captions

import android.content.Context
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.view.accessibility.CaptioningManager
import com.mediahro.mediahro.pigeon.CaptionEdgeMsg
import com.mediahro.mediahro.pigeon.CaptionStyleChangesStreamHandler
import com.mediahro.mediahro.pigeon.CaptionStyleHostApi
import com.mediahro.mediahro.pigeon.CaptionStyleMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink
import java.util.Locale

/**
 * CaptionStyleFacade on Android (ADR-030, SUB-014, docs/06 §7): the
 * Settings › Accessibility › Caption preferences from CaptioningManager.
 * Only values the user set are reported; the rest stay null so the
 * player's own defaults apply.
 */
class CaptionStyleModule(context: Context) : CaptionStyleHostApi {
    private val captioning = context.getSystemService(CaptioningManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    override fun current(): CaptionStyleMsg? = captioning?.let(::styleOf)

    private fun styleOf(cm: CaptioningManager): CaptionStyleMsg {
        val style = cm.userStyle
        return CaptionStyleMsg(
            enabled = cm.isEnabled,
            fontFamily = style.typeface?.let(::familyOf),
            scale = cm.fontScale.toDouble(),
            foregroundArgb = style.foregroundColor.toLong().takeIf { style.hasForegroundColor() }?.and(MASK),
            backgroundArgb = style.backgroundColor.toLong().takeIf { style.hasBackgroundColor() }?.and(MASK),
            windowArgb = style.windowColor.toLong().takeIf { style.hasWindowColor() }?.and(MASK),
            edge = edgeOf(style),
            edgeArgb = style.edgeColor.toLong().takeIf { style.hasEdgeColor() }?.and(MASK),
        )
    }

    private fun edgeOf(style: CaptioningManager.CaptionStyle): CaptionEdgeMsg {
        if (!style.hasEdgeType()) return CaptionEdgeMsg.NONE
        return when (style.edgeType) {
            CaptioningManager.CaptionStyle.EDGE_TYPE_OUTLINE -> CaptionEdgeMsg.OUTLINE
            CaptioningManager.CaptionStyle.EDGE_TYPE_DROP_SHADOW -> CaptionEdgeMsg.DROP_SHADOW
            CaptioningManager.CaptionStyle.EDGE_TYPE_RAISED -> CaptionEdgeMsg.RAISED
            CaptioningManager.CaptionStyle.EDGE_TYPE_DEPRESSED -> CaptionEdgeMsg.DEPRESSED
            else -> CaptionEdgeMsg.NONE
        }
    }

    /**
     * The system's caption fonts are fixed families; the style hands back a
     * Typeface, so it is matched against them (Typeface.create caches).
     */
    private fun familyOf(typeface: Typeface): String? =
        FAMILIES.firstOrNull { name ->
            Typeface.create(name, Typeface.NORMAL) == typeface || Typeface.create(name, typeface.style) == typeface
        }

    private var sink: PigeonEventSink<CaptionStyleMsg>? = null
    private val listener = object : CaptioningManager.CaptioningChangeListener() {
        override fun onEnabledChanged(enabled: Boolean) = publish()
        override fun onUserStyleChanged(userStyle: CaptioningManager.CaptionStyle) = publish()
        override fun onFontScaleChanged(fontScale: Float) = publish()
        override fun onLocaleChanged(locale: Locale?) = publish()
    }

    private fun publish() {
        val cm = captioning ?: return
        main.post { sink?.success(styleOf(cm)) }
    }

    val changesHandler = object : CaptionStyleChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<CaptionStyleMsg>) {
            this@CaptionStyleModule.sink = sink
            captioning?.addCaptioningChangeListener(listener)
        }

        override fun onCancel(p0: Any?) {
            captioning?.removeCaptioningChangeListener(listener)
            sink = null
        }
    }

    fun dispose() {
        captioning?.removeCaptioningChangeListener(listener)
    }

    companion object {
        private const val MASK = 0xFFFFFFFFL

        /** Caption fonts offered in Android's accessibility settings. */
        private val FAMILIES = listOf(
            "sans-serif",
            "sans-serif-condensed",
            "sans-serif-monospace",
            "serif",
            "serif-monospace",
            "casual",
            "cursive",
            "sans-serif-smallcaps",
        )
    }
}
