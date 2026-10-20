package com.mediahro.mediahro.platform.imaging

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.graphics.Rect
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PlatformImageMsg
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Pixels in, pixels out through the platform decoders (IMG-001/002/003). */
internal class ImageCodec(private val context: Context) {
    private val resolver: ContentResolver = context.contentResolver

    class Request(
        val uri: Uri,
        val maxEdge: Int?,
        /** left, top, right, bottom in full-image pixels, or null. */
        val region: DoubleArray?,
        val frame: Int,
        val keepHdr: Boolean,
    )

    fun decode(r: Request): PlatformImageMsg {
        try {
            return if (r.frame > 0) decodeSequenceFrame(r) else decodeFirst(r)
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message ?: "Image not found", r.uri.toString())
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message ?: "No access to the image", r.uri.toString())
        } catch (e: ImageDecoder.DecodeException) {
            throw FlutterError("decodeFailed", e.message ?: "The image could not be decoded", r.uri.toString())
        } catch (e: IOException) {
            throw FlutterError("decodeFailed", e.message ?: "The image could not be read", r.uri.toString())
        }
    }

    private fun decodeFirst(r: Request): PlatformImageMsg {
        var frames = 1
        var hdrSource = false
        val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, r.uri)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isUnpremultipliedRequired = true
            val full = info.size
            val (tw, th) = ImagingMath.targetSize(full.width, full.height, r.maxEdge)
            if (tw != full.width || th != full.height) decoder.setTargetSize(tw, th)
            r.region?.let { g ->
                val c = ImagingMath.scaledRegion(g[0], g[1], g[2], g[3], full.width, full.height, tw, th)
                decoder.crop = Rect(c[0], c[1], c[2], c[3])
            }
            val cs = info.colorSpace
            hdrSource = cs == ColorSpace.get(ColorSpace.Named.BT2020_PQ) ||
                cs == ColorSpace.get(ColorSpace.Named.BT2020_HLG)
            // SDR rendition for keepHdr false; extended-range sRGB keeps PQ/HLG highlights.
            decoder.setTargetColorSpace(
                ColorSpace.get(if (r.keepHdr) ColorSpace.Named.EXTENDED_SRGB else ColorSpace.Named.SRGB),
            )
            if (info.mimeType.contains("heif") || info.mimeType.contains("heic")) frames = imageCount(r.uri)
        }
        val gain = Build.VERSION.SDK_INT >= 34 && bitmap.hasGainmap()
        val hdr = hdrSource || gain
        if (r.keepHdr && gain) return HdrBitmaps.withGainMap(bitmap).toMsg(frames)
        if (r.keepHdr && hdr) return f16Msg(bitmap, frames, true)
        return rgbaMsg(bitmap, frames, hdr)
    }

    /** HEIF image sequences: the platform retriever reads frame [Request.frame]. */
    private fun decodeSequenceFrame(r: Request): PlatformImageMsg {
        val count = imageCount(r.uri)
        if (r.frame >= count) throw FlutterError("notFound", "No frame ${r.frame}", r.uri.toString())
        val mmr = MediaMetadataRetriever()
        try {
            mmr.setDataSource(context, r.uri)
            val raw = mmr.getImageAtIndex(r.frame)
                ?: throw FlutterError("unsupported", "This image has no frame ${r.frame}", r.uri.toString())
            val (tw, th) = ImagingMath.targetSize(raw.width, raw.height, r.maxEdge)
            var out = if (tw != raw.width) Bitmap.createScaledBitmap(raw, tw, th, true) else raw
            r.region?.let { g ->
                val c = ImagingMath.scaledRegion(g[0], g[1], g[2], g[3], raw.width, raw.height, out.width, out.height)
                out = Bitmap.createBitmap(out, c[0], c[1], c[2] - c[0], c[3] - c[1])
            }
            return rgbaMsg(out, count, false)
        } finally {
            mmr.release()
        }
    }

    /** Frames of a HEIF sequence (1 for a still). */
    fun imageCount(uri: Uri): Int {
        val mmr = MediaMetadataRetriever()
        return try {
            mmr.setDataSource(context, uri)
            mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_IMAGE_COUNT)?.toIntOrNull()?.coerceAtLeast(1) ?: 1
        } catch (e: RuntimeException) {
            1
        } finally {
            mmr.release()
        }
    }

    /** The OS thumbnail cache (MediaStore) entry, or null when there is none. */
    fun thumbnail(uri: Uri, size: Int): PlatformImageMsg? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        val bmp = try {
            resolver.loadThumbnail(uri, android.util.Size(size, size), null)
        } catch (e: IOException) {
            return null
        } catch (e: RuntimeException) {
            return null
        }
        return rgbaMsg(bmp, 1, false)
    }

    companion object {
        /** Packed RGBA8888, straight alpha when the decoder gave it so. */
        fun rgbaMsg(source: Bitmap, frames: Int, hdr: Boolean): PlatformImageMsg {
            val b = if (source.config == Bitmap.Config.ARGB_8888) source else source.copy(Bitmap.Config.ARGB_8888, false)
            return PlatformImageMsg(b.width.toLong(), b.height.toLong(), packed(b, 4), false, frames.toLong(), hdr)
        }

        /** Packed RGBA F16 (native byte order, little endian on every Android ABI we ship). */
        fun f16Msg(source: Bitmap, frames: Int, hdr: Boolean): PlatformImageMsg {
            val b = if (source.config == Bitmap.Config.RGBA_F16) source else source.copy(Bitmap.Config.RGBA_F16, false)
            return PlatformImageMsg(b.width.toLong(), b.height.toLong(), packed(b, 8), true, frames.toLong(), hdr)
        }

        /** Rows without padding. */
        private fun packed(b: Bitmap, bytesPerPixel: Int): ByteArray {
            val rowBytes = b.width * bytesPerPixel
            val buf = ByteBuffer.allocate(b.rowBytes * b.height).order(ByteOrder.nativeOrder())
            b.copyPixelsToBuffer(buf)
            val raw = buf.array()
            if (b.rowBytes == rowBytes) return raw
            val out = ByteArray(rowBytes * b.height)
            for (y in 0 until b.height) System.arraycopy(raw, y * b.rowBytes, out, y * rowBytes, rowBytes)
            return out
        }

        /** [msg] as an ARGB_8888 / RGBA_F16 bitmap. */
        fun toBitmap(msg: PlatformImageMsg): Bitmap {
            val config = if (msg.f16) Bitmap.Config.RGBA_F16 else Bitmap.Config.ARGB_8888
            val bpp = if (msg.f16) 8 else 4
            val w = msg.width.toInt()
            val h = msg.height.toInt()
            if (w <= 0 || h <= 0 || msg.pixels.size < w * h * bpp) {
                throw FlutterError("badImage", "Pixel buffer does not match ${w}x$h")
            }
            val b = Bitmap.createBitmap(w, h, config)
            b.copyPixelsFromBuffer(ByteBuffer.wrap(msg.pixels, 0, w * h * bpp).order(ByteOrder.nativeOrder()))
            return b
        }
    }
}
