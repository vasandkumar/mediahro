package com.mediahro.mediahro.platform.tls

import android.net.InetAddresses
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.TlsEventKindMsg
import com.mediahro.mediahro.pigeon.TlsEventMsg
import com.mediahro.mediahro.pigeon.TlsEventsStreamHandler
import com.mediahro.mediahro.pigeon.TlsIdentityMsg
import com.mediahro.mediahro.pigeon.TlsListenerMsg
import com.mediahro.mediahro.pigeon.TlsServerHostApi
import com.mediahro.mediahro.pigeon.TlsSocketHostApi
import com.mediahro.mediahro.pigeon.TlsSocketInfoMsg
import java.io.IOException
import java.math.BigInteger
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.security.auth.x500.X500Principal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** One open connection, plain or TLS. */
internal class Conn(
    val id: String,
    val socket: Socket,
    val host: String,
    val port: Int,
    val context: SSLContext?,
    val info: TlsSocketInfoMsg,
    /** The peer was accepted by a user-confirmed pin, not the system CAs. */
    val pinned: Boolean = false,
) {
    @Volatile var reader: Thread? = null
    @Volatile var stopReading = false
    val writeLock = Any()
}

/**
 * Open connections and the one event channel that carries their data,
 * closes and accepted peers (lane C4a, ADR-017). Readers run on their own
 * threads; events are delivered on the main thread.
 */
internal object TlsHub {
    val conns = ConcurrentHashMap<String, Conn>()
    private val ids = AtomicLong(1)
    private val main = Handler(Looper.getMainLooper())

    @Volatile var sink: PigeonEventSink<TlsEventMsg>? = null

    val eventsHandler = object : TlsEventsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<TlsEventMsg>) {
            TlsHub.sink = sink
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }
    }

    fun nextId(prefix: String) = "$prefix${ids.getAndIncrement()}"

    fun emit(event: TlsEventMsg) {
        main.post { sink?.success(event) }
    }

    fun startReading(conn: Conn) {
        if (conn.reader != null) return
        conn.stopReading = false
        val thread = Thread({
            val buf = ByteArray(64 * 1024)
            val input = try {
                conn.socket.getInputStream()
            } catch (e: IOException) {
                emit(TlsEventMsg(TlsEventKindMsg.ERROR, conn.id, message = e.message))
                return@Thread
            }
            while (!conn.stopReading) {
                val n = try {
                    input.read(buf)
                } catch (e: SocketTimeoutException) {
                    continue // Plain sockets poll so an upgrade can pause them.
                } catch (e: IOException) {
                    if (!conn.stopReading) {
                        conns.remove(conn.id)
                        emit(TlsEventMsg(TlsEventKindMsg.ERROR, conn.id, message = e.message ?: "read failed"))
                    }
                    return@Thread
                }
                if (n < 0) {
                    conns.remove(conn.id)
                    emit(TlsEventMsg(TlsEventKindMsg.CLOSED, conn.id))
                    return@Thread
                }
                if (n > 0) emit(TlsEventMsg(TlsEventKindMsg.DATA, conn.id, data = buf.copyOf(n)))
            }
        }, "mediahro-tls-${conn.id}")
        thread.isDaemon = true
        conn.reader = thread
        thread.start()
    }

    /** Stops the reader without closing the socket (before an upgrade). */
    fun pauseReading(conn: Conn) {
        conn.stopReading = true
        conn.reader?.join(2_000)
        conn.reader = null
    }

    fun close(id: String) {
        val conn = conns.remove(id) ?: return
        conn.stopReading = true
        try {
            conn.socket.close()
        } catch (e: IOException) {
            // Already closed by the peer.
        }
    }

    fun closeAll() {
        conns.keys.toList().forEach(::close)
    }
}

internal object Tls {
    private val versions = arrayOf("TLSv1.3", "TLSv1.2")

    fun isIpLiteral(host: String): Boolean =
        if (Build.VERSION.SDK_INT >= 29) InetAddresses.isNumericAddress(host) else host.all { it.isDigit() || it == '.' || it == ':' }

    fun plainSocket(host: String, port: Int, timeoutMs: Int): Socket = Socket().apply {
        tcpNoDelay = true
        try {
            connect(InetSocketAddress(host, port), timeoutMs)
        } catch (e: IOException) {
            close()
            throw FlutterError("connectFailed", "$host:$port: ${e.message}")
        }
    }

    /**
     * TLS over an open [plain] socket. [peerHost]/[peerPort] are the session
     * cache key: passing another connection's values resumes its session
     * (FTPS data channels on the control session).
     */
    fun layer(
        context: SSLContext,
        plain: Socket,
        peerHost: String,
        peerPort: Int,
        serverName: String?,
        alpn: List<String>,
        timeoutMs: Int,
        versions: List<String> = this.versions.toList(),
        mutual: Boolean = false,
    ): SSLSocket {
        val ssl = context.socketFactory.createSocket(plain, peerHost, peerPort, true) as SSLSocket
        ssl.useClientMode = true
        ssl.enabledProtocols = versions.filter { it in ssl.supportedProtocols }.toTypedArray()
        // Mutual TLS: forward-secret AEAD suites only; no such suite is an SSLException, never a fallback.
        if (mutual) ssl.enabledCipherSuites = MutualTls.select(ssl.supportedCipherSuites)
        val params = ssl.sslParameters
        val sni = serverName ?: peerHost
        if (!isIpLiteral(sni)) params.serverNames = listOf(SNIHostName(sni))
        if (alpn.isNotEmpty() && Build.VERSION.SDK_INT >= 29) params.applicationProtocols = alpn.toTypedArray()
        ssl.sslParameters = params
        plain.soTimeout = timeoutMs
        ssl.startHandshake()
        plain.soTimeout = 0
        return ssl
    }

    fun info(id: String, socket: Socket): TlsSocketInfoMsg {
        val ssl = socket as? SSLSocket ?: return TlsSocketInfoMsg(id, false, "", "")
        val session = ssl.session
        val leaf = session.peerCertificates.firstOrNull() as? X509Certificate
        return TlsSocketInfoMsg(id, true, session.protocol ?: "", leaf?.let(Fingerprint::of) ?: "")
    }

    fun requireConn(id: String): Conn = TlsHub.conns[id] ?: throw FlutterError("closed", "No connection $id")
}

/**
 * TlsSocketFacade on Android (ADR-017, NET-004 FTPS, CAST-001): SSLSocket on
 * the OS TLS stack (Conscrypt), TLS 1.2 and 1.3 only, system CAs plus
 * hostname verification, or a user-confirmed fingerprint pin.
 */
class TlsSocketModule : TlsSocketHostApi {
    override suspend fun connect(
        host: String,
        port: Long,
        serverName: String?,
        pinnedSha256: String?,
        alpn: List<String>,
        timeoutMs: Long,
        resumeSessionOf: String?,
    ): TlsSocketInfoMsg = withContext(Dispatchers.IO) {
        val timeout = timeoutMs.toInt()
        val resume = resumeSessionOf?.let { TlsHub.conns[it] }?.takeIf { it.context != null }
        val trust = PinningTrustManager(pinnedSha256)
        val context = resume?.context ?: SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
        val plain = Tls.plainSocket(host, port.toInt(), timeout)
        // A resumed data channel trusts what its control connection trusted.
        val ssl = handshake(plain, trust, host, serverName, resume?.pinned == true) {
            Tls.layer(context, plain, resume?.host ?: host, resume?.port ?: port.toInt(), serverName ?: host, alpn, timeout)
        }
        register(ssl, host, port.toInt(), context, trust.acceptedByPin || resume?.pinned == true)
    }

    override suspend fun connectPlain(host: String, port: Long, timeoutMs: Long): TlsSocketInfoMsg =
        withContext(Dispatchers.IO) {
            val plain = Tls.plainSocket(host, port.toInt(), timeoutMs.toInt())
            // Short reads let `upgrade` pause the reader before the handshake.
            plain.soTimeout = PLAIN_POLL_MS
            register(plain, host, port.toInt(), null)
        }

    override suspend fun upgrade(connectionId: String, serverName: String?, pinnedSha256: String?): TlsSocketInfoMsg =
        withContext(Dispatchers.IO) {
            val conn = Tls.requireConn(connectionId)
            if (conn.context != null) throw FlutterError("alreadyTls", "Connection $connectionId is already TLS")
            TlsHub.pauseReading(conn)
            conn.socket.soTimeout = 0
            TlsHub.conns.remove(conn.id)
            val trust = PinningTrustManager(pinnedSha256)
            val context = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
            val ssl = handshake(conn.socket, trust, conn.host, serverName, false) {
                Tls.layer(context, conn.socket, conn.host, conn.port, serverName ?: conn.host, emptyList(), HANDSHAKE_MS)
            }
            register(ssl, conn.host, conn.port, context, trust.acceptedByPin)
        }

    /** Maps handshake failures; verifies the host name unless a pin accepted the peer. */
    private fun handshake(
        plain: Socket,
        trust: PinningTrustManager,
        host: String,
        serverName: String?,
        alreadyPinned: Boolean,
        block: () -> SSLSocket,
    ): SSLSocket {
        val ssl = try {
            block()
        } catch (e: SSLHandshakeException) {
            runCatching { plain.close() }
            trust.rejectedFingerprint?.let { throw FlutterError("untrusted", "Untrusted certificate for $host", it) }
            throw FlutterError("handshakeFailed", e.message)
        } catch (e: IOException) {
            runCatching { plain.close() }
            trust.rejectedFingerprint?.let { throw FlutterError("untrusted", "Untrusted certificate for $host", it) }
            throw FlutterError("handshakeFailed", e.message)
        }
        if (!trust.acceptedByPin && !alreadyPinned) {
            val name = serverName ?: host
            if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(name, ssl.session)) {
                val fp = (ssl.session.peerCertificates.firstOrNull() as? X509Certificate)?.let(Fingerprint::of)
                runCatching { ssl.close() }
                throw FlutterError("untrusted", "Certificate does not match $name", fp)
            }
        }
        return ssl
    }

    private fun register(socket: Socket, host: String, port: Int, context: SSLContext?, pinned: Boolean = false): TlsSocketInfoMsg {
        val id = TlsHub.nextId("t")
        val info = Tls.info(id, socket)
        TlsHub.conns[id] = Conn(id, socket, host, port, context, info, pinned)
        return info
    }

    override fun startReading(socketId: String) = TlsHub.startReading(Tls.requireConn(socketId))

    override suspend fun write(socketId: String, data: ByteArray): Unit = withContext(Dispatchers.IO) {
        val conn = Tls.requireConn(socketId)
        try {
            synchronized(conn.writeLock) {
                val out = conn.socket.getOutputStream()
                out.write(data)
                out.flush()
            }
        } catch (e: IOException) {
            throw FlutterError("writeFailed", e.message)
        }
    }

    override suspend fun close(socketId: String) = withContext(Dispatchers.IO) { TlsHub.close(socketId) }

    companion object {
        private const val PLAIN_POLL_MS = 250
        private const val HANDSHAKE_MS = 15_000
    }
}

/**
 * TlsServerFacade on Android (NET-017, ADR-025): a device identity as a
 * Keystore EC P-256 key with its self-signed certificate (the key never
 * leaves the Keystore), mutual-TLS listeners that accept only paired
 * fingerprints, and mutual-TLS client connections pinned to a peer.
 */
class TlsServerModule : TlsServerHostApi {
    private val keystore: KeyStore by lazy { KeyStore.getInstance(KEYSTORE).apply { load(null) } }
    private val listeners = ConcurrentHashMap<String, Pair<SSLServerSocket, PeerSetTrustManager>>()

    internal fun alias(label: String) = "mediahro.tls.$label"

    @Synchronized
    internal fun ensureIdentity(label: String): Pair<PrivateKey, X509Certificate> {
        val alias = alias(label)
        if (!keystore.containsAlias(alias)) {
            val now = System.currentTimeMillis()
            val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(
                    KeyProperties.DIGEST_NONE,
                    KeyProperties.DIGEST_SHA256,
                    KeyProperties.DIGEST_SHA384,
                    KeyProperties.DIGEST_SHA512,
                )
                .setCertificateSubject(X500Principal("CN=Mediahro $label"))
                .setCertificateSerialNumber(BigInteger.valueOf(now))
                .setCertificateNotBefore(Date(now - DAY_MS))
                .setCertificateNotAfter(Date(now + 20 * 365 * DAY_MS))
                .build()
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE).apply {
                initialize(spec)
                generateKeyPair()
            }
        }
        val key = keystore.getKey(alias, null) as PrivateKey
        val cert = keystore.getCertificate(alias) as X509Certificate
        return key to cert
    }

    override suspend fun identity(label: String): TlsIdentityMsg = withContext(Dispatchers.IO) {
        TlsIdentityMsg(label, Fingerprint.of(ensureIdentity(label).second))
    }

    private fun mutualContext(label: String, trust: PeerSetTrustManager): SSLContext {
        val (key, cert) = ensureIdentity(label)
        return SSLContext.getInstance("TLS").apply {
            init(arrayOf(IdentityKeyManager(alias(label), key, arrayOf(cert))), arrayOf(trust), null)
        }
    }

    override suspend fun listen(label: String, trustedPeers: List<String>, port: Long): TlsListenerMsg =
        withContext(Dispatchers.IO) {
            val trust = PeerSetTrustManager(trustedPeers.toSet())
            val server = mutualContext(label, trust).serverSocketFactory.createServerSocket(port.toInt()) as SSLServerSocket
            server.needClientAuth = true
            try {
                server.enabledCipherSuites = MutualTls.select(server.supportedCipherSuites)
            } catch (e: IOException) {
                runCatching { server.close() }
                throw FlutterError("unavailable", e.message)
            }
            server.enabledProtocols = MutualTls.PROTOCOLS.filter { it in server.supportedProtocols }.toTypedArray()
            val id = TlsHub.nextId("l")
            listeners[id] = server to trust
            Thread({ acceptLoop(id, server) }, "mediahro-tls-listen-$id").apply {
                isDaemon = true
                start()
            }
            TlsListenerMsg(id, server.localPort.toLong())
        }

    private fun acceptLoop(listenerId: String, server: SSLServerSocket) {
        while (!server.isClosed) {
            val socket = try {
                server.accept() as SSLSocket
            } catch (e: IOException) {
                break
            }
            // Handshake off the accept thread; unpaired peers fail here.
            Thread({
                try {
                    socket.soTimeout = 15_000
                    socket.startHandshake()
                    socket.soTimeout = 0
                    val id = TlsHub.nextId("t")
                    val info = Tls.info(id, socket)
                    TlsHub.conns[id] = Conn(id, socket, socket.inetAddress.hostAddress ?: "", socket.port, null, info)
                    TlsHub.emit(TlsEventMsg(TlsEventKindMsg.ACCEPTED, id, listenerId = listenerId, accepted = info))
                } catch (e: IOException) {
                    runCatching { socket.close() }
                }
            }, "mediahro-tls-accept").apply {
                isDaemon = true
                start()
            }
        }
    }

    override fun setTrustedPeers(listenerId: String, trustedPeers: List<String>) {
        val (_, trust) = listeners[listenerId] ?: throw FlutterError("closed", "No listener $listenerId")
        trust.trusted = trustedPeers.toSet()
    }

    override suspend fun closeListener(listenerId: String) = withContext(Dispatchers.IO) {
        listeners.remove(listenerId)?.first?.let { runCatching { it.close() } }
        Unit
    }

    override suspend fun connectMutual(host: String, port: Long, label: String, peerSha256: String): TlsSocketInfoMsg =
        withContext(Dispatchers.IO) {
            val context = mutualContext(label, PeerSetTrustManager(setOf(peerSha256)))
            val plain = Tls.plainSocket(host, port.toInt(), 15_000)
            val ssl = try {
                Tls.layer(context, plain, host, port.toInt(), null, emptyList(), 15_000, MutualTls.PROTOCOLS, mutual = true)
            } catch (e: IOException) {
                runCatching { plain.close() }
                throw FlutterError("handshakeFailed", e.message)
            }
            val id = TlsHub.nextId("t")
            val info = Tls.info(id, ssl)
            TlsHub.conns[id] = Conn(id, ssl, host, port.toInt(), context, info)
            info
        }

    fun dispose() {
        listeners.values.forEach { runCatching { it.first.close() } }
        listeners.clear()
    }

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val DAY_MS = 24L * 60 * 60 * 1000
    }
}
