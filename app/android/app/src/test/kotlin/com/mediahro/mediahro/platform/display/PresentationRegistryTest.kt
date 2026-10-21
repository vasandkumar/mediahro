package com.mediahro.mediahro.platform.display

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PresentationRegistryTest {
    @Test
    fun `IMG-012 a presentation closes once, however often it is asked`() {
        val r = PresentationRegistry()
        var closed = 0
        val id = r.add("2") { closed++ }
        assertTrue(r.contains(id))
        assertEquals("2", r.displayOf(id))
        assertTrue(r.close(id))
        assertFalse(r.close(id))
        assertEquals(1, closed)
        assertFalse(r.contains(id))
    }

    @Test
    fun `IMG-012 removing a display closes only the presentations on it`() {
        val r = PresentationRegistry()
        val closedOn = mutableListOf<String>()
        val a = r.add("2") { closedOn += "2a" }
        val b = r.add("2") { closedOn += "2b" }
        val c = r.add("3") { closedOn += "3" }
        assertEquals(listOf(a, b), r.closeForDisplay("2"))
        assertEquals(listOf("2a", "2b"), closedOn)
        assertTrue(r.contains(c))
        assertEquals(1, r.count)
        // Removing the same display again, or an unknown one, closes nothing more.
        assertEquals(emptyList<Long>(), r.closeForDisplay("2"))
        assertEquals(emptyList<Long>(), r.closeForDisplay("9"))
        assertEquals(listOf("2a", "2b"), closedOn)
    }

    @Test
    fun `IMG-012 the engine going away closes everything`() {
        val r = PresentationRegistry()
        var closed = 0
        repeat(3) { r.add("${it + 2}") { closed++ } }
        r.closeAll()
        assertEquals(3, closed)
        assertEquals(0, r.count)
        r.closeAll()
        assertEquals(3, closed)
    }

    @Test
    fun `IMG-012 a failing close still removes the entry and does not stop the others`() {
        val r = PresentationRegistry()
        var closed = 0
        r.add("2") { throw IllegalStateException("window gone") }
        r.add("2") { closed++ }
        assertEquals(2, r.closeForDisplay("2").size)
        assertEquals(1, closed)
        assertEquals(0, r.count)
    }

    @Test
    fun `IMG-012 opening on a display that has a presentation replaces it, one engine per display`() {
        val r = PresentationRegistry()
        val order = mutableListOf<String>()
        val first = r.add("2") { order += "close first" }
        // What open() does: close what is on the display, then start the new one.
        r.closeForDisplay("2")
        order += "start second"
        val second = r.add("2") { order += "close second" }
        assertEquals(listOf("close first", "start second"), order)
        assertFalse(r.contains(first))
        assertTrue(r.contains(second))
        assertEquals(1, r.count)
        // Another display is not touched.
        val other = r.add("3") {}
        r.closeForDisplay("2")
        assertTrue(r.contains(other))
        assertEquals(1, r.count)
    }

    @Test
    fun `IMG-012 ids are not reused`() {
        val r = PresentationRegistry()
        val a = r.add("2") {}
        r.close(a)
        val b = r.add("2") {}
        assertTrue(b > a)
    }
}
