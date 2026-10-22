package com.mediahro.mediahro.diagnostics

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.util.Log

/**
 * Debug and profile builds only (src/diagnostics): at start the log says which media permissions
 * the app holds and how many pictures, videos and audio files the MediaStore shows it per folder,
 * so "my screenshots are missing" can be told apart from a permission state or a filtered query
 * (Android 14 limited access shows only the selected photos). Nothing leaves the device.
 */
object StartupDiagnostics {
    private const val TAG = "MediahroDiag"

    @JvmStatic
    fun run(context: Context) {
        Thread({ log(context) }, "mediahro-diagnostics").start()
    }

    private fun log(context: Context) {
        try {
            val permissions = listOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                Manifest.permission.ACCESS_MEDIA_LOCATION,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            )
            val state = permissions.joinToString(" ") {
                val short = it.substringAfterLast('.')
                "$short=" + if (context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED) "yes" else "no"
            }
            Log.i(TAG, "sdk=${Build.VERSION.SDK_INT} $state")
            val byFolder = sortedMapOf<String, IntArray>()
            val totals = IntArray(3)
            context.contentResolver.query(
                MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL),
                arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE, MediaStore.MediaColumns.RELATIVE_PATH),
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (" +
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE}," +
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}," +
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO})",
                null,
                null,
            )?.use { c ->
                while (c.moveToNext()) {
                    val slot = when (c.getInt(0)) {
                        MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE -> 0
                        MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO -> 1
                        else -> 2
                    }
                    totals[slot]++
                    byFolder.getOrPut(c.getString(1).orEmpty()) { IntArray(3) }[slot]++
                }
            }
            Log.i(TAG, "visible images=${totals[0]} videos=${totals[1]} audio=${totals[2]} folders=${byFolder.size}")
            // The biggest folders first; the screenshots folders are named so they can be checked.
            byFolder.entries.sortedByDescending { it.value.sum() }.take(MAX_FOLDERS).forEach { (path, n) ->
                Log.i(TAG, "folder '$path' images=${n[0]} videos=${n[1]} audio=${n[2]}")
            }
            byFolder.filterKeys { it.contains("Screenshot", ignoreCase = true) }.forEach { (path, n) ->
                Log.i(TAG, "screenshots folder '$path' images=${n[0]} videos=${n[1]}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "diagnostics failed: $e")
        }
    }

    private const val MAX_FOLDERS = 15
}
