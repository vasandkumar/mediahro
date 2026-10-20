package com.mediahro.mediahro.platform.media

import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.mediahro.mediahro.pigeon.MediaSessionKindMsg
import com.mediahro.mediahro.pigeon.NowPlayingMsg
import com.mediahro.mediahro.pigeon.PlaybackStatusMsg
import com.mediahro.mediahro.pigeon.RemoteCommandKindMsg
import com.mediahro.mediahro.pigeon.RemoteCommandMsg
import com.mediahro.mediahro.pigeon.SessionStateMsg

/**
 * The Media3 face of the libmpv engine (SYS-001/002). Playback runs in the
 * engine; this player only mirrors what Dart reports (`setNowPlaying`,
 * `setPlaybackStatus`) so the session, notification, lock screen, Bluetooth
 * AVRCP and car surfaces show it, and turns their commands into
 * [RemoteCommandMsg]s for Dart. Commands update the mirrored state
 * optimistically so controls do not flicker while Dart applies them.
 */
@OptIn(UnstableApi::class)
class SessionPlayer(private val onCommand: (RemoteCommandMsg) -> Unit) :
    SimpleBasePlayer(Looper.getMainLooper()) {

    var kind: MediaSessionKindMsg = MediaSessionKindMsg.MUSIC
        set(value) {
            field = value
            invalidateState()
        }

    var nowPlaying: NowPlayingMsg? = null
        private set
    var status: PlaybackStatusMsg = idleStatus()
        private set

    fun setNowPlaying(item: NowPlayingMsg) {
        nowPlaying = item
        invalidateState()
    }

    fun setStatus(value: PlaybackStatusMsg) {
        status = value
        invalidateState()
    }

    /** Back to idle with nothing loaded: the notification goes away. */
    fun clear() {
        nowPlaying = null
        status = idleStatus()
        invalidateState()
    }

    override fun getState(): State {
        val item = nowPlaying
        val commands = Player.Commands.Builder().addAll(
            Player.COMMAND_PLAY_PAUSE,
            Player.COMMAND_STOP,
            Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
            Player.COMMAND_GET_METADATA,
            Player.COMMAND_GET_TIMELINE,
            Player.COMMAND_SET_SPEED_AND_PITCH,
            Player.COMMAND_RELEASE,
        )
        if (item != null && !item.isLive) {
            commands.addAll(
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_SEEK_BACK,
                Player.COMMAND_SEEK_FORWARD,
            )
        }
        if (status.canSkipNext) commands.addAll(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
        if (status.canSkipPrevious) {
            commands.addAll(Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
        }
        val builder = State.Builder()
            .setAvailableCommands(commands.build())
            .setSeekBackIncrementMs(SKIP_MS)
            .setSeekForwardIncrementMs(SKIP_MS)
        // Stopped: nothing loaded as far as the system is concerned, so the
        // notification goes and the service leaves the foreground at once
        // (SYS-006). The item is kept for a later play.
        if (item == null || status.state == SessionStateMsg.STOPPED) {
            return builder.setPlaybackState(Player.STATE_IDLE).build()
        }

        val metadata = MediaMetadata.Builder()
            .setTitle(item.title)
            .setArtist(item.artist)
            .setAlbumTitle(item.album)
            .setArtworkData(item.artwork, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
            .setMediaType(
                when (kind) {
                    MediaSessionKindMsg.VIDEO -> MediaMetadata.MEDIA_TYPE_VIDEO
                    MediaSessionKindMsg.MUSIC -> MediaMetadata.MEDIA_TYPE_MUSIC
                    MediaSessionKindMsg.PODCAST -> MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE
                },
            )
            .setIsPlayable(true)
            .setIsBrowsable(false)
            .build()
        val media = MediaItem.Builder().setMediaId(MEDIA_ID).setMediaMetadata(metadata).build()
        val data = MediaItemData.Builder(MEDIA_ID)
            .setMediaItem(media)
            .setDurationUs(item.durationMs?.let { it * 1000 } ?: C.TIME_UNSET)
            .setIsSeekable(!item.isLive)
            .setIsDynamic(item.isLive)
            .build()
        val playing = status.state == SessionStateMsg.PLAYING
        val rate = status.rate.toFloat().takeIf { it > 0f } ?: 1f
        return builder
            .setPlaylist(listOf(data))
            .setCurrentMediaItemIndex(0)
            .setPlayWhenReady(
                playing || status.state == SessionStateMsg.BUFFERING,
                Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST,
            )
            .setPlaybackState(
                when (status.state) {
                    SessionStateMsg.PLAYING, SessionStateMsg.PAUSED -> Player.STATE_READY
                    SessionStateMsg.BUFFERING -> Player.STATE_BUFFERING
                    SessionStateMsg.STOPPED -> Player.STATE_IDLE // handled above
                },
            )
            .setContentPositionMs(
                PositionSupplier.getExtrapolating(status.positionMs, if (playing) rate else 0f),
            )
            .setPlaybackParameters(PlaybackParameters(rate))
            .build()
    }

    private fun command(kind: RemoteCommandKindMsg, positionMs: Long? = null, rate: Double? = null) =
        onCommand(RemoteCommandMsg(kind, positionMs, rate))

    /** The current position, extrapolated while playing. */
    private fun position(): Long = currentPosition

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        command(if (playWhenReady) RemoteCommandKindMsg.PLAY else RemoteCommandKindMsg.PAUSE)
        status = status.copy(
            state = if (playWhenReady) SessionStateMsg.PLAYING else SessionStateMsg.PAUSED,
            positionMs = position(),
        )
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        command(RemoteCommandKindMsg.STOP)
        status = status.copy(state = SessionStateMsg.STOPPED, positionMs = position())
        return Futures.immediateVoidFuture()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        when (seekCommand) {
            Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM ->
                command(RemoteCommandKindMsg.NEXT)
            Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM ->
                command(RemoteCommandKindMsg.PREVIOUS)
            Player.COMMAND_SEEK_BACK -> command(RemoteCommandKindMsg.SKIP_BY, positionMs = -SKIP_MS)
            Player.COMMAND_SEEK_FORWARD -> command(RemoteCommandKindMsg.SKIP_BY, positionMs = SKIP_MS)
            else -> command(RemoteCommandKindMsg.SEEK_TO, positionMs = positionMs.coerceAtLeast(0))
        }
        if (positionMs != C.TIME_UNSET) status = status.copy(positionMs = positionMs.coerceAtLeast(0))
        return Futures.immediateVoidFuture()
    }

    override fun handleSetPlaybackParameters(playbackParameters: PlaybackParameters): ListenableFuture<*> {
        command(RemoteCommandKindMsg.SET_RATE, rate = playbackParameters.speed.toDouble())
        status = status.copy(rate = playbackParameters.speed.toDouble(), positionMs = position())
        return Futures.immediateVoidFuture()
    }

    override fun handleRelease(): ListenableFuture<*> = Futures.immediateVoidFuture()

    companion object {
        const val MEDIA_ID = "mediahro.now"
        const val SKIP_MS = 10_000L

        private fun idleStatus() = PlaybackStatusMsg(SessionStateMsg.STOPPED, 0, 1.0, false, false)
    }
}
