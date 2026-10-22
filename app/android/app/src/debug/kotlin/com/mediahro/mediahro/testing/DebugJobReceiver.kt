package com.mediahro.mediahro.testing

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.mediahro.mediahro.platform.background.BackgroundWorkModule

/**
 * Debug-only: leaves a scheduled background job behind for the cold-start check
 * (ADR-049). A job only runs while the app is closed if it is still scheduled
 * when the app goes away, which an integration test cannot arrange because it
 * cleans up after itself. This receiver schedules the real periodic job through
 * the production module and never cancels it.
 *
 * ```
 * adb shell am broadcast -n com.mediahro.app/com.mediahro.mediahro.testing.DebugJobReceiver --es op schedule
 * # swipe the app away, then run the job as the OS would:
 * adb shell cmd jobscheduler run -f com.mediahro.app <job id>
 * adb logcat -s flutter MediahroBackground    # expect: bg: ran debug.leave
 * adb shell am broadcast -n com.mediahro.app/com.mediahro.mediahro.testing.DebugJobReceiver --es op cancel
 * ```
 *
 * `--es id <id>` picks another job id (default `debug.leave`). The Dart side
 * answers `debug.leave` in debug builds only (`registerDebugBackgroundJob`).
 * `<job id>` is the number `adb shell dumpsys jobscheduler com.mediahro.app`
 * lists for the WorkManager job. Not part of any release build: this file and
 * its manifest entry live in `src/debug`.
 */
class DebugJobReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: DEFAULT_ID
        val op = intent.getStringExtra(EXTRA_OP) ?: OP_SCHEDULE
        val module = BackgroundWorkModule(context.applicationContext)
        try {
            when (op) {
                OP_CANCEL -> module.cancel(id)
                OP_SCHEDULE -> module.schedulePeriodic(
                    id,
                    FIFTEEN_MINUTES_MS,
                    requiresNetwork = false,
                    unmeteredOnly = false,
                    requiresCharging = false,
                )
                else -> {
                    Log.w(TAG, "bg: unknown op $op")
                    return
                }
            }
            Log.i(TAG, "bg: $op $id")
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "bg: refused $op $id: ${e.message}")
        }
    }

    companion object {
        const val TAG = "MediahroBackground"
        const val DEFAULT_ID = "debug.leave"
        const val EXTRA_ID = "id"
        const val EXTRA_OP = "op"
        const val OP_SCHEDULE = "schedule"
        const val OP_CANCEL = "cancel"
        private const val FIFTEEN_MINUTES_MS = 15L * 60 * 1000
    }
}
