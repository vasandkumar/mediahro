package com.mediahro.mediahro.platform.storage

import android.Manifest
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PhotoAccessMsg
import com.mediahro.mediahro.pigeon.PhotoAssetMsg
import com.mediahro.mediahro.pigeon.PhotoLibraryHostApi
import com.mediahro.mediahro.platform.ActivityHost
import java.io.File
import java.io.FileInputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * PhotoLibraryFacade on Android (IMG-016, SYS-007): MediaStore images and
 * videos with `READ_MEDIA_VISUAL_USER_SELECTED` partial access (limited),
 * the system re-selection prompt, and Motion Photo video extraction.
 */
class PhotoLibraryModule(private val context: Context, private val host: ActivityHost) : PhotoLibraryHostApi {
    private val resolver: ContentResolver = context.contentResolver
    private val prefs = context.getSharedPreferences("mediahro.photos", Context.MODE_PRIVATE)

    private val fullPermissions: List<String> =
        if (Build.VERSION.SDK_INT >= 33) {
            listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
        } else {
            listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    override fun access(): PhotoAccessMsg = when {
        fullPermissions.all(host::granted) -> PhotoAccessMsg.FULL
        Build.VERSION.SDK_INT >= 34 && host.granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) ->
            PhotoAccessMsg.LIMITED
        prefs.getBoolean(KEY_ASKED, false) -> PhotoAccessMsg.DENIED
        else -> PhotoAccessMsg.NOT_DETERMINED
    }

    override suspend fun requestAccess(): PhotoAccessMsg {
        val request = fullPermissions.toMutableList()
        if (Build.VERSION.SDK_INT >= 34) request += Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        // EXIF GPS for the photo map (IMG map); not device location.
        request += Manifest.permission.ACCESS_MEDIA_LOCATION
        host.request(request)
        prefs.edit().putBoolean(KEY_ASKED, true).apply()
        return access()
    }

    override suspend fun manageLimitedSelection() {
        // Android 14+: asking again while partially granted shows the
        // system's re-selection sheet.
        if (Build.VERSION.SDK_INT < 34) return
        val request = fullPermissions + Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        host.launch(
            androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions(),
            request.toTypedArray(),
        )
    }

    override suspend fun assetsPage(offset: Long, limit: Long): List<PhotoAssetMsg> = withContext(Dispatchers.IO) {
        val image = MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE
        val video = MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
        val query = Bundle().apply {
            putString(
                ContentResolver.QUERY_ARG_SQL_SELECTION,
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN ($image,$video)",
            )
            putStringArray(
                ContentResolver.QUERY_ARG_SORT_COLUMNS,
                arrayOf(MediaStore.MediaColumns.DATE_TAKEN, MediaStore.MediaColumns.DATE_ADDED),
            )
            putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset.toInt())
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit.toInt())
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.VOLUME_NAME,
        )
        val out = ArrayList<PhotoAssetMsg>()
        resolver.query(MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL), projection, query, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val isVideo = c.getInt(1) == video
                val volume = c.getString(7) ?: MediaStore.VOLUME_EXTERNAL
                val collection = if (isVideo) {
                    MediaStore.Video.Media.getContentUri(volume)
                } else {
                    MediaStore.Images.Media.getContentUri(volume)
                }
                val created = if (!c.isNull(2) && c.getLong(2) > 0) c.getLong(2) else c.getLong(3) * 1000
                val name = c.getString(6).orEmpty()
                out += PhotoAssetMsg(
                    id = ContentUris.withAppendedId(collection, id).toString(),
                    uri = ContentUris.withAppendedId(collection, id).toString(),
                    createdMs = created,
                    width = if (c.isNull(4)) null else c.getLong(4),
                    height = if (c.isNull(5)) null else c.getLong(5),
                    isVideo = isVideo,
                    isLive = !isVideo && MotionPhoto.looksLikeMotionPhoto(name),
                )
            }
        }
        out
    }

    override suspend fun pairedVideo(assetId: String): String? = withContext(Dispatchers.IO) {
        val uri = Uri.parse(assetId)
        val pfd = try {
            resolver.openFileDescriptor(uri, "r")
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message)
        } ?: return@withContext null
        pfd.use {
            FileInputStream(it.fileDescriptor).use { input ->
                val range = MotionPhoto.videoRange(input.channel) ?: return@withContext null
                val dir = File(context.cacheDir, "motion").apply { mkdirs() }
                val out = File(dir, "${uri.lastPathSegment}.mp4")
                if (!out.exists() || out.length() != range.last - range.first + 1) {
                    out.outputStream().channel.use { dest ->
                        input.channel.transferTo(range.first, range.last - range.first + 1, dest)
                    }
                }
                Uri.fromFile(out).toString()
            }
        }
    }

    companion object {
        private const val KEY_ASKED = "asked"
    }
}
