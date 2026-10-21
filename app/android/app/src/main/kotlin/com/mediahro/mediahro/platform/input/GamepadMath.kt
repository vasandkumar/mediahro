package com.mediahro.mediahro.platform.input

import com.mediahro.mediahro.pigeon.GamepadAxisMsg
import kotlin.math.abs
import kotlin.math.sign

/** Pure rules of the gamepad module (JVM-testable; no Android types). */
internal object GamepadMath {
    /** Resting drift below this is reported as 0. */
    const val DEAD_ZONE = 0.15f

    /** Values closer than this to the last one sent are dropped. */
    const val STEP = 0.01f

    /**
     * Dead zone with the remaining range rescaled to the full -1..1, so a
     * stick pushed just past the zone starts at 0 instead of jumping to 0.15.
     */
    fun deadZone(value: Float, zone: Float = DEAD_ZONE): Float {
        val a = abs(value)
        if (a <= zone) return 0f
        return (sign(value) * ((a - zone) / (1f - zone))).coerceIn(-1f, 1f)
    }

    /** Triggers are 0..1 with the same drift zone. */
    fun trigger(value: Float, zone: Float = DEAD_ZONE): Float {
        if (value <= zone) return 0f
        return ((value - zone) / (1f - zone)).coerceIn(0f, 1f)
    }

    /** The hat is already -1, 0 or 1; analog hats are snapped to that. */
    fun hat(value: Float): Float = when {
        value > 0.5f -> 1f
        value < -0.5f -> -1f
        else -> 0f
    }

    /** Android axis codes used to read one controller. */
    class Layout(
        val leftX: Int,
        val leftY: Int,
        val rightX: Int,
        val rightY: Int,
        val leftTrigger: Int,
        val rightTrigger: Int,
        val hatX: Int,
        val hatY: Int,
    )

    /**
     * Chooses the axes a controller really has: the right stick is RX/RY if
     * present, else Z/RZ; the triggers are BRAKE/GAS only if the pad has those
     * and no LTRIGGER/RTRIGGER, else LTRIGGER/RTRIGGER (values are `MotionEvent.AXIS_*`).
     */
    fun layout(has: (Int) -> Boolean): Layout = Layout(
        leftX = AXIS_X,
        leftY = AXIS_Y,
        rightX = if (has(AXIS_RX) && has(AXIS_RY)) AXIS_RX else AXIS_Z,
        rightY = if (has(AXIS_RX) && has(AXIS_RY)) AXIS_RY else AXIS_RZ,
        // BRAKE/GAS only for a pad that reports them and not LTRIGGER/RTRIGGER; an
        // unknown device (an injected event has none) gets the modern default.
        leftTrigger = if (has(AXIS_BRAKE) && !has(AXIS_LTRIGGER)) AXIS_BRAKE else AXIS_LTRIGGER,
        rightTrigger = if (has(AXIS_GAS) && !has(AXIS_RTRIGGER)) AXIS_GAS else AXIS_RTRIGGER,
        hatX = AXIS_HAT_X,
        hatY = AXIS_HAT_Y,
    )

    /** Keeps the last value sent per controller and axis and drops repeats. */
    class Changes {
        private val last = HashMap<Pair<Int, GamepadAxisMsg>, Float>()

        /** True if [value] differs enough from the last one sent (and records it). */
        fun changed(deviceId: Int, axis: GamepadAxisMsg, value: Float): Boolean {
            val key = deviceId to axis
            val before = last[key] ?: 0f
            val different = abs(value - before) >= STEP || (value == 0f && before != 0f)
            if (different) last[key] = value
            return different
        }

        fun forget(deviceId: Int) {
            last.keys.removeAll { it.first == deviceId }
        }
    }

    // MotionEvent.AXIS_* (compile-time constants in android.view.MotionEvent).
    const val AXIS_X = 0
    const val AXIS_Y = 1
    const val AXIS_Z = 11
    const val AXIS_RX = 12
    const val AXIS_RY = 13
    const val AXIS_RZ = 14
    const val AXIS_HAT_X = 15
    const val AXIS_HAT_Y = 16
    const val AXIS_LTRIGGER = 17
    const val AXIS_RTRIGGER = 18
    const val AXIS_GAS = 22
    const val AXIS_BRAKE = 23
}
