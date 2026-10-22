package com.mediahro.mediahro.platform.background

import android.content.Context
import com.mediahro.mediahro.pigeon.BackgroundWorkHostApi
import com.mediahro.mediahro.pigeon.RunsStreamHandler
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers scheduled background work (ADR-049) on an engine. Its own file, so
 * `PlatformModules` needs one line for it. When the engine goes away the runs
 * waiting for Dart fail, so WorkManager retries them.
 */
object BackgroundWorkModules {
    fun register(context: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        BackgroundWorkHostApi.setUp(messenger, BackgroundWorkModule(context.applicationContext))
        RunsStreamHandler.register(messenger, BackgroundHub.handler)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            override fun onEngineWillDestroy() {
                BackgroundHub.broker.reset()
            }
        })
    }
}
