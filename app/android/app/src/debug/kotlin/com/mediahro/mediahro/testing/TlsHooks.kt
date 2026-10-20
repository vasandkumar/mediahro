package com.mediahro.mediahro.testing

import com.mediahro.mediahro.platform.tls.IdentityKeyManager
import com.mediahro.mediahro.platform.tls.TlsServerModule
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.Collections
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket

/**
 * Debug-only TLS test servers on 127.0.0.1 for the TlsSocketFacade tests
 * (lane C4a), `mediahro.test/tls` taking `[op]`:
 * - `start`: a self-signed TLS echo server (Keystore identity
 *   `test-server`, no client auth) and a plain line server that answers
 *   `AUTH TLS` with `234` and switches to TLS (FTPS explicit). Replies
 *   `{tlsPort, starttlsPort, sha256}`.
 * - `sessions`: server-side session ids (hex) of accepted TLS handshakes.
 * - `stop`.
 */
internal object TlsHooks {
    private var tlsServer: SSLServerSocket? = null
    private var plainServer: ServerSocket? = null
    private val sessions = Collections.synchronizedList(ArrayList<String>())

    fun install(messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/tls", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                when ((message as List<*>)[0]) {
                    "start" -> Thread {
                        val result = start()
                        android.os.Handler(android.os.Looper.getMainLooper()).post { reply.reply(result) }
                    }.start()
                    "sessions" -> reply.reply(ArrayList(sessions))
                    "stop" -> {
                        stop()
                        reply.reply(true)
                    }
                    else -> reply.reply(null)
                }
            }
    }

    private fun start(): Map<String, Any> {
        stop()
        val module = TlsServerModule()
        val (key, cert) = module.ensureIdentity("test-server")
        val context = SSLContext.getInstance("TLS").apply {
            init(arrayOf(IdentityKeyManager(module.alias("test-server"), key, arrayOf(cert))), null, null)
        }
        val loopback = InetAddress.getByName("127.0.0.1")
        val tls = context.serverSocketFactory.createServerSocket(0, 8, loopback) as SSLServerSocket
        tlsServer = tls
        daemon {
            while (!tls.isClosed) {
                val s = try {
                    tls.accept() as SSLSocket
                } catch (e: IOException) {
                    break
                }
                daemon { echo(s) }
            }
        }
        val plain = ServerSocket(0, 8, loopback)
        plainServer = plain
        daemon {
            while (!plain.isClosed) {
                val s = try {
                    plain.accept()
                } catch (e: IOException) {
                    break
                }
                daemon { startTls(s, context) }
            }
        }
        return mapOf(
            "tlsPort" to tls.localPort,
            "starttlsPort" to plain.localPort,
            "sha256" to com.mediahro.mediahro.platform.tls.Fingerprint.of(cert),
        )
    }

    private fun echo(socket: Socket) {
        try {
            if (socket is SSLSocket) {
                socket.startHandshake()
                sessions += socket.session.id.joinToString("") { "%02x".format(it) }
            }
            val input = socket.getInputStream()
            val output = socket.getOutputStream()
            val buf = ByteArray(16 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                output.write(buf, 0, n)
                output.flush()
            }
        } catch (e: IOException) {
            // Client went away.
        } finally {
            runCatching { socket.close() }
        }
    }

    /** Reads one line; on `AUTH TLS` answers 234 and continues as TLS. */
    private fun startTls(socket: Socket, context: SSLContext) {
        try {
            val input = socket.getInputStream()
            val line = StringBuilder()
            while (true) {
                val c = input.read()
                if (c < 0) return
                if (c == '\n'.code) break
                line.append(c.toChar())
            }
            if (line.toString().trim() != "AUTH TLS") {
                socket.getOutputStream().write("500 expected AUTH TLS\r\n".toByteArray())
                return
            }
            socket.getOutputStream().apply {
                write("234 AUTH TLS ok\r\n".toByteArray())
                flush()
            }
            val ssl = context.socketFactory.createSocket(socket, "127.0.0.1", socket.port, true) as SSLSocket
            ssl.useClientMode = false
            echo(ssl)
        } catch (e: IOException) {
            runCatching { socket.close() }
        }
    }

    private fun stop() {
        runCatching { tlsServer?.close() }
        runCatching { plainServer?.close() }
        tlsServer = null
        plainServer = null
        sessions.clear()
    }

    private fun daemon(block: () -> Unit) = Thread(block).apply {
        isDaemon = true
        start()
    }
}
