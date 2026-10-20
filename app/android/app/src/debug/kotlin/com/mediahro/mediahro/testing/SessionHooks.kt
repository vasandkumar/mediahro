package com.mediahro.mediahro.testing

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import androidx.core.content.ContextCompat
import androidx.media3.common.PlaybackParameters
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.mediahro.mediahro.platform.PlatformModules
import com.mediahro.mediahro.platform.media.MediaSessionModule
import com.mediahro.mediahro.platform.media.PlaybackService
import com.mediahro.mediahro.platform.media.SessionHub
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only hooks for the media session and audio focus tests (lane C4a):
 * `mediahro.test/session` takes `[op, arg]`. A separate MediaController
 * sends commands through the session as a headset, the notification or a
 * car would; `stealFocus` takes audio focus with a second client the way
 * another app would.
 */
internal object SessionHooks {
    private var controller: MediaController? = null
    private var stolen: AudioFocusRequest? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/session", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val args = message as List<*>
                handle(context, args[0] as String, args.getOrNull(1)) { reply.reply(it) }
            }
    }

    private fun handle(context: Context, op: String, arg: Any?, reply: (Any?) -> Unit) {
        when (op) {
            "notification" -> reply(
                context.getSystemService(NotificationManager::class.java).activeNotifications.isNotEmpty(),
            )
            // A system back, as the gesture or the back button sends it
            // (predictive back, CORE-001): through the activity's dispatcher.
            "systemBack" -> {
                val activity = PlatformModules.host(context).activity
                activity?.onBackPressedDispatcher?.onBackPressed()
                reply(activity != null)
            }
            "notificationDiag" -> reply(notificationDiag(context))
            "notificationPrompt" -> {
                MediaSessionModule.askForNotifications = arg as Boolean
                reply(MediaSessionModule.notificationPrompts)
            }
            "foreground" -> reply((SessionHub.service?.foregroundServiceType ?: 0) != 0)
            "service" -> reply(SessionHub.service != null)
            "stealFocus" -> {
                val audio = context.getSystemService(AudioManager::class.java)
                val gain = when (arg) {
                    "duck" -> AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                    "transient" -> AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                    else -> AudioManager.AUDIOFOCUS_GAIN
                }
                val request = AudioFocusRequest.Builder(gain)
                    .setAudioAttributes(
                        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE).build(),
                    )
                    .setOnAudioFocusChangeListener {}
                    .build()
                stolen = request
                reply(audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            }
            "returnFocus" -> {
                stolen?.let { context.getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
                stolen = null
                reply(true)
            }
            "noisy" -> {
                PlatformModules.audio?.noisyReceiver?.onReceive(context, Intent(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
                reply(true)
            }
            "release" -> {
                controller?.release()
                controller = null
                reply(true)
            }
            else -> withController(context) { c -> reply(command(c, op, arg)) }
        }
    }

    /** Why a media notification is or is not visible (SYS-002 on OEM builds). */
    private fun notificationDiag(context: Context): Map<String, Any?> {
        val nm = context.getSystemService(NotificationManager::class.java)
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "enabled" to nm.areNotificationsEnabled(),
            "permission" to (
                Build.VERSION.SDK_INT < 33 ||
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
                ),
            "channels" to nm.notificationChannels.map { "${it.id}:${it.importance}" },
            "active" to nm.activeNotifications.map { "${it.id}:${it.notification.channelId}" },
            "foreground" to ((SessionHub.service?.foregroundServiceType ?: 0) != 0),
            "prompts" to MediaSessionModule.notificationPrompts,
        )
    }

    private fun command(c: MediaController, op: String, arg: Any?): Any? {
        when (op) {
            "play" -> c.play()
            "pause" -> c.pause()
            "stop" -> c.stop()
            "next" -> c.seekToNext()
            "previous" -> c.seekToPrevious()
            "seekTo" -> c.seekTo((arg as Number).toLong())
            "seekForward" -> c.seekForward()
            "seekBack" -> c.seekBack()
            "speed" -> c.setPlaybackParameters(PlaybackParameters((arg as Number).toFloat()))
            "state" -> return mapOf(
                "title" to c.mediaMetadata.title?.toString(),
                "artist" to c.mediaMetadata.artist?.toString(),
                "album" to c.mediaMetadata.albumTitle?.toString(),
                "hasArtwork" to (c.mediaMetadata.artworkData != null),
                "durationMs" to c.duration,
                "positionMs" to c.currentPosition,
                "playbackState" to c.playbackState,
                "playWhenReady" to c.playWhenReady,
                "speed" to c.playbackParameters.speed.toDouble(),
                "canNext" to c.isCommandAvailable(androidx.media3.common.Player.COMMAND_SEEK_TO_NEXT),
                "canPrevious" to c.isCommandAvailable(androidx.media3.common.Player.COMMAND_SEEK_TO_PREVIOUS),
                "mediaType" to c.mediaMetadata.mediaType,
            )
            else -> return "unknown op $op"
        }
        return true
    }

    private fun withController(context: Context, block: (MediaController) -> Unit) {
        controller?.takeIf { it.isConnected }?.let { return block(it) }
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener(
            {
                val c = future.get()
                controller = c
                block(c)
            },
            ContextCompat.getMainExecutor(context),
        )
    }
}
