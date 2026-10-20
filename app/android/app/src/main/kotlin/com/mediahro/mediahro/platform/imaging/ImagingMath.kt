package com.mediahro.mediahro.platform.imaging

import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** Pure rules of the imaging module (JVM-testable; no Android types). */
internal object ImagingMath {
    /** Largest decode edge for [maxEdge] (null: full size): the integer factor to scale by. */
    fun targetSize(width: Int, height: Int, maxEdge: Int?): Pair<Int, Int> {
        if (maxEdge == null || maxEdge <= 0) return width to height
        val longest = max(width, height)
        if (longest <= maxEdge) return width to height
        val s = maxEdge.toDouble() / longest
        return max(1, (width * s).roundToInt()) to max(1, (height * s).roundToInt())
    }

    /** A region in full-image pixels mapped into the scaled image, clamped to its bounds. */
    fun scaledRegion(
        left: Double,
        top: Double,
        right: Double,
        bottom: Double,
        fullWidth: Int,
        fullHeight: Int,
        scaledWidth: Int,
        scaledHeight: Int,
    ): IntArray {
        val sx = scaledWidth.toDouble() / fullWidth
        val sy = scaledHeight.toDouble() / fullHeight
        val l = (left * sx).toInt().coerceIn(0, scaledWidth - 1)
        val t = (top * sy).toInt().coerceIn(0, scaledHeight - 1)
        val r = kotlin.math.ceil(right * sx).toInt().coerceIn(l + 1, scaledWidth)
        val b = kotlin.math.ceil(bottom * sy).toInt().coerceIn(t + 1, scaledHeight)
        return intArrayOf(l, t, r, b)
    }

    /** sRGB transfer, 0..1 encoded to linear. */
    fun srgbToLinear(c: Float): Float =
        if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)

    /** Ultra HDR gain-map parameters for one colour channel. */
    class GainParams(
        val ratioMin: Float,
        val ratioMax: Float,
        val gamma: Float,
        val epsilonSdr: Float,
        val epsilonHdr: Float,
    )

    /**
     * The HDR value (linear, 1.0 = SDR white) of one channel: [sdrLinear] from
     * the base image, [gain] the gain-map sample (0..1), at full HDR weight
     * (ISO 21496-1 / Android `Gainmap`).
     */
    fun applyGain(sdrLinear: Float, gain: Float, p: GainParams): Float {
        val recovery = gain.coerceIn(0f, 1f).pow(1f / p.gamma)
        val logBoost = ln(p.ratioMin) * (1f - recovery) + ln(p.ratioMax) * recovery
        return (sdrLinear + p.epsilonSdr) * exp(logBoost) - p.epsilonHdr
    }

    /** IEEE 754 binary16 bits of [f] (round to nearest even), for RGBA F16 pixels. */
    fun halfBits(f: Float): Int {
        val bits = java.lang.Float.floatToRawIntBits(f)
        val sign = (bits ushr 16) and 0x8000
        val exp = ((bits ushr 23) and 0xff) - 127 + 15
        val mant = bits and 0x7fffff
        return when {
            ((bits ushr 23) and 0xff) == 0xff -> sign or 0x7c00 or (if (mant != 0) 0x200 else 0)
            exp >= 31 -> sign or 0x7c00
            exp <= 0 -> {
                if (exp < -10) {
                    sign
                } else {
                    val m = mant or 0x800000
                    val shift = 14 - exp
                    var half = m ushr shift
                    val rem = m and ((1 shl shift) - 1)
                    val mid = 1 shl (shift - 1)
                    if (rem > mid || (rem == mid && (half and 1) == 1)) half++
                    sign or half
                }
            }
            else -> {
                var half = (exp shl 10) or (mant ushr 13)
                val rem = mant and 0x1fff
                if (rem > 0x1000 || (rem == 0x1000 && (half and 1) == 1)) half++
                sign or half
            }
        }
    }

    /** A page's image cells: [perPage] images in a grid inside the printable area. */
    class Cell(val left: Float, val top: Float, val width: Float, val height: Float)

    /** Grid for [perPage] images on a page of [pageW] x [pageH] with [margin] and [gap]. */
    fun printGrid(perPage: Int, pageW: Float, pageH: Float, margin: Float, gap: Float): List<Cell> {
        val n = perPage.coerceIn(1, 16)
        val cols = kotlin.math.ceil(kotlin.math.sqrt(n.toDouble() * pageW / pageH)).toInt().coerceIn(1, n)
        val rows = kotlin.math.ceil(n.toDouble() / cols).toInt()
        val cw = (pageW - 2 * margin - gap * (cols - 1)) / cols
        val ch = (pageH - 2 * margin - gap * (rows - 1)) / rows
        return List(n) { i ->
            Cell(margin + (i % cols) * (cw + gap), margin + (i / cols) * (ch + gap), cw, ch)
        }
    }

    /**
     * Source rectangle (in image pixels) and destination rectangle (in the
     * cell) for drawing an image of [iw] x [ih] into [cell]: fill crops to
     * cover the cell, fit letterboxes inside it. [captionH] is reserved at the cell bottom.
     */
    fun place(iw: Int, ih: Int, cell: Cell, fill: Boolean, captionH: Float): Pair<FloatArray, FloatArray> {
        val availH = max(1f, cell.height - captionH)
        val ratioImage = iw.toFloat() / ih
        val ratioCell = cell.width / availH
        if (fill) {
            val src = if (ratioImage > ratioCell) {
                val w = ih * ratioCell
                floatArrayOf((iw - w) / 2, 0f, (iw + w) / 2, ih.toFloat())
            } else {
                val h = iw / ratioCell
                floatArrayOf(0f, (ih - h) / 2, iw.toFloat(), (ih + h) / 2)
            }
            return src to floatArrayOf(cell.left, cell.top, cell.left + cell.width, cell.top + availH)
        }
        val (w, h) = if (ratioImage > ratioCell) {
            cell.width to cell.width / ratioImage
        } else {
            availH * ratioImage to availH
        }
        val l = cell.left + (cell.width - w) / 2
        val t = cell.top + (availH - h) / 2
        return floatArrayOf(0f, 0f, iw.toFloat(), ih.toFloat()) to floatArrayOf(l, t, l + w, t + h)
    }

    /**
     * Face box from `android.media.FaceDetector.Face` (mid-point between the
     * eyes, eye distance), normalised to the image. The detector reports no
     * box, so this is the usual head proportion around the eyes.
     */
    fun faceRect(midX: Float, midY: Float, eyes: Float, width: Int, height: Int): FloatArray {
        val l = (midX - eyes * 1.3f) / width
        val r = (midX + eyes * 1.3f) / width
        val t = (midY - eyes * 1.4f) / height
        val b = (midY + eyes * 1.9f) / height
        return floatArrayOf(max(0f, l), max(0f, t), min(1f, r), min(1f, b))
    }
}
