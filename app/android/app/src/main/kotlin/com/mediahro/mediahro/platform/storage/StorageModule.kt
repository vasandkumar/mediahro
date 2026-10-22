package com.mediahro.mediahro.platform.storage

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.mediahro.mediahro.pigeon.DocumentEntryMsg
import com.mediahro.mediahro.pigeon.DocumentModeMsg
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.FolderGrantMsg
import com.mediahro.mediahro.pigeon.MediaPermissionMsg
import com.mediahro.mediahro.pigeon.MediaStoreEntryMsg
import com.mediahro.mediahro.pigeon.PickKindMsg
import com.mediahro.mediahro.pigeon.PickedFileMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.StorageChangeMsg
import com.mediahro.mediahro.pigeon.StorageChangesStreamHandler
import com.mediahro.mediahro.pigeon.StorageHostApi
import com.mediahro.mediahro.pigeon.TrashResultMsg
import com.mediahro.mediahro.platform.ActivityHost
import java.io.File
import java.io.FileNotFoundException
import java.io.OutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * StorageFacade on Android (SYS-007, LIB-002, LIB-003, FILE-002): SAF trees
 * with persisted grants, MediaStore queries and observers, the Photo Picker
 * for image/video picks, OS trash with undo. Never MANAGE_EXTERNAL_STORAGE.
 */
class StorageModule(private val context: Context, private val host: ActivityHost) : StorageHostApi {
    private val resolver: ContentResolver = context.contentResolver
    private val grantStore = GrantStore(context)
    private val trash = TrashManager(context, host)
    private val writers = ConcurrentHashMap<Long, Pair<Uri, OutputStream>>()
    private val nextWriter = AtomicLong(1)
    private val main = Handler(Looper.getMainLooper())

    // ---- Pickers and grants.

    override suspend fun pickFiles(kinds: List<PickKindMsg>, multiple: Boolean): List<PickedFileMsg> {
        val uris: List<Uri> = when (PickPolicy.pickerFor(kinds)) {
            PickPolicy.Picker.PHOTO_PICKER -> {
                val request = PickVisualMediaRequest.Builder()
                    .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly)
                    .build()
                if (multiple) {
                    host.launch(ActivityResultContracts.PickMultipleVisualMedia(), request)
                } else {
                    listOfNotNull(host.launch(ActivityResultContracts.PickVisualMedia(), request))
                }
            }
            PickPolicy.Picker.DOCUMENTS -> {
                // OpenDocument never sets EXTRA_ALLOW_MULTIPLE; only
                // OpenMultipleDocuments does.
                val mimes = PickPolicy.mimeTypes(kinds)
                if (multiple) {
                    host.launch(ActivityResultContracts.OpenMultipleDocuments(), mimes)
                } else {
                    listOfNotNull(host.launch(ActivityResultContracts.OpenDocument(), mimes))
                }
            }
        }
        return withContext(Dispatchers.IO) {
            uris.map { uri ->
                try {
                    resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (e: SecurityException) {
                    // Not persistable (some providers); readable for this session.
                }
                val (name, size) = Documents.nameAndSize(resolver, uri)
                PickedFileMsg(uri.toString(), name, size)
            }
        }
    }

    override suspend fun pickFolder(): FolderGrantMsg? {
        val tree = host.launch(ActivityResultContracts.OpenDocumentTree(), null) ?: return null
        return withContext(Dispatchers.IO) {
            val name = try {
                Documents.stat(resolver, tree).name
            } catch (e: FlutterError) {
                tree.lastPathSegment.orEmpty()
            }
            grantStore.add(tree, name)
        }
    }

    override fun resolveGrant(grantId: String): String? = grantStore.resolve(grantId)?.toString()

    override fun grants(): List<FolderGrantMsg> = grantStore.all()

    override fun releaseGrant(grantId: String) {
        unwatch(grantId)
        grantStore.release(grantId)
    }

    // ---- Trash.

    override suspend fun moveToTrash(uris: List<String>): TrashResultMsg =
        withContext(Dispatchers.IO) { trash.trash(uris.map(Uri::parse)) }

    override suspend fun restoreFromTrash(uris: List<String>, undoToken: String?) {
        val token = undoToken ?: throw FlutterError("unsupported", "Nothing to undo")
        withContext(Dispatchers.IO) { trash.restore(token) }
    }

    // ---- Change observers (LIB-003 watch).

    private val observers = ConcurrentHashMap<String, ContentObserver>()
    private var sink: PigeonEventSink<StorageChangeMsg>? = null

    val changesHandler = object : StorageChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<StorageChangeMsg>) {
            this@StorageModule.sink = sink
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }
    }

    private val openCursors = ConcurrentHashMap<String, android.database.Cursor>()

    override fun watch(grantId: String) {
        if (observers.containsKey(grantId)) return
        val observer = object : ContentObserver(main) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                sink?.success(StorageChangeMsg(grantId, uri?.toString().orEmpty()))
            }
        }
        if (grantId == MEDIASTORE_GRANT) {
            resolver.registerContentObserver(MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL), true, observer)
        } else {
            val tree = grantStore.resolve(grantId) ?: throw FlutterError("notFound", "No grant $grantId")
            // Providers notify `document/<id>/children` of the directory that
            // changed, so watch the whole authority; an open children cursor
            // keeps file-backed providers' directory observers running.
            resolver.registerContentObserver(Uri.parse("content://${tree.authority}/"), true, observer)
            if (tree.authority == EXTERNAL_STORAGE_AUTHORITY) {
                resolver.registerContentObserver(MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL), true, observer)
            }
            try {
                resolver.query(
                    DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree)),
                    arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                    null,
                    null,
                    null,
                )?.let { openCursors[grantId] = it }
            } catch (e: Exception) {
                // Watching still works through the observers above.
            }
        }
        observers[grantId] = observer
    }

    override fun unwatch(grantId: String) {
        observers.remove(grantId)?.let(resolver::unregisterContentObserver)
        openCursors.remove(grantId)?.close()
    }

    // ---- READ_MEDIA_* (docs/07 §3.1).

    private fun permissionsFor(kind: PickKindMsg): List<String> {
        if (Build.VERSION.SDK_INT < 33) return listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        return when (kind) {
            PickKindMsg.VIDEO -> listOf(Manifest.permission.READ_MEDIA_VIDEO)
            PickKindMsg.AUDIO -> listOf(Manifest.permission.READ_MEDIA_AUDIO)
            PickKindMsg.IMAGE -> listOf(Manifest.permission.READ_MEDIA_IMAGES)
            PickKindMsg.ANY -> listOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
                Manifest.permission.READ_MEDIA_IMAGES,
            )
            PickKindMsg.SUBTITLE, PickKindMsg.PLAYLIST -> emptyList()
        }
    }

    override fun mediaPermission(kind: PickKindMsg): MediaPermissionMsg {
        val perms = permissionsFor(kind)
        if (perms.isEmpty()) return MediaPermissionMsg.NOT_APPLICABLE
        return stateOf(perms)
    }

    private fun stateOf(perms: List<String>): MediaPermissionMsg {
        val granted = perms.count(host::granted)
        if (granted == perms.size) return MediaPermissionMsg.GRANTED
        val visual = perms.any {
            it == Manifest.permission.READ_MEDIA_IMAGES || it == Manifest.permission.READ_MEDIA_VIDEO
        }
        if (Build.VERSION.SDK_INT >= 34 && visual &&
            host.granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        ) {
            return MediaPermissionMsg.LIMITED
        }
        return if (granted > 0) MediaPermissionMsg.LIMITED else MediaPermissionMsg.DENIED
    }

    override suspend fun requestMediaPermission(kind: PickKindMsg): MediaPermissionMsg {
        val perms = permissionsFor(kind)
        if (perms.isEmpty()) return MediaPermissionMsg.NOT_APPLICABLE
        val request = perms.toMutableList()
        if (Build.VERSION.SDK_INT >= 34 && kind != PickKindMsg.AUDIO) {
            request += Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        }
        host.request(request)
        return stateOf(perms)
    }

    // ---- Documents inside grants.

    override suspend fun listDocuments(directory: String): List<DocumentEntryMsg> =
        withContext(Dispatchers.IO) { Documents.list(resolver, Uri.parse(directory)) }

    override suspend fun statDocument(uri: String): DocumentEntryMsg =
        withContext(Dispatchers.IO) { Documents.stat(resolver, Uri.parse(uri)) }

    override suspend fun openDocumentFd(uri: String, mode: DocumentModeMsg): Long = withContext(Dispatchers.IO) {
        val u = Uri.parse(uri)
        val m = when (mode) {
            DocumentModeMsg.READ -> "r"
            DocumentModeMsg.WRITE -> "wt"
            DocumentModeMsg.READ_WRITE -> "rw"
        }
        val pfd: ParcelFileDescriptor = try {
            if (u.scheme == ContentResolver.SCHEME_FILE) {
                ParcelFileDescriptor.open(File(u.path ?: ""), ParcelFileDescriptor.parseMode(m))
            } else {
                resolver.openFileDescriptor(Documents.documentUri(u), m)
            }
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message)
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message)
        } ?: throw FlutterError("notFound", "No descriptor for $uri")
        pfd.detachFd().toLong()
    }

    override suspend fun createDocument(parent: String, name: String, mimeType: String?, directory: Boolean): String =
        withContext(Dispatchers.IO) {
            val p = Documents.documentUri(Uri.parse(parent))
            val mime = if (directory) {
                DocumentsContract.Document.MIME_TYPE_DIR
            } else {
                mimeType ?: mimeOf(name)
            }
            Documents.mutate(p) { DocumentsContract.createDocument(resolver, p, mime, name) }.toString()
        }

    override suspend fun renameDocument(uri: String, newName: String): String = withContext(Dispatchers.IO) {
        val u = Uri.parse(uri)
        // Some providers rename in place and return null: the URI is unchanged.
        Documents.mutate(u) { DocumentsContract.renameDocument(resolver, u, newName) ?: u }.toString()
    }

    override suspend fun moveDocument(uri: String, fromParent: String, toParent: String): String =
        withContext(Dispatchers.IO) {
            val u = Uri.parse(uri)
            Documents.mutate(u) {
                DocumentsContract.moveDocument(
                    resolver,
                    u,
                    Documents.documentUri(Uri.parse(fromParent)),
                    Documents.documentUri(Uri.parse(toParent)),
                )
            }.toString()
        }

    override suspend fun deleteDocument(uri: String) = withContext(Dispatchers.IO) {
        val u = Uri.parse(uri)
        if (u.scheme == ContentResolver.SCHEME_FILE) {
            if (!File(u.path ?: "").deleteRecursively()) throw FlutterError("io", "Cannot delete $uri")
            return@withContext
        }
        Documents.mutate(u) { if (DocumentsContract.deleteDocument(resolver, u)) true else null }
        Unit
    }

    // ---- MediaStore video and audio (LIB-002).

    override suspend fun mediaStorePage(
        kinds: List<PickKindMsg>,
        modifiedSinceMs: Long?,
        offset: Long,
        limit: Long,
    ): List<MediaStoreEntryMsg> = withContext(Dispatchers.IO) {
        val types = kinds.mapNotNull {
            when (it) {
                PickKindMsg.VIDEO -> MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                PickKindMsg.AUDIO -> MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO
                PickKindMsg.ANY -> null
                else -> -1
            }
        }.filter { it >= 0 }.ifEmpty {
            if (kinds.contains(PickKindMsg.ANY)) {
                listOf(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO, MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO)
            } else {
                emptyList()
            }
        }
        // Subtitle files next to a video (SUB-012): the system classes them as MEDIA_TYPE_SUBTITLE
        // (API 31), older versions only by name.
        val subtitles = kinds.contains(PickKindMsg.SUBTITLE)
        if (types.isEmpty() && !subtitles) return@withContext emptyList()
        val clauses = ArrayList<String>()
        if (types.isNotEmpty()) clauses += "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (${types.joinToString(",")})"
        if (subtitles) clauses += PickPolicy.subtitleSelection(Build.VERSION.SDK_INT >= 31)
        val selection = StringBuilder(clauses.joinToString(" OR ", "(", ")"))
        if (modifiedSinceMs != null) {
            // Rows not yet scanned have no DATE_MODIFIED; DATE_ADDED stands in.
            // Inlined as an integer: a bound argument is text, and the
            // COALESCE expression has no column affinity to convert it.
            selection.append(" AND $MODIFIED >= ${modifiedSinceMs / 1000}")
        }
        val query = Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection.toString())
            putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, "$MODIFIED DESC, ${MediaStore.MediaColumns._ID} DESC")
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset.toInt())
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit.toInt())
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.VOLUME_NAME,
            MediaStore.MediaColumns.DATE_ADDED,
        )
        val out = ArrayList<MediaStoreEntryMsg>()
        resolver.query(MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL), projection, query, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val type = c.getInt(1)
                val video = type == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                val audio = type == MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO
                val volume = c.getString(6) ?: MediaStore.VOLUME_EXTERNAL
                val collection = when {
                    video -> MediaStore.Video.Media.getContentUri(volume)
                    audio -> MediaStore.Audio.Media.getContentUri(volume)
                    else -> MediaStore.Files.getContentUri(volume)
                }
                out += MediaStoreEntryMsg(
                    uri = ContentUris.withAppendedId(collection, id).toString(),
                    relativePath = c.getString(2).orEmpty(),
                    name = c.getString(3).orEmpty(),
                    size = c.getLong(4),
                    modifiedMs = (if (c.isNull(5) || c.getLong(5) == 0L) c.getLong(7) else c.getLong(5)) * 1000,
                    kind = when {
                        video -> PickKindMsg.VIDEO
                        audio -> PickKindMsg.AUDIO
                        else -> PickKindMsg.SUBTITLE
                    },
                )
            }
        }
        out
    }

    // ---- Save, share, open in.

    override suspend fun createSaveTarget(suggestedName: String, mimeType: String): String? =
        host.launch(ActivityResultContracts.CreateDocument(mimeType), suggestedName)?.toString()

    override suspend fun openWrite(uri: String): Long = withContext(Dispatchers.IO) {
        val u = Uri.parse(uri)
        val stream = try {
            resolver.openOutputStream(u, "wt")
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message)
        } ?: throw FlutterError("io", "Cannot write $uri")
        val handle = nextWriter.getAndIncrement()
        writers[handle] = u to stream
        handle
    }

    override suspend fun write(handle: Long, data: ByteArray) = withContext(Dispatchers.IO) {
        val (_, stream) = writers[handle] ?: throw FlutterError("closed", "Write session $handle is closed")
        stream.write(data)
    }

    override suspend fun closeWrite(handle: Long, abort: Boolean) = withContext(Dispatchers.IO) {
        val (uri, stream) = writers.remove(handle) ?: return@withContext
        stream.close()
        if (abort) {
            try {
                DocumentsContract.deleteDocument(resolver, uri)
            } catch (e: Exception) {
                // Best effort: the partial file stays if the provider refuses.
            }
        }
    }

    override suspend fun share(uris: List<String>, subject: String?) {
        val shared = uris.map { shareable(Uri.parse(it)) }
        if (shared.isEmpty()) return
        val intent = if (shared.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, shared[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(shared))
        }
        intent.type = commonMime(shared)
        subject?.let { intent.putExtra(Intent.EXTRA_SUBJECT, it) }
        intent.clipData = ClipData.newRawUri(null, shared[0]).also { clip ->
            shared.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        host.requireActivity().startActivity(Intent.createChooser(intent, null))
    }

    override suspend fun openWith(uri: String): Boolean {
        val u = shareable(Uri.parse(uri))
        val intent = Intent(Intent.ACTION_VIEW).setDataAndType(u, mimeOfUri(u))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val activity = host.requireActivity()
        val handlers = activity.packageManager.queryIntentActivities(intent, 0)
            .filter { it.activityInfo.packageName != context.packageName }
        if (handlers.isEmpty()) return false
        return try {
            activity.startActivity(Intent.createChooser(intent, null))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** `file:` URIs go out through the FileProvider (no FileUriExposedException). */
    private fun shareable(uri: Uri): Uri =
        if (uri.scheme == ContentResolver.SCHEME_FILE) {
            FileProvider.getUriForFile(context, "${context.packageName}.files", File(uri.path ?: ""))
        } else {
            uri
        }

    private fun mimeOf(name: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"

    private fun mimeOfUri(uri: Uri): String =
        resolver.getType(uri) ?: mimeOf(Documents.nameAndSize(resolver, uri).first)

    private fun commonMime(uris: List<Uri>): String {
        val types = uris.map(::mimeOfUri).distinct()
        if (types.size == 1) return types[0]
        val majors = types.map { it.substringBefore('/') }.distinct()
        return if (majors.size == 1) "${majors[0]}/*" else "*/*"
    }

    fun dispose() {
        observers.values.forEach(resolver::unregisterContentObserver)
        observers.clear()
        openCursors.values.forEach { it.close() }
        openCursors.clear()
        writers.values.forEach { (_, s) -> runCatching { s.close() } }
        writers.clear()
    }

    companion object {
        /** `StorageFacade.changes('mediastore')` watches MediaStore itself. */
        const val MEDIASTORE_GRANT = "mediastore"
        private const val MODIFIED =
            "COALESCE(NULLIF(${MediaStore.MediaColumns.DATE_MODIFIED}, 0), ${MediaStore.MediaColumns.DATE_ADDED})"
        private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    }
}
