package com.mediahro.mediahro.platform.vault

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.mediahro.mediahro.pigeon.CaptureStatesStreamHandler
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.SecureWindowHostApi
import com.mediahro.mediahro.platform.ActivityHost
import java.util.function.Consumer

/**
 * SecureWindowFacade on Android (IMG-011, ADR-039): `FLAG_SECURE` keeps the
 * app out of screenshots, screen recordings, casts of the screen and the
 * recents thumbnail. The choice is remembered and applied again to an
 * activity that is re-created (rotation, process restart of the activity).
 * On Android 15+ the state of screen recording over the app's windows is
 * reported through [statesHandler].
 */
class SecureWindowModule(context: Context, private val host: ActivityHost) :
    SecureWindowHostApi, Application.ActivityLifecycleCallbacks {
    private val app = context.applicationContext as Application
    private var secure = false
    private var sink: PigeonEventSink<Boolean>? = null
    private var recording: Consumer<Int>? = null
    private var watched: Activity? = null

    init {
        app.registerActivityLifecycleCallbacks(this)
    }

    override fun setSecure(secure: Boolean) {
        this.secure = secure
        host.activity?.let(::apply)
    }

    private fun apply(activity: Activity) {
        val flag = WindowManager.LayoutParams.FLAG_SECURE
        if (secure) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = apply(activity)

    override fun onActivityResumed(activity: Activity) {
        apply(activity)
        watch(activity)
    }

    override fun onActivityPaused(activity: Activity) = unwatch()

    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}

    val statesHandler = object : CaptureStatesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<Boolean>) {
            this@SecureWindowModule.sink = sink
            host.activity?.let(::watch)
        }

        override fun onCancel(p0: Any?) {
            unwatch()
            sink = null
        }
    }

    /** Android 15+: tells whether the app's windows are being recorded. */
    private fun watch(activity: Activity) {
        if (Build.VERSION.SDK_INT < 35 || sink == null || recording != null) return
        val listener = Consumer<Int> { state ->
            sink?.success(state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE)
        }
        val wm = activity.getSystemService(WindowManager::class.java)
        val initial = wm.addScreenRecordingCallback(activity.mainExecutor, listener)
        recording = listener
        watched = activity
        sink?.success(initial == WindowManager.SCREEN_RECORDING_STATE_VISIBLE)
    }

    private fun unwatch() {
        val listener = recording ?: return
        if (Build.VERSION.SDK_INT >= 35) {
            watched?.getSystemService(WindowManager::class.java)?.removeScreenRecordingCallback(listener)
        }
        recording = null
        watched = null
    }

    fun dispose() {
        unwatch()
        app.unregisterActivityLifecycleCallbacks(this)
        sink = null
    }
}
