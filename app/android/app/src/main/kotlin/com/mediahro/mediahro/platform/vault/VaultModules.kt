package com.mediahro.mediahro.platform.vault

import android.content.Context
import com.mediahro.mediahro.pigeon.CaptureStatesStreamHandler
import com.mediahro.mediahro.pigeon.SecureWindowHostApi
import com.mediahro.mediahro.pigeon.VaultCryptoHostApi
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the vault's OS crypto and the secure window (IMG-011, ADR-039)
 * on an engine. Its own file, so `PlatformModules` needs one line for it.
 * When the engine is destroyed every open master key is wiped and the window
 * callbacks are removed.
 */
object VaultModules {
    private var crypto: VaultCryptoModule? = null
    private var window: SecureWindowModule? = null

    fun register(context: Context, host: ActivityHost, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        crypto?.dispose()
        val cryptoModule = VaultCryptoModule(context, host).also { crypto = it }
        VaultCryptoHostApi.setUp(messenger, cryptoModule)
        window?.dispose()
        val windowModule = SecureWindowModule(context, host).also { window = it }
        SecureWindowHostApi.setUp(messenger, windowModule)
        CaptureStatesStreamHandler.register(messenger, windowModule.statesHandler)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}

            override fun onEngineWillDestroy() {
                if (crypto === cryptoModule) {
                    cryptoModule.dispose()
                    crypto = null
                }
                if (window === windowModule) {
                    windowModule.dispose()
                    window = null
                }
            }
        })
    }
}
