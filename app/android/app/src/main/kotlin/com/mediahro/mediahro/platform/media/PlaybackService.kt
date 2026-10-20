package com.mediahro.mediahro.platform.media

import android.app.PendingIntent
import android.content.Intent
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.platform.AppEngine

/**
 * Media3 `MediaLibraryService` (SYS-001/002/006): owns the session over
 * [SessionPlayer], posts the media notification and runs as a
 * `mediaPlayback` foreground service while something plays. Media3 starts
 * and stops the foreground state from the player's state, so no wake lock
 * or foreground time outlives playback. The library tree for Android Auto
 * (MUS-013) is added with `MediaBrowseFacade`; a car or voice request while
 * the app is closed starts the app without a screen ([AppEngine], ADR-036).
 */
@OptIn(UnstableApi::class)
class PlaybackService : MediaLibraryService() {
    private var session: MediaLibrarySession? = null

    /** The library session, for children-changed notifications (MUS-013). */
    val librarySession: MediaLibrarySession? get() = session

    override fun onCreate() {
        super.onCreate()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaLibrarySession.Builder(this, SessionHub.player, BrowseCallback(this))
            .setId(SESSION_ID)
            .setSessionActivity(open)
            .build()
        SessionHub.service = this
        AppEngine.onService(alive = true)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onDestroy() {
        AppEngine.onService(alive = false)
        SessionHub.service = null
        session?.release()
        session = null
        super.onDestroy()
    }

    companion object {
        const val SESSION_ID = "mediahro"
    }
}
