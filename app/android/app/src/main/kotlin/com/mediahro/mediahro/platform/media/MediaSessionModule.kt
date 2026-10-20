package com.mediahro.mediahro.platform.media

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.os.Build
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.mediahro.mediahro.pigeon.MediaSessionHostApi
import com.mediahro.mediahro.pigeon.MediaSessionKindMsg
import com.mediahro.mediahro.pigeon.NowPlayingMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.PlaybackStatusMsg
import com.mediahro.mediahro.pigeon.RemoteCommandMsg
import com.mediahro.mediahro.pigeon.RemoteCommandsStreamHandler
import com.mediahro.mediahro.platform.ActivityHost
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.launch

/** The one session player shared by [PlaybackService] and the module. */
object SessionHub {
    @Volatile var sink: PigeonEventSink<RemoteCommandMsg>? = null

    val player: SessionPlayer by lazy { SessionPlayer { command -> sink?.success(command) } }

    @Volatile var service: PlaybackService? = null
}

/**
 * MediaSessionFacade on Android (SYS-001/002/006). `activate` connects a
 * controller to [PlaybackService], which creates the session; `deactivate`
 * clears the session and lets the service stop.
 *
 * Android 13+: the first activation asks for POST_NOTIFICATIONS (SYS-002)
 * without waiting for the answer. Playback, the session and the foreground
 * service work either way; some OEM builds (One UI) hide the media
 * notification while the permission is denied, so lock-screen and shade
 * controls need it there.
 */
class MediaSessionModule(private val context: Context, private val host: ActivityHost) : MediaSessionHostApi {
    private var controller: MediaController? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val prefs = context.getSharedPreferences("mediahro.session", Context.MODE_PRIVATE)

    val commandsHandler = object : RemoteCommandsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<RemoteCommandMsg>) {
            SessionHub.sink = sink
        }

        override fun onCancel(p0: Any?) {
            SessionHub.sink = null
        }
    }

    override suspend fun activate(kind: MediaSessionKindMsg) {
        SessionHub.player.kind = kind
        askForNotificationsOnce()
        if (controller?.isConnected == true) return
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        controller = MediaController.Builder(context, token).buildAsync().await()
    }

    override fun setNowPlaying(item: NowPlayingMsg) = SessionHub.player.setNowPlaying(item)

    override fun setPlaybackStatus(status: PlaybackStatusMsg) = SessionHub.player.setStatus(status)

    override suspend fun deactivate() {
        SessionHub.player.clear()
        controller?.release()
        controller = null
        // The player is idle now, so the service is out of the foreground.
        SessionHub.service?.stopSelf()
    }

    /** Asks once per install; the OS stops asking after repeated denials anyway. */
    private fun askForNotificationsOnce() {
        if (Build.VERSION.SDK_INT < 33 || !askForNotifications) return
        if (host.granted(Manifest.permission.POST_NOTIFICATIONS)) return
        if (prefs.getBoolean(KEY_ASKED, false) || host.activity == null) return
        prefs.edit().putBoolean(KEY_ASKED, true).apply()
        notificationPrompts++
        scope.launch {
            try {
                host.request(listOf(Manifest.permission.POST_NOTIFICATIONS))
            } catch (e: Exception) {
                // No activity any more: the next start from the app asks again.
                prefs.edit().putBoolean(KEY_ASKED, false).apply()
            }
        }
    }

    fun dispose() {
        scope.cancel()
        controller?.release()
        controller = null
    }

    companion object {
        private const val KEY_ASKED = "notificationsAsked"

        /** Debug hooks turn the prompt off to test the denied path. */
        @Volatile var askForNotifications = true

        /** Prompts launched in this process (debug diagnostics). */
        @Volatile var notificationPrompts = 0
    }
}
