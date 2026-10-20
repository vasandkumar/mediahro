package com.mediahro.mediahro.platform.enterprise

import android.app.Activity
import android.app.ActivityManager
import android.app.AlarmManager
import android.app.Application
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.KioskHostApi
import com.mediahro.mediahro.pigeon.KioskStatesStreamHandler
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.platform.ActivityHost

/**
 * KioskFacade on Android (B2B-002): lock task mode (screen pinning unless
 * the device owner made Mediahro a lock-task package), immersive full screen,
 * screen kept on, a crash watchdog that relaunches the app, and an optional
 * launch after boot (enterprise build; `RECEIVE_BOOT_COMPLETED` is only
 * declared there, docs/07).
 */
class KioskModule(private val context: Context, private val host: ActivityHost) :
    KioskHostApi, Application.ActivityLifecycleCallbacks {
    private val main = Handler(Looper.getMainLooper())
    private val activityManager = context.getSystemService(ActivityManager::class.java)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var sink: PigeonEventSink<Boolean>? = null
    private var wanted = false
    private var last: Boolean? = null
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    init {
        (context.applicationContext as Application).registerActivityLifecycleCallbacks(this)
    }

    override fun isSupported(): Boolean = true

    override fun isActive(): Boolean =
        wanted && activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE

    override fun enter() {
        val activity = host.requireActivity()
        wanted = true
        main.post {
            // Pinning asks the user once unless the device owner allow-listed the app.
            try {
                activity.startLockTask()
            } catch (e: IllegalArgumentException) {
                // Not allowed on this device: the immersive kiosk still applies.
            }
            val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            installWatchdog()
            publishSoon()
        }
    }

    override fun exit() {
        wanted = false
        val activity = host.activity
        main.post {
            if (activity != null) {
                try {
                    activity.stopLockTask()
                } catch (e: IllegalStateException) {
                    // Not in lock task mode.
                }
                WindowCompat.getInsetsController(activity.window, activity.window.decorView)
                    .show(WindowInsetsCompat.Type.systemBars())
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            removeWatchdog()
            publish()
        }
    }

    override fun setStartOnBoot(enabled: Boolean) {
        val boot = ComponentName(context.packageName, BOOT_RECEIVER)
        val present = try {
            context.packageManager.getReceiverInfo(boot, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
        if (!present) throw FlutterError("unsupported", "Starting after boot is only in the enterprise build")
        prefs.edit().putBoolean(KEY_BOOT, enabled).apply()
    }

    // --- state stream ---------------------------------------------------

    val statesHandler = object : KioskStatesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<Boolean>) {
            this@KioskModule.sink = sink
            last = null
            publish()
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }
    }

    private fun publish() {
        val now = isActive()
        if (now != last) {
            last = now
            sink?.success(now)
        }
    }

    /** The pin confirmation is a system dialog: look again for a few seconds. */
    private fun publishSoon() {
        for (i in 0..PUBLISH_CHECKS) main.postDelayed(::publish, i * PUBLISH_STEP_MS)
    }

    override fun onActivityResumed(activity: Activity) = publish()

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}

    // --- watchdog -------------------------------------------------------

    /** An uncaught exception schedules a relaunch a few seconds later (best effort; see the help page). */
    private fun installWatchdog() {
        if (previousHandler != null) return
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        previousHandler = previous
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                scheduleRelaunch()
            } finally {
                previous?.uncaughtException(thread, error)
            }
        }
    }

    private fun removeWatchdog() {
        val previous = previousHandler ?: return
        Thread.setDefaultUncaughtExceptionHandler(previous)
        previousHandler = null
    }

    private fun scheduleRelaunch() {
        val launch = PendingIntent.getActivity(
            context,
            RELAUNCH_ID,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val at = System.currentTimeMillis() + RELAUNCH_DELAY_MS
        if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
            alarms.setAlarmClock(AlarmManager.AlarmClockInfo(at, launch), launch)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, launch)
        }
    }

    fun dispose() {
        (context.applicationContext as Application).unregisterActivityLifecycleCallbacks(this)
        removeWatchdog()
        sink = null
    }

    companion object {
        const val PREFS = "mediahro.kiosk"
        const val KEY_BOOT = "startOnBoot"
        const val BOOT_RECEIVER = "com.mediahro.mediahro.platform.enterprise.BootReceiver"
        private const val RELAUNCH_ID = 0x4b10
        private const val RELAUNCH_DELAY_MS = 3_000L
        private const val PUBLISH_CHECKS = 20
        private const val PUBLISH_STEP_MS = 500L
    }
}
