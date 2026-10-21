package com.mediahro.mediahro.testing

import android.content.Context
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only external display for the presentation test (lane C4a): a virtual
 * display owned by the app, drawn into an `ImageReader`, so the test can show a
 * frame on it and read the pixels back. `mediahro.test/vdisplay` takes `[op]`:
 * - `create`: a 640x360 presentation display; replies its id (a DisplayInfo id).
 * - `pixel`: the ARGB value of the middle pixel of the newest image, or null.
 * - `release`: removes the display (the presentation on it must close).
 */
internal object PresentationHooks {
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        val main = Handler(Looper.getMainLooper())
        BasicMessageChannel(messenger, "mediahro.test/vdisplay", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                main.post {
                    when ((message as List<*>)[0]) {
                        "create" -> reply.reply(create(context))
                        "pixel" -> reply.reply(pixel())
                        "release" -> {
                            release()
                            reply.reply(true)
                        }
                        else -> reply.reply(null)
                    }
                }
            }
    }

    private fun create(context: Context): String {
        release()
        val images = ImageReader.newInstance(WIDTH, HEIGHT, PixelFormat.RGBA_8888, 3)
        val manager = context.getSystemService(DisplayManager::class.java)
        val virtual = manager.createVirtualDisplay(
            "mediahro-test-external",
            WIDTH,
            HEIGHT,
            160,
            images.surface,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION or DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY,
        )
        reader = images
        display = virtual
        return virtual.display.displayId.toString()
    }

    private fun pixel(): Int? {
        val image = reader?.acquireLatestImage() ?: return null
        image.use {
            val plane = it.planes[0]
            val x = WIDTH / 2
            val y = HEIGHT / 2
            val at = y * plane.rowStride + x * plane.pixelStride
            val b = plane.buffer
            val r = b.get(at).toInt() and 0xff
            val g = b.get(at + 1).toInt() and 0xff
            val bl = b.get(at + 2).toInt() and 0xff
            return (0xff shl 24) or (r shl 16) or (g shl 8) or bl
        }
    }

    private fun release() {
        display?.release()
        reader?.close()
        display = null
        reader = null
    }

    private const val WIDTH = 640
    private const val HEIGHT = 360
}
