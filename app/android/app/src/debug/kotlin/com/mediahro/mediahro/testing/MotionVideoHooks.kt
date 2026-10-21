package com.mediahro.mediahro.testing

import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only hook for the Motion Photo test (lane C4a): `mediahro.test/motionvideo`
 * takes a served video URI and replies with its bytes, read through
 * `ContentResolver.openAssetFileDescriptor` the way the media APIs do.
 */
internal object MotionVideoHooks {
    fun install(context: Context, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/motionvideo", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                Thread {
                    val bytes = runCatching {
                        context.contentResolver.openAssetFileDescriptor(Uri.parse(message as String), "r")!!.use { afd ->
                            afd.createInputStream().use { it.readBytes() }
                        }
                    }.getOrNull()
                    android.os.Handler(android.os.Looper.getMainLooper()).post { reply.reply(bytes) }
                }.start()
            }
    }
}
