package com.mediahro.mediahro.platform.imaging

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import androidx.annotation.RequiresApi
import com.mediahro.mediahro.pigeon.PlatformImageMsg
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Ultra HDR (gain map) stills as RGBA F16, linear extended sRGB (IMG-002). */
internal class HdrBitmaps private constructor(
    private val width: Int,
    private val height: Int,
    private val pixels: ByteArray,
) {
    fun toMsg(frames: Int): PlatformImageMsg =
        PlatformImageMsg(width.toLong(), height.toLong(), pixels, true, frames.toLong(), true)

    companion object {
        /**
         * Applies [base]'s gain map at full HDR weight. The base is the SDR
         * rendition (sRGB); the result is linear with 1.0 at SDR white.
         */
        @RequiresApi(34)
        fun withGainMap(base: Bitmap): HdrBitmaps {
            check(Build.VERSION.SDK_INT >= 34)
            val gm = base.gainmap!!
            val w = base.width
            val h = base.height
            val map = gm.gainmapContents.copy(Bitmap.Config.ARGB_8888, false)
            val mapped = if (map.width == w && map.height == h) map else Bitmap.createScaledBitmap(map, w, h, true)
            val min = gm.ratioMin
            val max = gm.ratioMax
            val gamma = gm.gamma
            val epsSdr = gm.epsilonSdr
            val epsHdr = gm.epsilonHdr
            val params = Array(3) { c ->
                ImagingMath.GainParams(min[c], max[c], gamma[c], epsSdr[c], epsHdr[c])
            }
            val src = IntArray(w * h)
            val gain = IntArray(w * h)
            base.copy(Bitmap.Config.ARGB_8888, false).getPixels(src, 0, w, 0, 0, w, h)
            mapped.getPixels(gain, 0, w, 0, 0, w, h)
            val bytes = ByteBuffer.allocate(w * h * 8).order(ByteOrder.LITTLE_ENDIAN)
            val out = bytes.asShortBuffer()
            for (i in src.indices) {
                val p = src[i]
                val g = gain[i]
                // A single-channel map has R == G == B; a 3-channel map uses each.
                val r = ImagingMath.applyGain(ImagingMath.srgbToLinear(Color.red(p) / 255f), Color.red(g) / 255f, params[0])
                val gr = ImagingMath.applyGain(ImagingMath.srgbToLinear(Color.green(p) / 255f), Color.green(g) / 255f, params[1])
                val b = ImagingMath.applyGain(ImagingMath.srgbToLinear(Color.blue(p) / 255f), Color.blue(g) / 255f, params[2])
                out.put(ImagingMath.halfBits(r).toShort())
                out.put(ImagingMath.halfBits(gr).toShort())
                out.put(ImagingMath.halfBits(b).toShort())
                out.put(ImagingMath.halfBits(Color.alpha(p) / 255f).toShort())
            }
            return HdrBitmaps(w, h, bytes.array())
        }
    }
}
