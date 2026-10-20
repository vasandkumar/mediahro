package com.mediahro.mediahro.platform.media

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.R
import com.mediahro.mediahro.pigeon.AlarmFiredMsg
import com.mediahro.mediahro.pigeon.AlarmHostApi
import com.mediahro.mediahro.pigeon.AlarmsFiredStreamHandler
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.ScheduledAlarmMsg
import com.mediahro.mediahro.platform.ActivityHost

/** Fired alarms on their way to Dart; one held back until Dart listens. */
object AlarmHub {
    @Volatile var sink: PigeonEventSink<AlarmFiredMsg>? = null
    @Volatile private var pending: String? = null

    fun deliver(id: String) {
        val s = sink
        if (s != null) s.success(AlarmFiredMsg(id)) else pending = id
    }

    val handler = object : AlarmsFiredStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<AlarmFiredMsg>) {
            AlarmHub.sink = sink
            pending?.let {
                pending = null
                sink.success(AlarmFiredMsg(it))
            }
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }
    }

    const val EXTRA_ID = "mediahro.alarm.id"
    const val EXTRA_LABEL = "mediahro.alarm.label"
    const val ACTION_FIRE = "com.mediahro.mediahro.ALARM"
}

/**
 * AlarmFacade on Android (MUS-011 wake alarms): `AlarmManager.setAlarmClock`,
 * shown in the status bar and the clock's "next alarm", exact and allowed
 * in Doze. The user grants "Alarms & reminders" once (Android 12+); without
 * it the alarm falls back to a 10-minute window. Alarms are not restored
 * after a reboot (no boot receiver outside the enterprise build): the music
 * player schedules them again whenever it starts.
 */
class AlarmModule(private val context: Context, private val host: ActivityHost) : AlarmHostApi {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    override fun isSupported(): Boolean = true

    private fun canExact(): Boolean = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()

    override suspend fun schedule(alarm: ScheduledAlarmMsg) {
        if (!canExact() && host.activity != null && Build.VERSION.SDK_INT >= 31) {
            // The system page for "Alarms & reminders"; the user comes back here.
            host.launch(
                ActivityResultContracts.StartActivityForResult(),
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}")),
            )
        }
        val fire = fireIntent(alarm.id, alarm.label)
        if (canExact()) {
            val show = PendingIntent.getActivity(
                context,
                alarm.id.hashCode(),
                launchIntent(context, alarm.id),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            alarms.setAlarmClock(AlarmManager.AlarmClockInfo(alarm.atMs, show), fire)
        } else {
            alarms.setWindow(AlarmManager.RTC_WAKEUP, alarm.atMs, WINDOW_MS, fire)
        }
    }

    override fun cancel(id: String) {
        alarms.cancel(fireIntent(id, ""))
    }

    private fun fireIntent(id: String, label: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, AlarmReceiver::class.java)
            .setAction(AlarmHub.ACTION_FIRE)
            // The data URI makes each alarm's PendingIntent distinct (and cancellable).
            .setData(Uri.parse("mediahro-alarm:${Uri.encode(id)}"))
            .putExtra(AlarmHub.EXTRA_ID, id)
            .putExtra(AlarmHub.EXTRA_LABEL, label),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        private const val WINDOW_MS = 10 * 60 * 1000L
        const val CHANNEL = "mediahro.alarms"

        fun launchIntent(context: Context, id: String): Intent =
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(AlarmHub.EXTRA_ID, id)
    }
}

/**
 * The alarm went off. With the app running, Dart gets it at once and starts
 * the music. Otherwise an alarm notification (full screen where the user
 * allows it) opens the app, which then delivers the id.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(AlarmHub.EXTRA_ID) ?: return
        if (AlarmHub.sink != null) {
            AlarmHub.deliver(id)
            return
        }
        val label = intent.getStringExtra(AlarmHub.EXTRA_LABEL).orEmpty()
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                AlarmModule.CHANNEL,
                context.getString(R.string.mediahro_alarm_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val open = PendingIntent.getActivity(
            context,
            id.hashCode(),
            AlarmModule.launchIntent(context, id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(context, AlarmModule.CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(label.ifBlank { context.getString(R.string.mediahro_alarm_channel) })
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setContentIntent(open)
            .setAutoCancel(true)
        val fullScreen = Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()
        if (fullScreen) builder.setFullScreenIntent(open, true)
        val allowed = Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (allowed) nm.notify(id.hashCode(), builder.build())
    }
}
