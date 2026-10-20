package com.mediahro.mediahro.platform.display

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import androidx.fragment.app.FragmentActivity
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.PipHostApi
import com.mediahro.mediahro.pigeon.PipStateMsg
import com.mediahro.mediahro.pigeon.PipStatesStreamHandler
import com.mediahro.mediahro.platform.ActivityHost

/**
 * PipFacade on Android (VID-067): system picture-in-picture for the player.
 * The PiP window's play/pause/skip controls come from the Media3 session
 * (SYS-001), whose commands reach Dart through MediaSessionFacade. Auto-PiP
 * on leave uses `setAutoEnterEnabled` (Android 12+) or `onUserLeaveHint`.
 */
class PipModule(private val context: Context, private val host: ActivityHost) : PipHostApi {
    private var autoEnter = false

    override fun isSupported(): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    override fun enter(aspectRatio: Double): Boolean {
        if (!isSupported()) return false
        if (aspectRatio > 0) VideoShape.aspectRatio = aspectRatio
        val activity = host.requireActivity()
        if (activity.isInPictureInPictureMode) return true
        return try {
            activity.enterPictureInPictureMode(params())
        } catch (e: IllegalStateException) {
            // Activity not in a state that allows PiP (e.g. already stopping).
            false
        }
    }

    override fun exit() {
        val activity = host.activity ?: return
        if (!activity.isInPictureInPictureMode) return
        // Bringing the task to the front expands the PiP window back to full screen.
        context.getSystemService(ActivityManager::class.java).appTasks.firstOrNull()?.moveToFront()
    }

    override fun setAutoEnter(enabled: Boolean) {
        autoEnter = enabled
        if (Build.VERSION.SDK_INT >= 31 && isSupported()) {
            host.activity?.setPictureInPictureParams(params())
        }
    }

    /** ADR-028: kept for auto-PiP and followVideo; resizes an open PiP window. */
    override fun setAspectRatio(aspectRatio: Double) {
        if (aspectRatio <= 0 || aspectRatio.isNaN() || aspectRatio.isInfinite()) return
        VideoShape.aspectRatio = aspectRatio
        if (!isSupported()) return
        val activity = host.activity ?: return
        if (activity.isInPictureInPictureMode || (autoEnter && Build.VERSION.SDK_INT >= 31)) {
            activity.setPictureInPictureParams(params())
        }
    }

    /** Android 11 and older: auto-PiP when the user leaves (home, recents). */
    fun onUserLeaveHint(activity: FragmentActivity) {
        if (autoEnter && Build.VERSION.SDK_INT < 31 && isSupported() && !activity.isInPictureInPictureMode) {
            try {
                activity.enterPictureInPictureMode(params())
            } catch (e: IllegalStateException) {
                // Ignored: leaving continues normally.
            }
        }
    }

    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(rational(VideoShape.aspectRatio))
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setAutoEnterEnabled(autoEnter).setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    /** PiP accepts 1:2.39 … 2.39:1; wider or taller videos are letterboxed. */
    private fun rational(aspect: Double): Rational {
        val clamped = aspect.coerceIn(1 / MAX_ASPECT, MAX_ASPECT)
        return Rational((clamped * 10_000).toInt(), 10_000)
    }

    // ---- State (isActive).

    private var sink: PigeonEventSink<PipStateMsg>? = null

    val statesHandler = object : PipStatesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<PipStateMsg>) {
            this@PipModule.sink = sink
            host.activity?.let { sink.success(PipStateMsg(it.isInPictureInPictureMode)) }
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }
    }

    fun onPictureInPictureModeChanged(active: Boolean) {
        sink?.success(PipStateMsg(active))
    }

    companion object {
        private const val MAX_ASPECT = 2.39
    }
}
