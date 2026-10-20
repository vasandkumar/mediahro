package com.mediahro.mediahro.platform.storage

import com.mediahro.mediahro.pigeon.PickKindMsg

/**
 * Which system picker serves a `pickFiles` call, and how a picked file is
 * named (SYS-007, FILE-001). Pure, so the rules are unit-tested on the JVM.
 *
 * Images alone go to the Photo Picker, which works without READ_MEDIA_*.
 * Everything else, video included, goes to the documents picker: it reaches
 * any folder, SD card or USB drive and every format (MKV, ISO folders,
 * subtitles), returns the real file name and is multi-select only when
 * asked.
 */
internal object PickPolicy {
    enum class Picker { PHOTO_PICKER, DOCUMENTS }

    fun pickerFor(kinds: List<PickKindMsg>): Picker =
        if (kinds.isNotEmpty() && kinds.all { it == PickKindMsg.IMAGE }) Picker.PHOTO_PICKER else Picker.DOCUMENTS

    fun mimeTypes(kinds: List<PickKindMsg>): Array<String> {
        // Subtitles and playlists rarely carry a MIME type, so they open everything.
        if (kinds.isEmpty() ||
            kinds.any { it == PickKindMsg.ANY || it == PickKindMsg.SUBTITLE || it == PickKindMsg.PLAYLIST }
        ) {
            return arrayOf("*/*")
        }
        return kinds.flatMap {
            when (it) {
                // Providers often type MKV, M2TS and others as octet-stream.
                PickKindMsg.VIDEO -> listOf("video/*", "application/x-matroska", "application/octet-stream")
                PickKindMsg.AUDIO -> listOf("audio/*", "application/ogg", "application/octet-stream")
                PickKindMsg.IMAGE -> listOf("image/*")
                else -> listOf("*/*")
            }
        }.distinct().toTypedArray()
    }

    /**
     * The best user-facing name: the first candidate that is a real name
     * (not blank, not a bare media id), else the URI's last segment if it
     * reads like a file name, else `<id>.<extension for mime>`.
     */
    fun displayName(
        candidates: List<String?>,
        lastSegment: String?,
        mimeType: String?,
        extensionFor: (String) -> String?,
    ): String {
        candidates.firstOrNull { isRealName(it) }?.let { return it!!.trim() }
        val segment = lastSegment?.substringAfterLast('/')
        if (isRealName(segment)) return segment!!
        val base = segment?.takeIf { it.isNotBlank() } ?: "file"
        val ext = mimeType?.let(extensionFor)
        return if (ext.isNullOrBlank()) base else "$base.$ext"
    }

    private fun isRealName(name: String?): Boolean =
        !name.isNullOrBlank() && !name.trim().all { it.isDigit() }
}
