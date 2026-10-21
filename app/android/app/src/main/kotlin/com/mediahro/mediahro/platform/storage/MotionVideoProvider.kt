package com.mediahro.mediahro.platform.storage

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.net.Uri
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.net.URLDecoder
import java.net.URLEncoder

/**
 * The URI of a Motion Photo's video component served in place (IMG-016). The
 * video is never copied out of the photo: [MotionVideoProvider] opens the
 * original MediaStore file and hands out the tail of it as an
 * `AssetFileDescriptor` (offset and length of the same descriptor), so no
 * plaintext copy of the video ever sits in the cache (PR #104 review M4).
 * Pure string handling, unit-tested.
 */
internal object MotionVideoUri {
    /** Only MediaStore images may be served; anything else is refused. */
    private const val MEDIA_PREFIX = "content://media/"

    fun isServable(assetId: String): Boolean = assetId.startsWith(MEDIA_PREFIX) && assetId.length > MEDIA_PREFIX.length

    /** `content://<authority>/<percent-encoded asset id>`. */
    fun build(authority: String, assetId: String): String {
        require(isServable(assetId)) { "not a MediaStore asset" }
        return "content://$authority/" + URLEncoder.encode(assetId, "UTF-8")
    }

    /** The asset id behind an encoded path segment, or null if it is not a servable one. */
    fun assetOf(segment: String?): String? {
        if (segment.isNullOrEmpty()) return null
        val decoded = try {
            URLDecoder.decode(segment, "UTF-8")
        } catch (e: IllegalArgumentException) {
            return null
        }
        return decoded.takeIf(::isServable)
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
