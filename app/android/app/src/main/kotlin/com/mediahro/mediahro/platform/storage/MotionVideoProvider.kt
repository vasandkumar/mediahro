package com.mediahro.mediahro.platform.storage

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.net.Uri
import java.io.FileInputStream
import java.io.FileNotFoundException

/**
 * The URI of a Motion Photo's video component served in place (IMG-016). The
 * video is never copied out of the photo: [MotionVideoProvider] opens the
 * original MediaStore file and hands out the tail of it as an
 * `AssetFileDescriptor` (offset and length of the same descriptor), so no
 * plaintext copy of the video ever sits in the cache (PR #104 review M4).
 * Pure string handling, unit-tested.
 */
internal object MotionVideoUri {
    /**
     * Only photos of the MediaStore images collection may be served
     * (`content://media/<volume>/images/media/<id>`), not every
     * `content://media/` URI.
     */
    private val servable = Regex("""content://media/[A-Za-z0-9_\-]+/images/media/\d+""")

    fun isServable(assetId: String): Boolean = servable.matches(assetId)

    /** `content://<authority>/<percent-encoded asset id>`; the id is one path segment. */
    fun build(authority: String, assetId: String): String {
        require(isServable(assetId)) { "not a MediaStore image" }
        return "content://$authority/" + percentEncode(assetId)
    }

    /**
     * The asset id for a path segment **as Android hands it over**: `Uri.lastPathSegment`
     * has already percent-decoded it once, so it is checked as it is and never
     * decoded again. Null if it is not a servable one.
     */
    fun assetOf(decodedSegment: String?): String? = decodedSegment?.takeIf(::isServable)

    /** Percent-encodes everything but unreserved characters (RFC 3986), so a space is %20 and not +. */
    fun percentEncode(text: String): String {
        val out = StringBuilder()
        for (b in text.toByteArray(Charsets.UTF_8)) {
            val c = b.toInt() and 0xff
            if (c.toChar().isLetterOrDigit() && c < 0x80 || c.toChar() in "-._~") {
                out.append(c.toChar())
            } else {
                out.append('%').append("0123456789ABCDEF"[c shr 4]).append("0123456789ABCDEF"[c and 15])
            }
        }
        return out.toString()
    }
}

/**
 * Serves the video part of a Motion Photo from the photo file itself (see
 * [MotionVideoUri]). Not exported: only this app reads it, through
 * `ContentResolver.openAssetFileDescriptor` (the Android media APIs do).
 */
class MotionVideoProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "video/mp4"

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        if (mode != "r") throw FileNotFoundException("read only")
        val asset = MotionVideoUri.assetOf(uri.lastPathSegment) ?: throw FileNotFoundException("not a Motion Photo")
        val pfd = context!!.contentResolver.openFileDescriptor(Uri.parse(asset), "r")
            ?: throw FileNotFoundException(asset)
        try {
            // Scan a duplicate: closing the stream must not close the descriptor handed out below.
            val range = pfd.dup().use { copy ->
                FileInputStream(copy.fileDescriptor).use { MotionPhoto.videoRange(it.channel) }
            } ?: throw FileNotFoundException("no video in $asset")
            return AssetFileDescriptor(pfd, range.first, range.last - range.first + 1)
        } catch (e: Exception) {
            pfd.close()
            throw if (e is FileNotFoundException) e else FileNotFoundException(e.message)
        }
    }

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0
}
