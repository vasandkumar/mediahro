package com.mediahro.mediahro.platform.background

import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RunBrokerTest {
    private val delivered = CopyOnWriteArrayList<String>()
    private val broker = RunBroker { it() }

    /** Dart answering: listens, and completes each id it is handed. */
    private fun dart(success: Boolean) = broker.attach {
        delivered.add(it)
        broker.complete(it, success)
    }

    @Test
    fun `ADR-049 a run delivers the id and a success answer is true`() = runBlocking {
        dart(success = true)
        assertTrue(broker.run("pod.refresh", 2_000))
        assertEquals(listOf("pod.refresh"), delivered)
    }

    @Test
    fun `ADR-049 a failure answer is false, which the worker turns into a retry`() = runBlocking {
        dart(success = false)
        assertFalse(broker.run("pod.refresh", 2_000))
        assertEquals(listOf("pod.refresh"), delivered)
    }

    @Test
    fun `ADR-049 a run that starts before Dart listens waits for it`() = runBlocking {
        val run = async { broker.run("pod.refresh", 5_000) }
        delay(100)
        assertTrue(delivered.isEmpty())
        dart(success = true)
        assertTrue(run.await())
        assertEquals(listOf("pod.refresh"), delivered)
    }

    @Test
    fun `ADR-049 Dart never listening gives up after the timeout`() = runBlocking {
        assertFalse(broker.run("pod.refresh", 150))
        assertTrue(delivered.isEmpty())
    }

    @Test
    fun `ADR-049 Dart listening but never answering gives up after the timeout`() = runBlocking {
        broker.attach { delivered.add(it) }
        assertFalse(broker.run("pod.refresh", 150))
        assertEquals(listOf("pod.refresh"), delivered)
    }

    @Test
    fun `ADR-049 a late answer is ignored and does not answer the next run`() = runBlocking {
        broker.attach { delivered.add(it) }
        assertFalse(broker.run("pod.refresh", 100))
        broker.complete("pod.refresh", true) // the previous run's late answer
        val next = async { broker.run("pod.refresh", 150) }
        assertFalse(next.await())
    }

    @Test
    fun `ADR-049 an answer for another id does not finish a run`() = runBlocking {
        broker.attach {
            delivered.add(it)
            broker.complete("someone.else", true)
        }
        assertFalse(broker.run("pod.refresh", 150))
    }

    @Test
    fun `ADR-049 two jobs wait independently`() = runBlocking {
        broker.attach { delivered.add(it) }
        val a = async { broker.run("a", 3_000) }
        val b = async { broker.run("b", 3_000) }
        delay(100)
        broker.complete("b", false)
        broker.complete("a", true)
        assertTrue(a.await())
        assertFalse(b.await())
    }

    @Test
    fun `ADR-049 the engine going away fails the waiting runs`() = runBlocking {
        broker.attach { delivered.add(it) }
        val run = async { broker.run("pod.refresh", 5_000) }
        delay(100)
        broker.reset()
        assertFalse(run.await())
    }

    @Test
    fun `ADR-049 after Dart stops listening a run waits for the next listener`() = runBlocking {
        dart(success = true)
        broker.detach()
        val run = async { broker.run("pod.refresh", 5_000) }
        delay(100)
        assertTrue(delivered.isEmpty())
        dart(success = true)
        assertTrue(run.await())
    }

    @Test
    fun `ADR-049 a second run of the same id ends the first`() = runBlocking {
        broker.attach { delivered.add(it) }
        val first = async { broker.run("pod.refresh", 5_000) }
        delay(100)
        val second = async { broker.run("pod.refresh", 5_000) }
        delay(100)
        assertFalse(first.await())
        broker.complete("pod.refresh", true)
        assertTrue(second.await())
    }
}
