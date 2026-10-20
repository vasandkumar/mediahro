package com.mediahro.mediahro.platform.storage

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.mediahro.mediahro.pigeon.FolderGrantMsg
import java.security.MessageDigest

/**
 * Persisted SAF tree grants (SYS-007). The grant id is a stable hash of the
 * tree URI, so it is safe as a path segment (`saf://tree/<id>/`); the OS
 * keeps the permission itself (`takePersistableUriPermission`).
 */
internal class GrantStore(private val context: Context) {
    private val prefs = context.getSharedPreferences("mediahro.grants", Context.MODE_PRIVATE)

    fun idOf(uri: Uri): String =
        MessageDigest.getInstance("SHA-256").digest(uri.toString().toByteArray())
            .take(12).joinToString("") { "%02x".format(it) }

    fun add(tree: Uri, displayName: String): FolderGrantMsg {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        if (!isOwn(tree)) {
            try {
                context.contentResolver.takePersistableUriPermission(tree, flags)
            } catch (e: SecurityException) {
                // Read-only providers offer no write grant.
                context.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val id = idOf(tree)
        prefs.edit().putString(id, "$tree\n$displayName").apply()
        return FolderGrantMsg(id, tree.toString(), displayName)
    }

    /** The app's own providers need no grant (same UID). */
    private fun isOwn(uri: Uri): Boolean = uri.authority?.startsWith(context.packageName + ".") == true

    private fun live(uri: Uri, persisted: Set<Uri>): Boolean = isOwn(uri) || uri in persisted

    private fun persisted(): Set<Uri> =
        context.contentResolver.persistedUriPermissions.filter { it.isReadPermission }.map { it.uri }.toSet()

    fun resolve(id: String): Uri? {
        val (uri, _) = read(id) ?: return null
        return uri.takeIf { live(it, persisted()) }
    }

    fun all(): List<FolderGrantMsg> {
        val live = persisted()
        return prefs.all.keys.mapNotNull { id ->
            val (uri, name) = read(id) ?: return@mapNotNull null
            if (live(uri, live)) FolderGrantMsg(id, uri.toString(), name) else null
        }
    }

    fun release(id: String) {
        read(id)?.takeUnless { isOwn(it.first) }?.let { (uri, _) ->
            try {
                context.contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (e: SecurityException) {
                // Already gone (user revoked it in Settings).
            }
        }
        prefs.edit().remove(id).apply()
    }

    private fun read(id: String): Pair<Uri, String>? {
        val v = prefs.getString(id, null) ?: return null
        val nl = v.indexOf('\n')
        if (nl < 0) return null
        return Uri.parse(v.substring(0, nl)) to v.substring(nl + 1)
    }
}
