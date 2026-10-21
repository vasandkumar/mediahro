package com.mediahro.mediahro.platform.display

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PresentationHostApi
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * External-display presentations on Android (ADR-044 amendment 1, IMG-012,
 * CAST-004): an `android.app.Presentation` on the chosen display hosting a
 * `FlutterView` of a second engine, spawned from the app's engine at
 * `presentationMain`. That engine shows only what [present] sends it (an
 * image, a transition, a pan and zoom, a caption), never other state of the
 * app. A presentation closes when the display is removed, when the app closes
 * it, and when the app's engine is destroyed.
 */
class PresentationModule(
    private val context: Context,
    private val host: ActivityHost,
) : PresentationHostApi, DisplayManager.DisplayListener {
    private val displays = context.getSystemService(DisplayManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val registry = PresentationRegistry()
    private val group = FlutterEngineGroup(context)
    private val live = ConcurrentHashMap<Long, Live>()

    /** What one open presentation holds. */
    private class Live(
        val engine: FlutterEngine,
        val channel: BasicMessageChannel<Any?>,
        var presentation: ExternalPresentation? = null,
        /** The page listens (it said so over the control channel). */
        var ready: Boolean = false,
        /** The newest frame that arrived before the page was ready. */
        var pending: Map<String, Any?>? = null,
    )

    init {
        displays.registerDisplayListener(this, main)
    }

    override suspend fun open(displayId: String): Long? = withContext(Dispatchers.Main) {
        val id = displayId.toIntOrNull() ?: return@withContext null
        val display = displays.getDisplay(id) ?: return@withContext null
        // The built-in screen is the app itself; only another display can present.
        if (display.displayId == Display.DEFAULT_DISPLAY) return@withContext null
        val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        // A group engine shares the VM resources of the first one; no plugins: the page only draws what it is sent.
        val engine = group.createAndRunEngine(
            FlutterEngineGroup.Options(context)
                .setDartEntrypoint(DartEntrypoint(bundle, ENTRYPOINT))
                .setAutomaticallyRegisterPlugins(false),
        )
        val channel = BasicMessageChannel(engine.dartExecutor.binaryMessenger, "mediahro/presentation", StandardMessageCodec.INSTANCE)
        val state = Live(engine, channel)
        var presentationId = 0L
        MethodChannel(engine.dartExecutor.binaryMessenger, "mediahro/presentation/control").setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                state.ready = true
                state.pending?.let { channel.send(it) }
                state.pending = null
            }
            result.success(null)
        }
        val shown = ExternalPresentation(host.activity ?: context, display, engine) {
            // Dismissed by the system (the display went away) or by us.
            main.post { registry.close(presentationId) }
        }
        presentationId = registry.add(displayId) {
            live.remove(presentationId)
            runCatching { shown.dismiss() }
            runCatching { shown.release() }
            engine.destroy()
        }
        state.presentation = shown
        live[presentationId] = state
        try {
            shown.show()
        } catch (e: RuntimeException) {
            // The display refused a window (for example it went away meanwhile).
            registry.close(presentationId)
            return@withContext null
        }
        presentationId
    }

    override suspend fun close(id: Long) {
        withContext(Dispatchers.Main) { registry.close(id) }
    }

    override suspend fun present(id: Long, frame: Map<String, Any?>) {
        withContext(Dispatchers.Main) {
            val state = live[id] ?: return@withContext
            if (state.ready) state.channel.send(frame) else state.pending = frame
        }
    }

    override fun onDisplayRemoved(displayId: Int) {
        registry.closeForDisplay(displayId.toString())
    }

    override fun onDisplayAdded(displayId: Int) {}

    override fun onDisplayChanged(displayId: Int) {}

    fun dispose() {
        displays.unregisterDisplayListener(this)
        main.post { registry.closeAll() }
    }

    companion object {
        /** The Dart function the spawned engine starts at (`presentation_main.dart`). */
        const val ENTRYPOINT = "presentationMain"
    }
}

/** The window on the external display; it owns the `FlutterView` of the spawned engine. */
private class ExternalPresentation(
    outer: Context,
    display: Display,
    private val engine: FlutterEngine,
    private val onDismissed: () -> Unit,
) : Presentation(outer, display) {
    private var view: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val v = FlutterView(context, FlutterSurfaceView(context))
        v.attachToFlutterEngine(engine)
        view = v
        setContentView(v)
        engine.lifecycleChannel.appIsResumed()
        setOnDismissListener { onDismissed() }
    }

    fun release() {
        view?.detachFromFlutterEngine()
        view = null
    }
}
