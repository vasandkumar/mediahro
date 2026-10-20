package com.mediahro.mediahro

import android.os.Bundle
import com.mediahro.mediahro.platform.PlatformModules
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Fragment activity so platform modules can use the Activity Result APIs
 * (pickers, permissions, trash consent) and BiometricPrompt.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        PlatformModules.host(applicationContext).attach(this)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformModules.register(applicationContext, flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        PlatformModules.host(applicationContext).attach(this)
    }

    override fun onDestroy() {
        PlatformModules.host(applicationContext).detach(this)
        super.onDestroy()
    }
}
