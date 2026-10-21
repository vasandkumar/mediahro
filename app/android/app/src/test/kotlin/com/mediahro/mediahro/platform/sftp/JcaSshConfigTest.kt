package com.mediahro.mediahro.platform.sftp

import net.schmizz.sshj.SSHClient
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Test

class JcaSshConfigTest {
    @Test
    fun `NET-004 the sshj config has a logger factory, so an SSHClient can be made`() {
        val config = JcaSshConfig()
        assertNotNull(config.loggerFactory)
        // The batch 3 failure: a NullPointerException in SSHClient.<init> from a null factory.
        val client = SSHClient(config)
        assertNotNull(client)
        client.close()
    }

    @Test
    fun `NET-004 sshj loggers drop everything`() {
        val log = JcaSshConfig().loggerFactory.getLogger("net.schmizz.sshj.transport.TransportImpl")
        assertFalse(log.isInfoEnabled)
        assertFalse(log.isDebugEnabled)
        assertFalse(log.isTraceEnabled)
        assertFalse(log.isWarnEnabled)
        assertFalse(log.isErrorEnabled)
        // Never writes, whatever it is given.
        log.info("connected to {} as {}", "host.example", "user")
        log.error("auth failed for {}", "user", RuntimeException("x"))
        assertSame(log, JcaSshConfig().loggerFactory.getLogger(String::class.java))
    }
}
