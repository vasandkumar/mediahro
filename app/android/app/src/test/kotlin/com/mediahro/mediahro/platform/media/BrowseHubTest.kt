package com.mediahro.mediahro.platform.media

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class BrowseHubTest {
    @Test
    fun `MUS-013 a car request gives up when Dart never registers a provider`() = runBlocking {
        BrowseHub.reset()
        assertFalse(BrowseHub.registered)
        assertNull(BrowseHub.current())
        assertNull(BrowseHub.await(timeoutMs = 50))
    }

    @Test
    fun `MUS-013 reset clears the provider of a destroyed engine`() {
        BrowseHub.reset()
        BrowseHub.registered = true // no engine yet: nothing to register
        assertFalse(BrowseHub.registered)
        assertNull(BrowseHub.flutter)
    }
}
