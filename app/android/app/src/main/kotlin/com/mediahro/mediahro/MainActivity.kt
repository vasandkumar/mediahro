package com.mediahro.mediahro

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import com.mediahro.mediahro.platform.AppEngine
import com.mediahro.mediahro.platform.PlatformModules
import com.mediahro.mediahro.platform.media.AlarmHub
import com.mediahro.mediahro.platform.system.IncomingIntents
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Fragment activity so platform modules can use the Activity Result APIs
 * (pickers, permissions, trash consent) and BiometricPrompt.
 *
 * If Android Auto already started the app without a screen (ADR-036), the
 * activity shows that engine instead of starting a second one.
 */
class MainActivity : FlutterFragmentActivity() {
    /** Decided once, before the Flutter fragment is created. */
    private val adopted: String? by lazy {
        AppEngine.CACHE_ID.takeIf { AppEngine.cached() != null }
    }

    override fun getCachedEngineId(): String? = adopted ?: super.getCachedEngineId()

    override fun onCreate(savedInstanceState: Bundle?) {
        if (adopted != null) AppEngine.onActivity(attached = true, finishing = false)
        PlatformModules.host(applicationContext).attach(this)
        super.onCreate(savedInstanceState)
        deliverAlarm(intent)
        // A restored activity's intent was handled before it was destroyed.
        if (savedInstanceState == null) IncomingIntents.handle(applicationContext, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        deliverAlarm(intent)
        IncomingIntents.handle(applicationContext, intent)
    }

    /** Opened from a wake alarm (MUS-011): hand its id to Dart. */
    private fun deliverAlarm(intent: Intent?) {
        intent?.getStringExtra(AlarmHub.EXTRA_ID)?.let {
            intent.removeExtra(AlarmHub.EXTRA_ID)
            AlarmHub.deliver(it)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PlatformModules.register(applicationContext, flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        PlatformModules.host(applicationContext).attach(this)
        PlatformModules.authBrowser?.onAppResumed()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        PlatformModules.pip?.onUserLeaveHint(this)
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        PlatformModules.pip?.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }

    override fun onDestroy() {
        PlatformModules.host(applicationContext).detach(this)
        super.onDestroy()
        if (adopted != null) AppEngine.onActivity(attached = false, finishing = isFinishing)
    }
}
