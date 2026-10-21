package com.mediahro.mediahro.platform.motion

import android.content.Context
import com.mediahro.mediahro.pigeon.AttitudeStreamHandler
import com.mediahro.mediahro.pigeon.MotionHostApi
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the device attitude (IMG-001, ADR-042) on an engine. Its own file,
 * so `PlatformModules` needs one line for it. The sensor is released when the
 * engine is destroyed.
 */
object MotionModules {
    private var motion: MotionModule? = null

    fun register(context: Context, host: ActivityHost, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        motion?.dispose()
        val module = MotionModule(context, host).also { motion = it }
        MotionHostApi.setUp(messenger, module)
        AttitudeStreamHandler.register(messenger, module.attitudeHandler)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            override fun onEngineWillDestroy() {
                module.dispose()
                if (motion === module) motion = null
            }
        })
    }
}
