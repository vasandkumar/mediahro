package com.mediahro.mediahro.platform.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.R
import com.mediahro.mediahro.pigeon.HomeWidgetsHostApi
import com.mediahro.mediahro.pigeon.RemoteCommandKindMsg
import com.mediahro.mediahro.pigeon.RemoteCommandMsg
import com.mediahro.mediahro.pigeon.WidgetStateMsg
import com.mediahro.mediahro.platform.media.SessionHub
import java.io.File

/**
 * The "now playing" home-screen widget (MUS-012): artwork, title, artist
 * and previous / play-pause / next. The last state is kept on disk, so a
 * widget added later, or redrawn by the launcher after the app stopped,
 * shows it at once.
 */
internal object WidgetState {
    private const val PREFS = "mediahro.widget"

    data class State(val title: String?, val artist: String?, val playing: Boolean)

    fun save(context: Context, state: WidgetStateMsg?) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        val art = artFile(context)
        if (state == null) {
            prefs.clear()
            art.delete()
        } else {
            prefs.putString("title", state.title).putString("artist", state.artist).putBoolean("playing", state.playing)
            val bytes = state.artwork
            if (bytes != null) art.writeBytes(bytes) else art.delete()
        }
        prefs.apply()
    }

    fun load(context: Context): State {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return State(prefs.getString("title", null), prefs.getString("artist", null), prefs.getBoolean("playing", false))
    }

    /** Playing ends when the app's process does; the widget then shows play. */
    fun markStopped(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("playing", false).apply()
    }

    fun artFile(context: Context) = File(context.filesDir, "widget-art")

    fun artwork(context: Context): Bitmap? {
        val f = artFile(context)
        if (!f.exists()) return null
        // RemoteViews travel through binder: keep the bitmap small.
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, opts)
        var sample = 1
        while (opts.outWidth / sample > MAX_ART_PX || opts.outHeight / sample > MAX_ART_PX) sample *= 2
        return BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    private const val MAX_ART_PX = 256
}

internal object WidgetRenderer {
    fun renderAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, NowPlayingWidget::class.java))
        if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
    }

    fun views(context: Context): RemoteViews {
        val state = WidgetState.load(context)
        val views = RemoteViews(context.packageName, R.layout.mediahro_widget)
        val hasItem = state.title != null
        views.setTextViewText(R.id.widget_title, state.title ?: context.getString(R.string.mediahro_widget_idle))
        views.setTextViewText(R.id.widget_artist, state.artist.orEmpty())
        views.setViewVisibility(R.id.widget_artist, if (state.artist.isNullOrBlank()) View.GONE else View.VISIBLE)
        val art = if (hasItem) WidgetState.artwork(context) else null
        if (art != null) {
            views.setImageViewBitmap(R.id.widget_art, art)
        } else {
            views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
        }
        views.setImageViewResource(
            R.id.widget_play_pause,
            if (state.playing) R.drawable.mediahro_widget_pause else R.drawable.mediahro_widget_play,
        )
        views.setContentDescription(
            R.id.widget_play_pause,
            context.getString(if (state.playing) R.string.mediahro_widget_pause else R.string.mediahro_widget_play),
        )
        for (id in listOf(R.id.widget_previous, R.id.widget_next)) {
            views.setViewVisibility(id, if (hasItem) View.VISIBLE else View.GONE)
        }
        views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
        views.setOnClickPendingIntent(R.id.widget_play_pause, action(context, WidgetActionReceiver.PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.widget_previous, action(context, WidgetActionReceiver.PREVIOUS))
        views.setOnClickPendingIntent(R.id.widget_next, action(context, WidgetActionReceiver.NEXT))
        return views
    }

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun action(context: Context, action: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        action.hashCode(),
        Intent(context, WidgetActionReceiver::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

/** The launcher asks for the widget's views (added, resized, rebooted). */
class NowPlayingWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // After a reboot or a killed process nothing is playing any more.
        if (SessionHub.sink == null) WidgetState.markStopped(context)
        manager.updateAppWidget(ids, WidgetRenderer.views(context))
    }
}

/**
 * Widget buttons. With the app running they reach the player as remote
 * commands, like the notification's; otherwise the widget switches to its
 * stopped look and the next tap on it opens the app.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val sink = SessionHub.sink
        if (sink == null) {
            WidgetState.markStopped(context)
            WidgetRenderer.renderAll(context)
            return
        }
        val kind = when (intent.action) {
            PLAY_PAUSE -> RemoteCommandKindMsg.TOGGLE_PLAY_PAUSE
            NEXT -> RemoteCommandKindMsg.NEXT
            PREVIOUS -> RemoteCommandKindMsg.PREVIOUS
            else -> return
        }
        sink.success(RemoteCommandMsg(kind))
    }

    companion object {
        const val PLAY_PAUSE = "com.mediahro.mediahro.widget.PLAY_PAUSE"
        const val NEXT = "com.mediahro.mediahro.widget.NEXT"
        const val PREVIOUS = "com.mediahro.mediahro.widget.PREVIOUS"
    }
}

/** HomeWidgetsFacade on Android (MUS-012). */
class HomeWidgetsModule(private val context: Context) : HomeWidgetsHostApi {
    override fun update(state: WidgetStateMsg?) {
        WidgetState.save(context, state)
        WidgetRenderer.renderAll(context)
    }
}
