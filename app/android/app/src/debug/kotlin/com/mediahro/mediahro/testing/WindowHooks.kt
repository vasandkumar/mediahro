package com.mediahro.mediahro.testing

import android.os.Build
import android.view.WindowManager
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only window read-back for the Display/PiP tests (lane C4a):
 * `mediahro.test/window` replies with the activity window's state.
 */
internal object WindowHooks {
    fun install(host: ActivityHost, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/window", StandardMessageCodec.INSTANCE)
            .setMessageHandler { _, reply ->
                val activity = host.activity
                if (activity == null) {
                    reply.reply(null)
                    return@setMessageHandler
                }
                val attrs = activity.window.attributes
                @Suppress("DEPRECATION")
                val display = if (Build.VERSION.SDK_INT >= 30) activity.display else activity.windowManager.defaultDisplay
                reply.reply(
                    mapOf(
                        "keepScreenOn" to ((attrs.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0),
                        "secure" to ((attrs.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0),
                        "brightness" to attrs.screenBrightness.toDouble(),
                        "orientation" to activity.requestedOrientation,
                        "preferredModeId" to attrs.preferredDisplayModeId,
                        "modes" to display?.supportedModes?.map { "${it.modeId}:${it.refreshRate}" },
                        "currentModeId" to display?.mode?.modeId,
                        "inPip" to activity.isInPictureInPictureMode,
                    ),
                )
            }
    }
}
