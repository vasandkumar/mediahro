package com.mediahro.mediahro.platform.display

import android.content.Context
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import com.mediahro.mediahro.platform.ActivityHost
import com.mediahro.mediahro_engine.MediahroEngineViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * The native HDR video view (VID-031, ADR-022): a `SurfaceView` whose
 * `Surface` is registered with the engine under the handle Dart chose, so mpv
 * draws into it and the display can show HDR instead of the 8-bit Flutter
 * texture. Creation params: `{'handle': int}`. Each view has a method channel
 * `mediahro/hdr_video/<handle>`:
 *
 * - Dart to native `ready`: completes with true once the surface exists
 *   (false if the view was disposed first). Call it before
 *   `PlaybackEngine.setVideoTarget(VideoTarget.platformView(handle))`.
 * - native to Dart `surfaceDestroyed`: the surface went away (app in the
 *   background); the engine detaches until a new `ready`.
 *
 * While a view exists the window is in HDR colour mode, restored afterwards.
 */
class HdrVideoViewFactory(
    private val messenger: BinaryMessenger,
    private val host: ActivityHost,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val handle = ((args as? Map<*, *>)?.get("handle") as? Number)?.toInt()
            ?: throw IllegalArgumentException("hdr video view needs a handle")
        return HdrVideoPlatformView(context, messenger, host, handle)
    }

    companion object {
        const val VIEW_TYPE = "mediahro/hdr_video"
    }
}

private class HdrVideoPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    private val host: ActivityHost,
    private val handle: Int,
) : PlatformView, SurfaceHolder.Callback {
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "mediahro/hdr_video/$handle")
    private val waiting = mutableListOf<MethodChannel.Result>()
    private var created = false
    private var disposed = false
    private val window = host.activity?.window

    private val view = SurfaceView(context).apply {
        // 10-bit buffers let HDR10 and HLG keep their precision.
        holder.setFormat(PixelFormat.RGBA_1010102)
        holder.addCallback(this@HdrVideoPlatformView)
        contentDescription = null
    }

    init {
        window?.let(HdrWindowMode::acquire)
        channel.setMethodCallHandler(::onCall)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> when {
                disposed -> result.success(false)
                created -> result.success(true)
                else -> waiting += result
            }
            else -> result.notImplemented()
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        created = true
        MediahroEngineViews.register(handle, holder.surface)
        waiting.forEach { it.success(true) }
        waiting.clear()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        MediahroEngineViews.register(handle, holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        created = false
        MediahroEngineViews.unregister(handle)
        if (!disposed) channel.invokeMethod("surfaceDestroyed", null)
    }

    override fun getView(): View = view

    override fun dispose() {
        disposed = true
        MediahroEngineViews.unregister(handle)
        waiting.forEach { it.success(false) }
        waiting.clear()
        channel.setMethodCallHandler(null)
        view.holder.removeCallback(this)
        window?.let { w -> main.post { HdrWindowMode.release(w) } }
    }
}
