package com.mediahro.mediahro.platform.enterprise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.mediahro.mediahro.MainActivity

/**
 * Launches the app after boot when the kiosk asked for it (B2B-002). Only the
 * enterprise build declares this receiver and `RECEIVE_BOOT_COMPLETED`.
 * Android 10+ lets an app start an activity from the background only when it
 * is a lock-task package of the device owner or holds "Display over other
 * apps"; that is part of provisioning a kiosk device.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(KioskModule.PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KioskModule.KEY_BOOT, false)) return
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
