package com.mediahro.mediahro.platform.motion

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MotionMathTest {
    /**
     * The row-major rotation matrix of a device whose camera axis (out of the
     * back, the screen's -z) looks at [heading] (clockwise from north) and
     * [pitch] (above the horizon), held upright (screen y toward the sky as
     * far as the aim allows). Columns are the screen axes in the world.
     */
    private fun matrix(heading: Double, pitch: Double): FloatArray {
        val aim = doubleArrayOf(sin(heading) * cos(pitch), cos(heading) * cos(pitch), sin(pitch))
        val z = doubleArrayOf(-aim[0], -aim[1], -aim[2])
        val x = doubleArrayOf(cos(heading), -sin(heading), 0.0) // screen right, level
        val y = doubleArrayOf(z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0])
        return floatArrayOf(
            x[0].toFloat(), y[0].toFloat(), z[0].toFloat(),
            x[1].toFloat(), y[1].toFloat(), z[1].toFloat(),
            x[2].toFloat(), y[2].toFloat(), z[2].toFloat(),
        )
    }

    private fun assertAim(heading: Double, pitch: Double) {
        val a = MotionMath.aim(matrix(heading, pitch))
        assertEquals(pitch, a.pitch, 1e-4)
        assertEquals(MotionMath.wrap(heading), MotionMath.wrap(a.heading), 1e-4)
        assertTrue(a.horizontal)
    }

    @Test
    fun `IMG-001 an upright phone facing north looks at the horizon`() {
        val upright = floatArrayOf(1f, 0f, 0f, 0f, 0f, -1f, 0f, 1f, 0f)
        val a = MotionMath.aim(upright)
        assertEquals(0.0, a.heading, 1e-6)
        assertEquals(0.0, a.pitch, 1e-6)
    }

    @Test
    fun `IMG-001 the aim is recovered for headings and pitches all round`() {
        for (h in listOf(0.0, 0.5, PI / 2, 2.5, PI, -2.0, -PI / 2, -0.1)) {
            for (p in listOf(-1.2, -0.6, 0.0, 0.4, 1.2)) assertAim(h, p)
        }
    }

    @Test
    fun `IMG-001 a phone lying face up looks straight down and has no heading`() {
        val flat = floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)
        val a = MotionMath.aim(flat)
        assertEquals(-PI / 2, a.pitch, 1e-6)
        assertFalse(a.horizontal)
        val faceDown = floatArrayOf(1f, 0f, 0f, 0f, -1f, 0f, 0f, 0f, -1f)
        assertEquals(PI / 2, MotionMath.aim(faceDown).pitch, 1e-6)
    }

    @Test
    fun `IMG-001 yaw is relative to the first heading, positive to the right`() {
        val t = MotionMath.Tracker()
        val h0 = 1.0
        val first = t.update(MotionMath.aim(matrix(h0, 0.2)))
        assertEquals(0.0, first.first, 1e-6)
        assertEquals(0.2, first.second, 1e-4)
        assertEquals(0.5, t.update(MotionMath.aim(matrix(h0 + 0.5, 0.0))).first, 1e-4)
        assertEquals(-0.7, t.update(MotionMath.aim(matrix(h0 - 0.7, -0.3))).first, 1e-4)
    }

    @Test
    fun `IMG-001 yaw wraps through the half turn without a jump`() {
        val t = MotionMath.Tracker()
        t.update(MotionMath.aim(matrix(2.5, 0.0)))
        // 2.5 + 1.0 = 3.5 rad is past pi: the yaw is +1.0, not -5.28.
        assertEquals(1.0, t.update(MotionMath.aim(matrix(3.5, 0.0))).first, 1e-4)
        assertEquals(-1.0, t.update(MotionMath.aim(matrix(1.5, 0.0))).first, 1e-4)
        assertEquals(PI - 0.01, t.update(MotionMath.aim(matrix(2.5 + PI - 0.01, 0.0))).first, 1e-3)
        assertEquals(-PI + 0.01, t.update(MotionMath.aim(matrix(2.5 + PI + 0.01, 0.0))).first, 1e-3)
    }

    @Test
    fun `IMG-001 looking straight up keeps the last yaw instead of jumping`() {
        val t = MotionMath.Tracker()
        t.update(MotionMath.aim(matrix(0.3, 0.0)))
        val before = t.update(MotionMath.aim(matrix(0.8, 0.5)))
        val zenith = MotionMath.Aim(0.0, PI / 2, false)
        val held = t.update(zenith)
        assertEquals(before.first, held.first, 1e-9)
        assertEquals(PI / 2, held.second, 1e-9)
        // A matrix that aims straight up has no horizontal part.
        assertFalse(MotionMath.aim(floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, -1f)).horizontal)
    }

    @Test
    fun `IMG-001 the wrap is in minus pi exclusive to pi inclusive`() {
        assertEquals(PI, MotionMath.wrap(PI), 1e-12)
        assertEquals(PI, MotionMath.wrap(-PI), 1e-12)
        assertEquals(0.0, MotionMath.wrap(2 * PI), 1e-12)
        assertEquals(-0.1, MotionMath.wrap(2 * PI - 0.1), 1e-9)
        assertEquals(0.1, MotionMath.wrap(-2 * PI + 0.1), 1e-9)
    }

    @Test
    fun `IMG-001 tiny changes are not worth sending`() {
        val a = 0.5 to 0.1
        assertTrue(MotionMath.same(a, 0.5005 to 0.1004))
        assertFalse(MotionMath.same(a, 0.51 to 0.1))
        assertFalse(MotionMath.same(null, a))
    }
}
