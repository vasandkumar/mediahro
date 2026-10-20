package com.mediahro.mediahro.platform.media

import android.content.ComponentName
import android.content.Context
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.mediahro.mediahro.pigeon.MediaSessionHostApi
import com.mediahro.mediahro.pigeon.MediaSessionKindMsg
import com.mediahro.mediahro.pigeon.NowPlayingMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.PlaybackStatusMsg
import com.mediahro.mediahro.pigeon.RemoteCommandMsg
import com.mediahro.mediahro.pigeon.RemoteCommandsStreamHandler
import kotlinx.coroutines.guava.await

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
 */
class MediaSessionModule(private val context: Context) : MediaSessionHostApi {
    private var controller: MediaController? = null

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

    fun dispose() {
        controller?.release()
        controller = null
    }
}
