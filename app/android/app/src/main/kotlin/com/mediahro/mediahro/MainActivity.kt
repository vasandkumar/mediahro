package com.mediahro.mediahro

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import com.mediahro.mediahro.platform.PlatformModules
import com.mediahro.mediahro.platform.media.AlarmHub
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
        deliverAlarm(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        deliverAlarm(intent)
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
    }
}
