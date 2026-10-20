package com.mediahro.mediahro.platform.media

import android.app.PendingIntent
import android.content.Intent
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.mediahro.mediahro.MainActivity

/**
 * Media3 `MediaLibraryService` (SYS-001/002/006): owns the session over
 * [SessionPlayer], posts the media notification and runs as a
 * `mediaPlayback` foreground service while something plays. Media3 starts
 * and stops the foreground state from the player's state, so no wake lock
 * or foreground time outlives playback. The library tree for Android Auto
 * (MUS-013) is added with `MediaBrowseFacade`.
 */
@OptIn(UnstableApi::class)
class PlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null

    override fun onCreate() {
        super.onCreate()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaLibrarySession.Builder(this, SessionHub.player, object : MediaLibrarySession.Callback {})
            .setId(SESSION_ID)
            .setSessionActivity(open)
            .build()
        SessionHub.service = this
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onDestroy() {
        SessionHub.service = null
        session?.release()
        session = null
        super.onDestroy()
    }

    companion object {
        const val SESSION_ID = "mediahro"
    }
}
