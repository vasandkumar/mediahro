package com.mediahro.mediahro.platform.storage

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.TrashResultMsg
import com.mediahro.mediahro.platform.ActivityHost
import java.io.File
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * Trash with undo (FILE-002). MediaStore items (and SAF documents backed by
 * MediaStore) go to the OS trash (`IS_TRASHED`, or
 * `MediaStore.createTrashRequest` with the system consent dialog for items
 * another app owns), so they show in the Files app's trash and expire on the
 * OS schedule. SAF documents of other providers move to a `.Trash-mediahro`
 * folder at the tree root; app-private `file:` paths move to the app's own
 * trash. The undo token names the journal entry that reverses each move.
 */
internal class TrashManager(private val context: Context, private val host: ActivityHost) {
    private val resolver: ContentResolver = context.contentResolver
    private val journal = context.getSharedPreferences("mediahro.trash", Context.MODE_PRIVATE)
    private val trashRoot = File(context.filesDir, "trash")

    suspend fun trash(uris: List<Uri>): TrashResultMsg {
        val token = UUID.randomUUID().toString()
        val entries = JSONArray()
        val trashed = ArrayList<String>()
        val needConsent = ArrayList<Pair<Uri, Uri>>()
        for ((i, uri) in uris.withIndex()) {
            val media = mediaUriOf(uri)
            when {
                media != null && Build.VERSION.SDK_INT >= 30 -> {
                    if (setTrashed(media, true)) {
                        entries.put(mediaEntry(uri, media))
                        trashed += uri.toString()
                    } else {
                        needConsent += uri to media
                    }
                }
                uri.scheme == ContentResolver.SCHEME_FILE -> {
                    entries.put(trashFile(uri, token, i))
                    trashed += uri.toString()
                }
                uri.scheme == ContentResolver.SCHEME_CONTENT && DocumentsContract.isDocumentUri(context, uri) -> {
                    entries.put(trashDocument(uri))
                    trashed += uri.toString()
                }
                else -> throw FlutterError("unsupported", "No trash for $uri")
            }
        }
        if (needConsent.isNotEmpty() && Build.VERSION.SDK_INT >= 30) {
            val request = MediaStore.createTrashRequest(resolver, needConsent.map { it.second }, true)
            if (consent(request.intentSender)) {
                for ((original, media) in needConsent) {
                    entries.put(mediaEntry(original, media))
                    trashed += original.toString()
                }
            }
        }
        if (entries.length() == 0) return TrashResultMsg(trashed, null)
        journal.edit().putString(token, entries.toString()).apply()
        return TrashResultMsg(trashed, token)
    }

    suspend fun restore(token: String) {
        val raw = journal.getString(token, null) ?: throw FlutterError("notFound", "Undo expired")
        val entries = JSONArray(raw)
        val needConsent = ArrayList<Uri>()
        for (i in 0 until entries.length()) {
            val e = entries.getJSONObject(i)
            when (e.getString("kind")) {
                "media" -> {
                    val media = Uri.parse(e.getString("media"))
                    if (Build.VERSION.SDK_INT >= 30 && !setTrashed(media, false)) needConsent += media
                }
                "file" -> {
                    val from = File(e.getString("trashed"))
                    val to = File(e.getString("original"))
                    to.parentFile?.mkdirs()
                    if (!from.renameTo(to)) {
                        from.copyTo(to, overwrite = false)
                        from.delete()
                    }
                }
                "saf" -> Documents.mutate(Uri.parse(e.getString("trashed"))) {
                    DocumentsContract.moveDocument(
                        resolver,
                        Uri.parse(e.getString("trashed")),
                        Uri.parse(e.getString("trashFolder")),
                        Uri.parse(e.getString("parent")),
                    )
                }
            }
        }
        if (needConsent.isNotEmpty() && Build.VERSION.SDK_INT >= 30) {
            consent(MediaStore.createTrashRequest(resolver, needConsent, false).intentSender)
        }
        journal.edit().remove(token).apply()
        File(trashRoot, token).deleteRecursively()
    }

    private suspend fun consent(sender: android.content.IntentSender): Boolean {
        val result = host.launch(
            ActivityResultContracts.StartIntentSenderForResult(),
            IntentSenderRequest.Builder(sender).build(),
        )
        return result.resultCode == Activity.RESULT_OK
    }

    /** The MediaStore item behind [uri], if any. */
    private fun mediaUriOf(uri: Uri): Uri? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        if (uri.authority == MediaStore.AUTHORITY) return uri
        if (!DocumentsContract.isDocumentUri(context, uri)) return null
        return try {
            MediaStore.getMediaUri(context, uri)
        } catch (e: Exception) {
            null
        }
    }

    /** Sets `IS_TRASHED` directly; false when another app owns the item. */
    private fun setTrashed(media: Uri, trashed: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < 30) return false
        val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_TRASHED, if (trashed) 1 else 0) }
        // Trashed rows are hidden from updates unless MATCH_INCLUDE is asked for.
        val extras = Bundle().apply { putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE) }
        return try {
            resolver.update(media, values, extras) > 0
        } catch (e: RecoverableSecurityException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    private fun mediaEntry(original: Uri, media: Uri) =
        JSONObject().put("kind", "media").put("original", original.toString()).put("media", media.toString())

    private fun trashFile(uri: Uri, token: String, index: Int): JSONObject {
        val f = File(uri.path ?: throw FlutterError("notFound", "$uri"))
        if (!f.exists()) throw FlutterError("notFound", "$uri")
        val dir = File(trashRoot, token).apply { mkdirs() }
        val dest = File(dir, "${index}_${f.name}")
        if (!f.renameTo(dest)) {
            if (f.isDirectory) f.copyRecursively(dest) else f.copyTo(dest)
            if (!f.deleteRecursively()) throw FlutterError("permissionDenied", "Cannot delete $uri")
        }
        return JSONObject().put("kind", "file").put("original", f.absolutePath).put("trashed", dest.absolutePath)
    }

    private fun trashDocument(uri: Uri): JSONObject {
        val tree = Documents.treeOf(uri)
        val root = Documents.documentUri(tree)
        val parent = parentOf(uri, tree) ?: throw FlutterError("unsupported", "No parent for $uri")
        val folder = trashFolder(tree, root)
        val moved = Documents.mutate(uri) { DocumentsContract.moveDocument(resolver, uri, parent, folder) }
        return JSONObject().put("kind", "saf").put("original", uri.toString()).put("trashed", moved.toString())
            .put("trashFolder", folder.toString()).put("parent", parent.toString())
    }

    private fun parentOf(uri: Uri, tree: Uri): Uri? {
        val path = try {
            DocumentsContract.findDocumentPath(resolver, uri)
        } catch (e: Exception) {
            null
        } ?: return null
        val ids = path.path
        if (ids.size < 2) return null
        return DocumentsContract.buildDocumentUriUsingTree(tree, ids[ids.size - 2])
    }

    private fun trashFolder(tree: Uri, root: Uri): Uri {
        Documents.list(resolver, root).firstOrNull { it.isDirectory && it.name == TRASH_NAME }?.let {
            return Uri.parse(it.uri)
        }
        return Documents.mutate(root) {
            DocumentsContract.createDocument(resolver, root, DocumentsContract.Document.MIME_TYPE_DIR, TRASH_NAME)
        }
    }

    companion object {
        const val TRASH_NAME = ".Trash-mediahro"
    }
}
