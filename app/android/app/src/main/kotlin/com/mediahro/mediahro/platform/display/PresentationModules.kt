package com.mediahro.mediahro.platform.display

import android.content.Context
import com.mediahro.mediahro.pigeon.PresentationHostApi
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers external-display presentations (ADR-044 amendment 1) on an
 * engine. Its own file, so `PlatformModules` needs one line for it. When the
 * engine is destroyed every open presentation is closed and its spawned
 * engine released.
 */
object PresentationModules {
    private var module: PresentationModule? = null

    fun register(context: Context, host: ActivityHost, engine: FlutterEngine) {
        module?.dispose()
        val created = PresentationModule(context, host).also { module = it }
        PresentationHostApi.setUp(engine.dartExecutor.binaryMessenger, created)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            override fun onEngineWillDestroy() {
                created.dispose()
                if (module === created) module = null
            }
        })
    }
}
