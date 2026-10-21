package com.mediahro.mediahro.platform.input

import com.mediahro.mediahro.pigeon.GamepadAxisMsg
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GamepadMathTest {
    @Test
    fun `SYS-009 drift inside the dead zone is zero and the rest is rescaled`() {
        assertEquals(0f, GamepadMath.deadZone(0.1f), 0f)
        assertEquals(0f, GamepadMath.deadZone(-0.15f), 0f)
        assertEquals(1f, GamepadMath.deadZone(1f), 1e-6f)
        assertEquals(-1f, GamepadMath.deadZone(-1f), 1e-6f)
        // Just past the zone starts near zero, not at 0.15.
        assertEquals(0.0118f, GamepadMath.deadZone(0.16f), 1e-3f)
        assertEquals(0.5f, GamepadMath.deadZone(0.575f), 1e-3f)
    }

    @Test
    fun `SYS-009 triggers are 0 to 1 with the same drift zone`() {
        assertEquals(0f, GamepadMath.trigger(0.1f), 0f)
        assertEquals(1f, GamepadMath.trigger(1f), 1e-6f)
        assertEquals(0.5f, GamepadMath.trigger(0.575f), 1e-3f)
        assertEquals(0f, GamepadMath.trigger(-0.3f), 0f)
    }

    @Test
    fun `SYS-009 the hat snaps to minus one, zero or one`() {
        assertEquals(1f, GamepadMath.hat(1f), 0f)
        assertEquals(-1f, GamepadMath.hat(-0.9f), 0f)
        assertEquals(0f, GamepadMath.hat(0.3f), 0f)
    }

    @Test
    fun `SYS-009 the layout follows the axes the controller has`() {
        val pad = GamepadMath.layout { it in setOf(GamepadMath.AXIS_RX, GamepadMath.AXIS_RY, GamepadMath.AXIS_LTRIGGER, GamepadMath.AXIS_RTRIGGER) }
        assertEquals(GamepadMath.AXIS_RX, pad.rightX)
        assertEquals(GamepadMath.AXIS_RY, pad.rightY)
        assertEquals(GamepadMath.AXIS_LTRIGGER, pad.leftTrigger)
        // An unknown device (an injected event has none) gets Z/RZ and LTRIGGER/RTRIGGER.
        val unknown = GamepadMath.layout { false }
        assertEquals(GamepadMath.AXIS_Z, unknown.rightX)
        assertEquals(GamepadMath.AXIS_RZ, unknown.rightY)
        assertEquals(GamepadMath.AXIS_LTRIGGER, unknown.leftTrigger)
        assertEquals(GamepadMath.AXIS_RTRIGGER, unknown.rightTrigger)
        assertEquals(GamepadMath.AXIS_HAT_X, unknown.hatX)
        // A pad that reports BRAKE/GAS and no LTRIGGER/RTRIGGER uses them.
        val brakeGas = GamepadMath.layout { it == GamepadMath.AXIS_BRAKE || it == GamepadMath.AXIS_GAS }
        assertEquals(GamepadMath.AXIS_BRAKE, brakeGas.leftTrigger)
        assertEquals(GamepadMath.AXIS_GAS, brakeGas.rightTrigger)
        // One that reports both keeps LTRIGGER/RTRIGGER.
        val both = GamepadMath.layout { it in setOf(GamepadMath.AXIS_BRAKE, GamepadMath.AXIS_LTRIGGER) }
        assertEquals(GamepadMath.AXIS_LTRIGGER, both.leftTrigger)
    }

    @Test
    fun `SYS-009 repeated and tiny changes are dropped, return to rest is sent`() {
        val c = GamepadMath.Changes()
        assertTrue(c.changed(1, GamepadAxisMsg.LEFT_X, 0.5f))
        assertFalse(c.changed(1, GamepadAxisMsg.LEFT_X, 0.505f))
        assertTrue(c.changed(1, GamepadAxisMsg.LEFT_X, 0.6f))
        assertTrue(c.changed(1, GamepadAxisMsg.LEFT_X, 0f))
        assertFalse(c.changed(1, GamepadAxisMsg.LEFT_X, 0f))
        // Another controller or axis is tracked on its own.
        assertTrue(c.changed(2, GamepadAxisMsg.LEFT_X, 0.5f))
        c.forget(2)
        assertTrue(c.changed(2, GamepadAxisMsg.LEFT_X, 0.5f))
    }
}
