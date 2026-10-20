package com.mediahro.mediahro.platform.display

import android.content.Context
import android.content.pm.ActivityInfo
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import com.mediahro.mediahro.pigeon.DisplayChangesStreamHandler
import com.mediahro.mediahro.pigeon.DisplayHostApi
import com.mediahro.mediahro.pigeon.DisplayInfoMsg
import com.mediahro.mediahro.pigeon.DisplayListMsg
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.OrientationLockMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.platform.ActivityHost
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * DisplayFacade on Android (VID-031, VID-036, VID-070/071, CAST-004):
 * displays with refresh rates and HDR, display-mode switching to the content
 * frame rate through the window's `preferredDisplayModeId`, keep-screen-on,
 * window brightness for the player gesture and orientation locks (ignored by
 * Android 16 on large screens, SYS-011).
 */
class DisplayModule(private val context: Context, private val host: ActivityHost) : DisplayHostApi {
    private val manager = context.getSystemService(DisplayManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    override fun displays(): List<DisplayInfoMsg> = manager.displays.map(::describe)

    private fun describe(d: Display): DisplayInfoMsg {
        val mode = d.mode
        val rates = d.supportedModes
            .filter { it.physicalWidth == mode.physicalWidth && it.physicalHeight == mode.physicalHeight }
            .map { round2(it.refreshRate) }
            .distinct()
            .sorted()
        val hdr = d.hdrCapabilities
        return DisplayInfoMsg(
            id = d.displayId.toString(),
            name = d.name ?: "Display ${d.displayId}",
            refreshRate = round2(d.refreshRate),
            supportedRefreshRates = rates,
            hdr = d.isHdr,
            peakNits = hdr?.desiredMaxLuminance?.takeIf { it > 0f }?.toDouble(),
            isExternal = d.displayId != Display.DEFAULT_DISPLAY,
        )
    }

    private fun round2(f: Float): Double = (f * 100).roundToInt() / 100.0

    // ---- Changes (CAST-004 external display, VID-031 HDR on/off).

    private var sink: PigeonEventSink<DisplayListMsg>? = null
    private val listener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = publish()
        override fun onDisplayRemoved(displayId: Int) = publish()
        override fun onDisplayChanged(displayId: Int) = publish()
    }

    private fun publish() {
        sink?.success(DisplayListMsg(displays()))
    }

    val changesHandler = object : DisplayChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<DisplayListMsg>) {
            this@DisplayModule.sink = sink
            manager.registerDisplayListener(listener, main)
        }

        override fun onCancel(p0: Any?) {
            manager.unregisterDisplayListener(listener)
            sink = null
        }
    }

    // ---- Frame-rate matching (VID-036).

    override fun matchFrameRate(displayId: String, fps: Double): Boolean {
        val activity = host.requireActivity()
        val display = displayOf(activity) ?: return false
        // Only the display the window is on can switch for this window.
        if (display.displayId.toString() != displayId || fps <= 0) return false
        val mode = bestMode(display, fps) ?: return false
        val attrs = activity.window.attributes
        if (attrs.preferredDisplayModeId == mode.modeId && display.mode.modeId == mode.modeId) return true
        attrs.preferredDisplayModeId = mode.modeId
        activity.window.attributes = attrs
        return true
    }

    @Suppress("DEPRECATION")
    private fun displayOf(activity: android.app.Activity): Display? =
        if (Build.VERSION.SDK_INT >= 30) activity.display else activity.windowManager.defaultDisplay

    /**
     * The mode at the current resolution whose refresh rate is the content
     * rate or its lowest whole multiple (23.976 → 23.976/47.95/71.93/119.88),
     * so every frame is shown for the same number of refreshes.
     */
    internal fun bestMode(display: Display, fps: Double): Display.Mode? {
        val current = display.mode
        val candidates = display.supportedModes.filter {
            it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight
        }
        for (multiple in 1..5) {
            val target = fps * multiple
            candidates.filter { abs(it.refreshRate - target) <= TOLERANCE * multiple }
                .minByOrNull { abs(it.refreshRate - target) }
                ?.let { return it }
        }
        return null
    }

    override fun restoreDisplayMode(displayId: String) {
        val activity = host.activity ?: return
        val attrs = activity.window.attributes
        if (attrs.preferredDisplayModeId == 0) return
        attrs.preferredDisplayModeId = 0
        activity.window.attributes = attrs
    }

    // ---- Window state for the player.

    override fun keepScreenOn(on: Boolean) {
        val window = host.requireActivity().window
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun setWindowBrightness(value: Double?) {
        if (value != null && (value.isNaN() || value < 0 || value > 1)) {
            throw FlutterError("invalidArgument", "Brightness must be 0–1, got $value")
        }
        val window = host.requireActivity().window
        val attrs = window.attributes
        attrs.screenBrightness = value?.toFloat() ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        window.attributes = attrs
    }

    override fun setOrientationLock(lock: OrientationLockMsg) {
        host.requireActivity().requestedOrientation = when (lock) {
            OrientationLockMsg.AUTO -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            OrientationLockMsg.LANDSCAPE -> ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
            OrientationLockMsg.PORTRAIT -> ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT
            // The video's shape from PipFacade.setAspectRatio or enter (16:9 until then).
            OrientationLockMsg.FOLLOW_VIDEO ->
                if (VideoShape.aspectRatio >= 1.0) {
                    ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE
                } else {
                    ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT
                }
        }
    }

    fun dispose() {
        manager.unregisterDisplayListener(listener)
    }

    companion object {
        /** Refresh-rate match tolerance per multiple (Hz). */
        private const val TOLERANCE = 0.05
    }
}

/** The playing video's shape, shared by PiP and the orientation lock. */
object VideoShape {
    @Volatile var aspectRatio: Double = 16.0 / 9.0
}
