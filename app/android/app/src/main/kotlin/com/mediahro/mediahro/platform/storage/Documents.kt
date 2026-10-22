package com.mediahro.mediahro.platform.storage

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.OpenableColumns
import com.mediahro.mediahro.pigeon.DocumentEntryMsg
import com.mediahro.mediahro.pigeon.FlutterError
import java.io.FileNotFoundException

/** SAF helpers shared by the storage module (LIB-002, FILE-002). */
internal object Documents {
    private val columns = arrayOf(
        Document.COLUMN_DOCUMENT_ID,
        Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE,
        Document.COLUMN_SIZE,
        Document.COLUMN_LAST_MODIFIED,
    )

    fun isTree(uri: Uri): Boolean =
        DocumentsContract.isTreeUri(uri) && !hasDocumentPart(uri)

    private fun hasDocumentPart(uri: Uri): Boolean =
        uri.pathSegments.size >= 4 && uri.pathSegments[2] == "document"

    /** The document URI for a tree URI (its root) or a document URI. */
    fun documentUri(uri: Uri): Uri =
        if (isTree(uri)) {
            DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
        } else {
            uri
        }

    fun documentId(uri: Uri): String =
        if (isTree(uri)) DocumentsContract.getTreeDocumentId(uri) else DocumentsContract.getDocumentId(uri)

    /** The tree URI a document URI was granted under. */
    fun treeOf(uri: Uri): Uri =
        DocumentsContract.buildTreeDocumentUri(uri.authority, DocumentsContract.getTreeDocumentId(uri))

    fun list(resolver: ContentResolver, directory: Uri): List<DocumentEntryMsg> {
        val tree = treeOf(directory)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(directory, documentId(directory))
        val out = ArrayList<DocumentEntryMsg>()
        query(resolver, children).use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0)
                out += entry(DocumentsContract.buildDocumentUriUsingTree(tree, id), c)
            }
        }
        return out
    }

    /**
     * True for URIs of a documents provider (`.../document/<id>`, `.../tree/<id>`): the only
     * ones that answer the document columns. Pure, so it is unit-tested on the JVM.
     */
    fun isDocumentPath(segments: List<String>): Boolean =
        segments.contains("document") || segments.contains("tree")

    fun stat(resolver: ContentResolver, uri: Uri): DocumentEntryMsg {
        // A MediaStore or FileProvider URI from "Open with" is not a document: the document
        // columns do not exist there, so the query fails. Name, size and type come from the
        // openable columns instead.
        if (uri.scheme == ContentResolver.SCHEME_FILE || !isDocumentPath(uri.pathSegments)) {
            val (name, size) = nameAndSize(resolver, uri)
            val mime = try {
                resolver.getType(uri)
            } catch (e: Exception) {
                null
            }
            return DocumentEntryMsg(
                uri = uri.toString(),
                name = name,
                isDirectory = false,
                size = size,
                modifiedMs = null,
                mimeType = mime,
            )
        }
        val doc = documentUri(uri)
        query(resolver, doc).use { c ->
            if (!c.moveToFirst()) throw FlutterError("notFound", "No document $uri")
            return entry(doc, c)
        }
    }

    private fun query(resolver: ContentResolver, uri: Uri): Cursor =
        try {
            resolver.query(uri, columns, null, null, null)
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message)
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message)
        } catch (e: IllegalArgumentException) {
            throw FlutterError("notFound", e.message)
        } ?: throw FlutterError("notFound", "Provider returned no cursor for $uri")

    private fun entry(uri: Uri, c: Cursor): DocumentEntryMsg {
        val mime = c.getString(2)
        return DocumentEntryMsg(
            uri = uri.toString(),
            name = c.getString(1) ?: uri.lastPathSegment.orEmpty(),
            isDirectory = mime == Document.MIME_TYPE_DIR,
            size = if (c.isNull(3)) null else c.getLong(3),
            modifiedMs = if (c.isNull(4)) null else c.getLong(4),
            mimeType = mime,
        )
    }

    /**
     * Display name and size of any openable URI (picker results). Some
     * providers (Photo Picker, OEM galleries) leave `_display_name` empty or
     * fail the OpenableColumns query, so a full-row query and the MIME type
     * back it up; a bare media id is never returned as the name.
     */
    fun nameAndSize(resolver: ContentResolver, uri: Uri): Pair<String, Long?> {
        if (uri.scheme == ContentResolver.SCHEME_FILE) {
            val f = java.io.File(uri.path ?: "")
            return f.name to f.length()
        }
        val names = ArrayList<String?>()
        var size: Long? = null
        fun read(projection: Array<String>?) {
            try {
                resolver.query(uri, projection, null, null, null)?.use { c ->
                    if (!c.moveToFirst()) return
                    for (column in NAME_COLUMNS) {
                        val i = c.getColumnIndex(column)
                        if (i >= 0 && !c.isNull(i)) names += c.getString(i)
                    }
                    val s = c.getColumnIndex(OpenableColumns.SIZE)
                    if (size == null && s >= 0 && !c.isNull(s)) size = c.getLong(s)
                }
            } catch (e: Exception) {
                // Fall through to the next source.
            }
        }
        read(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))
        if (names.none { !it.isNullOrBlank() && !it.trim().all(Char::isDigit) }) read(null)
        val mime = try {
            resolver.getType(uri)
        } catch (e: Exception) {
            null
        }
        val name = PickPolicy.displayName(names, uri.lastPathSegment, mime) {
            android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(it)
        }
        return name to size
    }

    private val NAME_COLUMNS = listOf(OpenableColumns.DISPLAY_NAME)

    /** Runs a SAF mutation and maps provider errors to stable codes. */
    inline fun <T> mutate(uri: Uri, op: () -> T?): T =
        try {
            op() ?: throw FlutterError("io", "Provider refused the operation on $uri")
        } catch (e: FlutterError) {
            throw e
        } catch (e: SecurityException) {
            throw FlutterError("permissionDenied", e.message)
        } catch (e: FileNotFoundException) {
            throw FlutterError("notFound", e.message)
        } catch (e: UnsupportedOperationException) {
            throw FlutterError("unsupported", e.message)
        } catch (e: IllegalStateException) {
            throw FlutterError("io", e.message)
        } catch (e: IllegalArgumentException) {
            throw FlutterError("notFound", e.message)
        }
}
