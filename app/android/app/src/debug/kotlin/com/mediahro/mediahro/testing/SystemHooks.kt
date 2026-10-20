package com.mediahro.mediahro.testing

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.core.content.pm.ShortcutManagerCompat
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.pigeon.AppIntentKindMsg
import com.mediahro.mediahro.platform.system.IntentsModule
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File

/**
 * Debug-only hooks for open-with, share and shortcut tests (lane C4a),
 * `mediahro.test/system` taking `[op, arg]`: real intents are sent to
 * MainActivity the way the file manager, the share sheet and the launcher
 * send them.
 * - `view` (file name in cache): ACTION_VIEW with a content URI.
 * - `shareText` (text): ACTION_SEND text/plain.
 * - `shareFiles` (comma-separated names): ACTION_SEND_MULTIPLE.
 * - `shortcut` (kind name): the launcher shortcut / App Action intent.
 * - `dynamicShortcuts`: ids of the published shortcuts.
 */
internal object SystemHooks {
    fun install(context: Context, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/system", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val args = message as List<*>
                val arg = args.getOrNull(1) as String?
                when (args[0]) {
                    "view" -> {
                        val uri = shared(context, arg!!)
                        start(context, Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/mp4"), uri)
                        reply.reply(uri.toString())
                    }
                    "shareText" -> {
                        start(context, Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, arg), null)
                        reply.reply(true)
                    }
                    "shareFiles" -> {
                        val uris = arg!!.split(',').map { shared(context, it) }
                        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).setType("video/*")
                            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                        intent.clipData = ClipData.newRawUri(null, uris[0]).also { c ->
                            uris.drop(1).forEach { c.addItem(ClipData.Item(it)) }
                        }
                        start(context, intent, null)
                        reply.reply(uris.map(Uri::toString))
                    }
                    "shortcut" -> {
                        val kind = AppIntentKindMsg.entries.first { it.name == arg }
                        start(context, IntentsModule.shortcutIntent(context, kind, "test-argument"), null)
                        reply.reply(true)
                    }
                    "dynamicShortcuts" -> reply.reply(ShortcutManagerCompat.getDynamicShortcuts(context).map { it.id })
                    else -> reply.reply(null)
                }
            }
    }

    private fun shared(context: Context, name: String): Uri {
        val f = File(context.cacheDir, name).apply { writeBytes(ByteArray(16)) }
        return FileProvider.getUriForFile(context, "${context.packageName}.files", f)
    }

    private fun start(context: Context, intent: Intent, uri: Uri?) {
        intent.setClass(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (uri != null) intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(intent)
    }
}
