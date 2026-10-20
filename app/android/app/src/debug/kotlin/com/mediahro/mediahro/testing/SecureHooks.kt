package com.mediahro.mediahro.testing

import android.content.Context
import com.mediahro.mediahro.platform.security.SecureStorageModule
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File

/**
 * Debug-only read-back for the secure storage test (lane C4a):
 * `mediahro.test/secure` replies with the raw stored entry for a key and the
 * whole preferences file, so the test can show no plaintext is on disk.
 */
internal object SecureHooks {
    fun install(context: Context, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/secure", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val key = message as String
                val prefs = context.getSharedPreferences(SecureStorageModule.PREFS, Context.MODE_PRIVATE)
                val file = File(context.applicationInfo.dataDir, "shared_prefs/${SecureStorageModule.PREFS}.xml")
                reply.reply(
                    mapOf(
                        "stored" to prefs.getString(key, null),
                        "file" to (if (file.exists()) file.readText() else ""),
                    ),
                )
            }
    }
}
