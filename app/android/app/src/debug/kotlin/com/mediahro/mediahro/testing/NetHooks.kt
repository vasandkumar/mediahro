package com.mediahro.mediahro.testing

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.platform.PlatformModules
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only hooks for the network tests (lane C4a), `mediahro.test/net`
 * taking `[op, arg]`:
 * - `multicastHeld`: leases currently holding a Wi-Fi multicast lock.
 * - `redirect`: sends a VIEW intent for the given URI, as the browser does
 *   when the provider redirects, so the manifest's intent filter and the
 *   redirect activity are exercised.
 * - `returnToApp`: brings the app back over the Custom Tab without a
 *   redirect, as closing the tab does.
 */
internal object NetHooks {
    fun install(context: Context, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/net", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val args = message as List<*>
                when (args[0]) {
                    "multicastHeld" -> reply.reply(PlatformModules.multicast?.held ?: -1)
                    "redirect" -> {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(args[1] as String))
                                .addCategory(Intent.CATEGORY_BROWSABLE)
                                .setPackage(context.packageName)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        reply.reply(true)
                    }
                    "returnToApp" -> {
                        context.startActivity(
                            Intent(context, MainActivity::class.java)
                                .addFlags(
                                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                ),
                        )
                        reply.reply(true)
                    }
                    else -> reply.reply(null)
                }
            }
    }
}
