package com.mediahro.mediahro.platform.imaging

import android.app.WallpaperManager
import android.content.ClipData
import android.content.ContentResolver
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.hardware.display.DisplayManager
import android.media.FaceDetector
import android.media.MediaCodecList
import android.net.Uri
import android.os.Build
import android.print.PrintAttributes
import android.print.PrintJobInfo
import android.print.PrintManager
import android.provider.MediaStore
import android.view.Display
import androidx.core.content.FileProvider
import androidx.heifwriter.HeifWriter
import com.mediahro.mediahro.pigeon.DecodeRequestMsg
import com.mediahro.mediahro.pigeon.DetectedFaceMsg
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.ImagingHostApi
import com.mediahro.mediahro.pigeon.ImagingSupportMsg
import com.mediahro.mediahro.pigeon.PlatformImageMsg
import com.mediahro.mediahro.pigeon.PrintLayoutMsg
import com.mediahro.mediahro.pigeon.WallpaperTargetMsg
import com.mediahro.mediahro.platform.ActivityHost
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * ImagingFacade on Android (ADR-037): `ImageDecoder` (with subsample, crop,
 * HEIF sequences, Ultra HDR gain maps and PQ/HLG), the MediaStore thumbnail
 * cache, `HeifWriter` for HEIC, `WallpaperManager`, the print framework,
 * the clipboard, `android.media.FaceDetector` (on-device, no ML Kit,
 * ADR-034) and `noBackupFilesDir` for the vault (ADR-008).
 */
class ImagingModule(private val context: Context, private val host: ActivityHost) : ImagingHostApi {
    private val resolver: ContentResolver = context.contentResolver
    private val codec = ImageCodec(context)
    private var previousColorMode: Int? = null

    // --- capabilities ---------------------------------------------------

    override fun support(): ImagingSupportMsg {
        val decodable = buildSet {
            if (hasDecoder("image/vnd.android.heic", "video/hevc")) {
                add("heic")
                add("heif")
            }
            if (Build.VERSION.SDK_INT >= 31 && hasDecoder("video/av01")) add("avif")
        }
        val encodable = buildSet {
            if (hasEncoder("image/vnd.android.heic", "video/hevc")) add("heic")
        }
        val wm = WallpaperManager.getInstance(context)
        val wallpaper = if (wm.isWallpaperSupported && wm.isSetWallpaperAllowed) {
            listOf(WallpaperTargetMsg.HOME, WallpaperTargetMsg.LOCK, WallpaperTargetMsg.BOTH)
        } else {
            emptyList()
        }
        return ImagingSupportMsg(
            decodable.toList(),
            encodable.toList(),
            displayIsHdr(),
            wallpaper,
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_PRINTING),
            true,
        )
    }

    private fun hasDecoder(vararg mimes: String) = hasCodec(false, mimes)

    private fun hasEncoder(vararg mimes: String) = hasCodec(true, mimes)

    private fun hasCodec(encoder: Boolean, mimes: Array<out String>): Boolean =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            info.isEncoder == encoder && info.supportedTypes.any { t -> mimes.any { it.equals(t, ignoreCase = true) } }
        }

    @Suppress("DEPRECATION")
    private fun displayIsHdr(): Boolean {
        val display: Display? = host.activity?.display
            ?: (context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager).getDisplay(Display.DEFAULT_DISPLAY)
        return display?.isHdr == true
    }

    // --- decode ---------------------------------------------------------

    override suspend fun decode(request: DecodeRequestMsg): PlatformImageMsg = withContext(Dispatchers.IO) {
        val r = request.region
        codec.decode(
            ImageCodec.Request(
                uri = Uri.parse(request.uri),
                maxEdge = request.maxEdge?.toInt(),
                region = r?.let { doubleArrayOf(it.left, it.top, it.right, it.bottom) },
                frame = request.frame.toInt(),
                keepHdr = request.keepHdr,
            ),
        )
    }

    override suspend fun thumbnail(uri: String, size: Long): PlatformImageMsg? = withContext(Dispatchers.IO) {
        codec.thumbnail(Uri.parse(uri), size.toInt().coerceIn(16, 4096))
    }

    // --- encode ---------------------------------------------------------

    override suspend fun encode(image: PlatformImageMsg, format: String, quality: Long, exif: ByteArray?): ByteArray =
        withContext(Dispatchers.IO) {
            if (format != "heic") throw FlutterError("unsupported", "Android cannot encode $format")
            if (!hasEncoder("image/vnd.android.heic", "video/hevc")) {
                throw FlutterError("unsupported", "This device has no HEIC encoder")
            }
            val src = ImageCodec.toBitmap(image)
            // HeifWriter takes 8-bit ARGB bitmaps.
            val bmp = if (src.config == Bitmap.Config.ARGB_8888) src else src.copy(Bitmap.Config.ARGB_8888, false)
            val out = File.createTempFile("heif", ".heic", context.cacheDir)
            try {
                HeifWriter.Builder(out.absolutePath, bmp.width, bmp.height, HeifWriter.INPUT_MODE_BITMAP)
                    .setQuality(quality.toInt().coerceIn(1, 100))
                    .setMaxImages(1)
                    .setPrimaryIndex(0)
                    .build().use { w ->
                        w.start()
                        w.addBitmap(bmp)
                        if (exif != null && exif.isNotEmpty()) w.addExifData(0, withExifHeader(exif), 0, withExifHeader(exif).size)
                        w.stop(ENCODE_TIMEOUT_MS)
                    }
                out.readBytes()
            } catch (e: IOException) {
                throw FlutterError("encodeFailed", e.message ?: "HEIC encoding failed")
            } finally {
                out.delete()
            }
        }

    // --- HDR view -------------------------------------------------------

    override suspend fun openHdrView(uri: String): String? = withContext(Dispatchers.Main) {
        val activity = host.activity ?: return@withContext null
        if (!displayIsHdr()) return@withContext null
        try {
            resolver.openAssetFileDescriptor(Uri.parse(uri), "r")?.close() ?: return@withContext null
        } catch (e: FileNotFoundException) {
            return@withContext null
        } catch (e: SecurityException) {
            return@withContext null
        }
        if (previousColorMode == null) previousColorMode = activity.window.colorMode
        activity.window.colorMode = ActivityInfo.COLOR_MODE_HDR
        HdrImageViewFactory.VIEW_TYPE
    }

    override fun closeHdrView() {
        val activity = host.activity ?: return
        previousColorMode?.let { activity.window.colorMode = it }
        previousColorMode = null
    }

    // --- wallpaper, print, clipboard -----------------------------------

    override suspend fun setWallpaper(uri: String, target: WallpaperTargetMsg) {
        withContext(Dispatchers.IO) {
            val flags = when (target) {
                WallpaperTargetMsg.HOME -> WallpaperManager.FLAG_SYSTEM
                WallpaperTargetMsg.LOCK -> WallpaperManager.FLAG_LOCK
                WallpaperTargetMsg.BOTH -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
            }
            val wm = WallpaperManager.getInstance(context)
            if (!wm.isWallpaperSupported || !wm.isSetWallpaperAllowed) {
                throw FlutterError("unsupported", "Setting the wallpaper is not allowed on this device")
            }
            try {
                (resolver.openInputStream(Uri.parse(uri)) ?: throw FileNotFoundException(uri)).use {
                    wm.setStream(it, null, true, flags)
                }
            } catch (e: FileNotFoundException) {
                throw FlutterError("notFound", e.message ?: "Image not found", uri)
            } catch (e: SecurityException) {
                throw FlutterError("permissionDenied", e.message ?: "No access", uri)
            }
        }
    }

    override suspend fun printImages(images: List<String>, layout: PrintLayoutMsg): Boolean {
        if (images.isEmpty()) return false
        val activity = host.requireActivity()
        val job = withContext(Dispatchers.Main) {
            val pm = activity.getSystemService(Context.PRINT_SERVICE) as PrintManager
            val adapter = ImagePrintAdapter(
                activity,
                images.map(Uri::parse),
                layout.perPage.toInt(),
                layout.fill,
                layout.captions,
            )
            val attrs = PrintAttributes.Builder()
                .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                .build()
            pm.print("Mediahro", adapter, attrs)
        }
        // The preview is not a print: wait until the job is submitted or dropped.
        val deadline = System.currentTimeMillis() + PRINT_WAIT_MS
        while (System.currentTimeMillis() < deadline) {
            when (job.info.state) {
                PrintJobInfo.STATE_QUEUED, PrintJobInfo.STATE_STARTED, PrintJobInfo.STATE_BLOCKED,
                PrintJobInfo.STATE_COMPLETED,
                -> return true
                PrintJobInfo.STATE_CANCELED, PrintJobInfo.STATE_FAILED -> return false
            }
            delay(PRINT_POLL_MS)
        }
        return false
    }

    override suspend fun copyImage(uri: String) {
        val clip = withContext(Dispatchers.IO) {
            val u = Uri.parse(uri)
            val shared = sharable(u)
            ClipData.newUri(resolver, "image", shared)
        }
        withContext(Dispatchers.Main) {
            (context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(clip)
        }
    }

    /** MediaStore URIs are readable by other apps with their own media access; anything else is copied to a FileProvider URI. */
    private fun sharable(u: Uri): Uri {
        if (u.scheme == ContentResolver.SCHEME_CONTENT && u.authority == MediaStore.AUTHORITY) return u
        val dir = File(context.cacheDir, "imaging-clip").apply { deleteRecursively(); mkdirs() }
        val name = (u.lastPathSegment ?: "image").substringAfterLast('/').replace(Regex("[^A-Za-z0-9._-]"), "_")
        val copy = File(dir, name.ifEmpty { "image" })
        try {
            (resolver.openInputStream(u) ?: throw FileNotFoundException(u.toString())).use { input ->
                copy.outputStream().use { input.copyTo(it) }
            }
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message ?: "Image not found", u.toString())
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message ?: "No access", u.toString())
        }
        return FileProvider.getUriForFile(context, "${context.packageName}.files", copy)
    }

    // --- faces, vault ---------------------------------------------------

    override suspend fun detectFaces(uri: String): List<DetectedFaceMsg> = withContext(Dispatchers.IO) {
        val u = Uri.parse(uri)
        val decoded = try {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, u)) { d, info, _ ->
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val (w, h) = ImagingMath.targetSize(info.size.width, info.size.height, FACE_EDGE)
                d.setTargetSize(w, h)
            }
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message ?: "Image not found", uri)
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message ?: "No access", uri)
        } catch (e: IOException) {
            throw FlutterError("decodeFailed", e.message ?: "The image could not be decoded", uri)
        }
        // FaceDetector wants RGB_565 with an even width.
        val w = decoded.width and 1.inv()
        val h = decoded.height
        if (w < 2 || h < 2) return@withContext emptyList()
        val b565 = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565)
        Canvas(b565).drawBitmap(decoded, 0f, 0f, null)
        val found = arrayOfNulls<FaceDetector.Face>(MAX_FACES)
        val n = FaceDetector(w, h, MAX_FACES).findFaces(b565, found)
        found.take(n).filterNotNull()
            .filter { it.confidence() >= FACE_CONFIDENCE }
            .map {
                val mid = android.graphics.PointF()
                it.getMidPoint(mid)
                val r = ImagingMath.faceRect(mid.x, mid.y, it.eyesDistance(), w, h)
                DetectedFaceMsg(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble())
            }
    }

    override fun noBackupDirectory(name: String): String {
        if (!NAME.matches(name)) throw FlutterError("badName", "Invalid directory name", name)
        val dir = File(context.noBackupFilesDir, name)
        if (!dir.isDirectory && !dir.mkdirs()) throw FlutterError("ioError", "Cannot create $name", name)
        return Uri.fromFile(dir).toString()
    }

    companion object {
        private val NAME = Regex("[A-Za-z0-9._-]{1,64}")
        private const val ENCODE_TIMEOUT_MS = 30_000L
        private const val PRINT_WAIT_MS = 10 * 60_000L
        private const val PRINT_POLL_MS = 400L
        private const val MAX_FACES = 32
        private const val FACE_EDGE = 1024
        private const val FACE_CONFIDENCE = 0.4f

        private val EXIF_HEADER = byteArrayOf('E'.code.toByte(), 'x'.code.toByte(), 'i'.code.toByte(), 'f'.code.toByte(), 0, 0)

        /** HeifWriter wants the payload to start with the Exif APP1 identifier. */
        fun withExifHeader(exif: ByteArray): ByteArray =
            if (exif.size >= 6 && exif.copyOfRange(0, 6).contentEquals(EXIF_HEADER)) exif else EXIF_HEADER + exif
    }
}
