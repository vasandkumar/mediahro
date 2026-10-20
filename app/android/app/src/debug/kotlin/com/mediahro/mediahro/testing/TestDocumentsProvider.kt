package com.mediahro.mediahro.testing

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

/**
 * Debug-only SAF provider over `filesDir/saf-test` (document id = path
 * below it, `root` for the top). Integration tests use its tree URI as a
 * granted folder; every StorageModule call still goes through
 * DocumentsContract and the provider, exactly as with a real provider.
 */
class TestDocumentsProvider : DocumentsProvider() {
    private val base: File get() = File(context!!.filesDir, "saf-test").apply { mkdirs() }
    private val authority: String get() = "${context!!.packageName}.testdocs"

    override fun onCreate(): Boolean = true

    private fun fileOf(id: String): File =
        if (id == ROOT) base else File(base, id.removePrefix("$ROOT/"))

    private fun idOf(f: File): String =
        if (f == base) ROOT else "$ROOT/" + f.relativeTo(base).invariantSeparatorsPath

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_FLAGS))
            .apply {
                newRow().add(Root.COLUMN_ROOT_ID, ROOT).add(Root.COLUMN_DOCUMENT_ID, ROOT)
                    .add(Root.COLUMN_TITLE, "Mediahro test").add(
                        Root.COLUMN_FLAGS,
                        Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_IS_CHILD,
                    )
            }

    private fun row(c: MatrixCursor, f: File) {
        val dir = f.isDirectory
        var flags = Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_RENAME or Document.FLAG_SUPPORTS_MOVE
        flags = flags or if (dir) Document.FLAG_DIR_SUPPORTS_CREATE else Document.FLAG_SUPPORTS_WRITE
        c.newRow().add(Document.COLUMN_DOCUMENT_ID, idOf(f))
            .add(Document.COLUMN_DISPLAY_NAME, if (f == base) "Mediahro test" else f.name)
            .add(Document.COLUMN_MIME_TYPE, if (dir) Document.MIME_TYPE_DIR else mimeOf(f.name))
            .add(Document.COLUMN_SIZE, if (dir) null else f.length())
            .add(Document.COLUMN_LAST_MODIFIED, f.lastModified())
            .add(Document.COLUMN_FLAGS, flags)
    }

    private fun cursor(projection: Array<out String>?) = MatrixCursor(
        projection ?: arrayOf(
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED, Document.COLUMN_FLAGS,
        ),
    )

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val f = fileOf(documentId)
        if (!f.exists()) throw FileNotFoundException(documentId)
        return cursor(projection).also { row(it, f) }
    }

    override fun queryChildDocuments(parentId: String, projection: Array<out String>?, sortOrder: String?): Cursor {
        val dir = fileOf(parentId)
        if (!dir.isDirectory) throw FileNotFoundException(parentId)
        return cursor(projection).also { c ->
            dir.listFiles()?.sortedBy { it.name }?.forEach { row(c, it) }
            c.setNotificationUri(context!!.contentResolver, DocumentsContract.buildChildDocumentsUri(authority, parentId))
        }
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor =
        ParcelFileDescriptor.open(fileOf(documentId), ParcelFileDescriptor.parseMode(mode))

    override fun createDocument(parentId: String, mimeType: String, displayName: String): String {
        val f = File(fileOf(parentId), displayName)
        if (f.exists()) throw IllegalStateException("exists: $displayName")
        if (mimeType == Document.MIME_TYPE_DIR) f.mkdirs() else f.createNewFile()
        changed(parentId)
        return idOf(f)
    }

    override fun renameDocument(documentId: String, displayName: String): String {
        val f = fileOf(documentId)
        val to = File(f.parentFile, displayName)
        if (!f.renameTo(to)) throw IllegalStateException("rename failed")
        changed(idOf(f.parentFile!!))
        return idOf(to)
    }

    override fun deleteDocument(documentId: String) {
        val f = fileOf(documentId)
        if (!f.deleteRecursively()) throw IllegalStateException("delete failed")
        changed(idOf(f.parentFile!!))
    }

    override fun moveDocument(sourceId: String, sourceParentId: String, targetParentId: String): String {
        val f = fileOf(sourceId)
        val to = File(fileOf(targetParentId), f.name)
        if (!f.renameTo(to)) throw IllegalStateException("move failed")
        changed(sourceParentId)
        changed(targetParentId)
        return idOf(to)
    }

    override fun isChildDocument(parentId: String, documentId: String): Boolean =
        parentId == ROOT || documentId.startsWith("$parentId/")

    override fun findDocumentPath(parentId: String?, childId: String): DocumentsContract.Path {
        val parts = childId.split('/')
        val ids = parts.indices.map { parts.subList(0, it + 1).joinToString("/") }
        val start = parentId?.let { ids.indexOf(it).coerceAtLeast(0) } ?: 0
        return DocumentsContract.Path(if (parentId == null) ROOT else null, ids.subList(start, ids.size))
    }

    private fun changed(parentId: String) {
        context!!.contentResolver.notifyChange(DocumentsContract.buildChildDocumentsUri(authority, parentId), null)
    }

    private fun mimeOf(name: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"

    companion object {
        const val ROOT = "root"
    }
}
