package com.mediahro.mediahro.platform.imaging

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ImagingMathTest {
    @Test
    fun `IMG-001 maxEdge scales the long edge and keeps the ratio`() {
        assertEquals(1000 to 500, ImagingMath.targetSize(4000, 2000, 1000))
        assertEquals(500 to 1000, ImagingMath.targetSize(2000, 4000, 1000))
        assertEquals(800 to 600, ImagingMath.targetSize(800, 600, 1000))
        assertEquals(800 to 600, ImagingMath.targetSize(800, 600, null))
    }

    @Test
    fun `IMG-001 a region in full pixels maps into the scaled image`() {
        // 4000x2000 decoded at 1000x500: a 400x200 box at (800, 400) becomes 100x50 at (200, 100).
        val c = ImagingMath.scaledRegion(800.0, 400.0, 1200.0, 600.0, 4000, 2000, 1000, 500)
        assertArrayEquals(intArrayOf(200, 100, 300, 150), c)
        // Out-of-bounds input is clamped and never empty.
        val edge = ImagingMath.scaledRegion(3999.0, 1999.0, 9000.0, 9000.0, 4000, 2000, 1000, 500)
        assertEquals(1000, edge[2])
        assertEquals(500, edge[3])
        assertTrue(edge[2] > edge[0] && edge[3] > edge[1])
    }

    @Test
    fun `IMG-002 gain map at zero keeps SDR white and at one reaches the max ratio`() {
        val p = ImagingMath.GainParams(ratioMin = 1f, ratioMax = 4f, gamma = 1f, epsilonSdr = 0f, epsilonHdr = 0f)
        assertEquals(1f, ImagingMath.applyGain(1f, 0f, p), 1e-4f)
        assertEquals(4f, ImagingMath.applyGain(1f, 1f, p), 1e-4f)
        // Halfway in log space is the geometric mean.
        assertEquals(2f, ImagingMath.applyGain(1f, 0.5f, p), 1e-4f)
    }

    @Test
    fun `IMG-002 sRGB to linear matches the transfer curve`() {
        assertEquals(0f, ImagingMath.srgbToLinear(0f), 1e-6f)
        assertEquals(1f, ImagingMath.srgbToLinear(1f), 1e-5f)
        assertEquals(0.2140f, ImagingMath.srgbToLinear(0.5f), 1e-3f)
    }

    @Test
    fun `IMG-002 half floats encode exact values, overflow and subnormals`() {
        assertEquals(0x3c00, ImagingMath.halfBits(1f))
        assertEquals(0x4000, ImagingMath.halfBits(2f))
        assertEquals(0xc000, ImagingMath.halfBits(-2f))
        assertEquals(0x3800, ImagingMath.halfBits(0.5f))
        assertEquals(0x0000, ImagingMath.halfBits(0f))
        assertEquals(0x7c00, ImagingMath.halfBits(1e9f))
        assertEquals(0x0001, ImagingMath.halfBits(5.9604645e-8f))
        assertEquals(0x7bff, ImagingMath.halfBits(65504f))
    }

    @Test
    fun `IMG-015 the print grid fills the page and keeps the cells apart`() {
        val one = ImagingMath.printGrid(1, 595f, 842f, 36f, 0f)
        assertEquals(1, one.size)
        assertEquals(523f, one[0].width, 0.01f)
        val four = ImagingMath.printGrid(4, 595f, 842f, 36f, 12f)
        assertEquals(4, four.size)
        for (a in four) for (b in four) {
            if (a === b) continue
            val overlapX = a.left < b.left + b.width && b.left < a.left + a.width
            val overlapY = a.top < b.top + b.height && b.top < a.top + a.height
            assertTrue(!(overlapX && overlapY))
        }
        for (c in four) {
            assertTrue(c.left >= 36f && c.left + c.width <= 595f - 36f + 0.01f)
            assertTrue(c.top >= 36f && c.top + c.height <= 842f - 36f + 0.01f)
        }
    }

    @Test
    fun `IMG-015 fit letterboxes and fill crops to the cell`() {
        val cell = ImagingMath.Cell(0f, 0f, 200f, 100f)
        // A square image fit into a wide cell: full source, centred 100x100 destination.
        val (src, dst) = ImagingMath.place(100, 100, cell, fill = false, captionH = 0f)
        assertArrayEquals(floatArrayOf(0f, 0f, 100f, 100f), src, 0.01f)
        assertArrayEquals(floatArrayOf(50f, 0f, 150f, 100f), dst, 0.01f)
        // Fill crops the source to the cell's ratio and covers the cell.
        val (fsrc, fdst) = ImagingMath.place(100, 100, cell, fill = true, captionH = 0f)
        assertArrayEquals(floatArrayOf(0f, 25f, 100f, 75f), fsrc, 0.01f)
        assertArrayEquals(floatArrayOf(0f, 0f, 200f, 100f), fdst, 0.01f)
        // A caption takes room from the bottom of the cell.
        val (_, withCaption) = ImagingMath.place(200, 100, cell, fill = false, captionH = 20f)
        assertEquals(80f, withCaption[3] - withCaption[1], 0.01f)
    }

    @Test
    fun `IMG-005 a face box is normalised and clamped to the image`() {
        val r = ImagingMath.faceRect(50f, 50f, 20f, 100, 100)
        assertTrue(r[0] in 0f..1f && r[1] in 0f..1f && r[2] in 0f..1f && r[3] in 0f..1f)
        assertTrue(r[2] > r[0] && r[3] > r[1])
        val edge = ImagingMath.faceRect(2f, 2f, 40f, 100, 100)
        assertEquals(0f, edge[0], 0f)
        assertEquals(0f, edge[1], 0f)
    }
}
