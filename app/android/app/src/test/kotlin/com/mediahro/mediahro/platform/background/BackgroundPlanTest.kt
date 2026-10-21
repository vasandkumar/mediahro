package com.mediahro.mediahro.platform.background

import androidx.work.NetworkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundPlanTest {
    @Test
    fun `ADR-049 the interval is never under 15 minutes`() {
        assertEquals(15 * 60 * 1000L, BackgroundPlan.MIN_INTERVAL_MS)
        assertEquals(BackgroundPlan.MIN_INTERVAL_MS, BackgroundPlan.interval(0))
        assertEquals(BackgroundPlan.MIN_INTERVAL_MS, BackgroundPlan.interval(60_000))
        assertEquals(BackgroundPlan.MIN_INTERVAL_MS, BackgroundPlan.interval(-5))
        assertEquals(BackgroundPlan.MIN_INTERVAL_MS, BackgroundPlan.interval(BackgroundPlan.MIN_INTERVAL_MS))
        val sixHours = 6 * 60 * 60 * 1000L
        assertEquals(sixHours, BackgroundPlan.interval(sixHours))
    }

    @Test
    fun `ADR-049 an absurd interval is capped at a year`() {
        assertEquals(BackgroundPlan.MAX_INTERVAL_MS, BackgroundPlan.interval(Long.MAX_VALUE))
        assertEquals(BackgroundPlan.MAX_INTERVAL_MS, BackgroundPlan.interval(BackgroundPlan.MAX_INTERVAL_MS + 1))
    }

    @Test
    fun `ADR-049 unmetered wins over the network flag`() {
        assertEquals(NetworkType.UNMETERED, BackgroundPlan.network(requiresNetwork = true, unmeteredOnly = true))
        assertEquals(NetworkType.UNMETERED, BackgroundPlan.network(requiresNetwork = false, unmeteredOnly = true))
        assertEquals(NetworkType.CONNECTED, BackgroundPlan.network(requiresNetwork = true, unmeteredOnly = false))
        assertEquals(NetworkType.NOT_REQUIRED, BackgroundPlan.network(requiresNetwork = false, unmeteredOnly = false))
    }

    @Test
    fun `ADR-049 one id is one job and two ids are two`() {
        assertEquals(BackgroundPlan.uniqueName("pod.refresh"), BackgroundPlan.uniqueName("pod.refresh"))
        assertNotEquals(BackgroundPlan.uniqueName("pod.refresh"), BackgroundPlan.uniqueName("pod.other"))
        assertEquals("mediahro.bg.pod.refresh", BackgroundPlan.uniqueName("pod.refresh"))
    }

    @Test
    fun `ADR-049 a bad id is refused`() {
        assertThrows(IllegalArgumentException::class.java) { BackgroundPlan.uniqueName("") }
        assertThrows(IllegalArgumentException::class.java) { BackgroundPlan.uniqueName("   ") }
        assertThrows(IllegalArgumentException::class.java) { BackgroundPlan.uniqueName("a\nb") }
        assertThrows(IllegalArgumentException::class.java) { BackgroundPlan.uniqueName("x".repeat(129)) }
        BackgroundPlan.uniqueName("x".repeat(128))
    }

    @Test
    fun `ADR-049 the wait is shorter than the ten minutes the OS gives a worker`() {
        assertTrue(BackgroundPlan.RUN_TIMEOUT_MS < 10 * 60 * 1000L)
    }
}
