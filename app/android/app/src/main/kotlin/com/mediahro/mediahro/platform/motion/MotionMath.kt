package com.mediahro.mediahro.platform.motion

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.hypot

/**
 * The maths of the 360 look-around (IMG-001, ADR-042), with no Android types
 * so it is unit-tested.
 *
 * Input is the row-major 3x3 rotation matrix of `getRotationMatrixFromVector`
 * after `remapCoordinateSystem` for the display rotation: it maps the screen
 * frame (x right, y up the screen, z out of the screen) to the world (x east,
 * y north, z up; the heading is arbitrary for a game rotation vector). The
 * camera looks out of the back of the device, along the screen's -z axis.
 */
internal object MotionMath {
    /** Below this horizontal share of the aim the heading is undefined (looking straight up or down). */
    const val ZENITH_EPSILON = 1e-3

    /**
     * Where the camera axis points: [heading] clockwise from north (radians,
     * 0..2pi is not enforced), [pitch] above the horizon, and whether the
     * heading is meaningful.
     */
    class Aim(val heading: Double, val pitch: Double, val horizontal: Boolean)

    /** The aim of `-z` of the screen frame in the world: minus the third column of [r]. */
    fun aim(r: FloatArray): Aim {
        require(r.size >= 9) { "a 3x3 matrix is needed" }
        val east = -r[2].toDouble()
        val north = -r[5].toDouble()
        val up = -r[8].toDouble()
        val horizontal = hypot(east, north) > ZENITH_EPSILON
        return Aim(atan2(east, north), asin(up.coerceIn(-1.0, 1.0)), horizontal)
    }

    /** [angle] wrapped to (-pi, pi]. */
    fun wrap(angle: Double): Double {
        var a = angle % (2 * PI)
        if (a > PI) a -= 2 * PI
        if (a <= -PI) a += 2 * PI
        return a
    }

    /**
     * Turns aims into yaw relative to the heading of the first one. When the
     * camera points straight up or down the last yaw is kept instead of
     * jumping.
     */
    class Tracker {
        private var reference: Double? = null
        private var lastYaw = 0.0

        /** (yaw, pitch) for [aim]; the first call defines yaw 0. */
        fun update(aim: Aim): Pair<Double, Double> {
            if (aim.horizontal) {
                val ref = reference ?: aim.heading.also { reference = it }
                lastYaw = wrap(aim.heading - ref)
            }
            return lastYaw to aim.pitch
        }
    }

    /** True when [a] and [b] differ by less than [step] in both angles (not worth sending). */
    fun same(a: Pair<Double, Double>?, b: Pair<Double, Double>, step: Double = 0.002): Boolean =
        a != null && abs(a.first - b.first) < step && abs(a.second - b.second) < step
}
