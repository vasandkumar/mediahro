package com.mediahro.mediahro.platform.sftp

import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.SftpEndpointMsg
import com.mediahro.mediahro.pigeon.SftpEntryMsg
import com.mediahro.mediahro.pigeon.SftpHostApi
import com.mediahro.mediahro.pigeon.SftpSessionMsg
import com.mediahro.mediahro.platform.security.SecureStorageModule
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.security.MessageDigest
import java.security.PublicKey
import java.util.EnumSet
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import net.schmizz.sshj.SSHClient
import net.schmizz.sshj.common.Buffer
import net.schmizz.sshj.sftp.FileAttributes
import net.schmizz.sshj.sftp.FileMode
import net.schmizz.sshj.sftp.OpenMode
import net.schmizz.sshj.sftp.RemoteFile
import net.schmizz.sshj.sftp.Response
import net.schmizz.sshj.sftp.SFTPClient
import net.schmizz.sshj.sftp.SFTPException
import net.schmizz.sshj.transport.TransportException
import net.schmizz.sshj.transport.verification.HostKeyVerifier
import net.schmizz.sshj.userauth.UserAuthException
import net.schmizz.sshj.userauth.method.AuthKeyboardInteractive
import net.schmizz.sshj.userauth.method.AuthMethod
import net.schmizz.sshj.userauth.method.AuthPassword
import net.schmizz.sshj.userauth.method.AuthPublickey
import net.schmizz.sshj.userauth.method.PasswordResponseProvider
import net.schmizz.sshj.userauth.password.PasswordFinder
import net.schmizz.sshj.userauth.password.Resource

/**
 * SftpFacade on Android (NET-004, ADR-017): sshj over the platform JCA
 * ([JcaSshConfig]). Secrets are read here from secure storage by their
 * references; their values never cross into Dart.
 *
 * Host keys: when the endpoint has no confirmed host key, or the server's
 * key differs, the session stops after the key exchange. Nothing is sent
 * and the session is unauthenticated; the caller shows the fingerprint and
 * connects again once the user confirms it.
 */
class SftpModule(private val secrets: SecureStorageModule) : SftpHostApi {
    private class Session(val ssh: SSHClient, val sftp: SFTPClient?, val hostKey: String) {
        val lock = Mutex()
        val open = LinkedHashMap<String, RemoteFile>(8, 0.75f, true)
    }

    private class Sink(val session: Session, val file: RemoteFile, var offset: Long, val path: String)

    private val sessions = ConcurrentHashMap<String, Session>()
    private val sinks = ConcurrentHashMap<String, Sink>()
    private val ids = AtomicLong(1)

    override suspend fun connect(endpoint: SftpEndpointMsg): SftpSessionMsg = withContext(Dispatchers.IO) {
        var seen: String? = null
        val ssh = SSHClient(JcaSshConfig())
        ssh.connectTimeout = TIMEOUT_MS
        ssh.timeout = TIMEOUT_MS
        ssh.addHostKeyVerifier(object : HostKeyVerifier {
            override fun verify(hostname: String?, port: Int, key: PublicKey): Boolean {
                seen = fingerprint(key)
                return true
            }

            override fun findExistingAlgorithms(hostname: String?, port: Int): List<String> = emptyList()
        })
        try {
            ssh.connect(endpoint.host, endpoint.port.toInt())
        } catch (e: Exception) {
            runCatching { ssh.close() }
            throw mapError(e)
        }
        val hostKey = seen ?: throw FlutterError("handshakeFailed", "No host key")
        val known = endpoint.knownHostKeySha256
        val confirmed = known != null && normalize(known) == normalize(hostKey)
        if (!confirmed) {
            // Unknown or changed key: stop before any credential is sent.
            runCatching { ssh.disconnect() }
            return@withContext SftpSessionMsg(register(Session(ssh, null, hostKey)), hostKey, false)
        }
        try {
            ssh.auth(endpoint.username, authMethods(endpoint))
            val sftp = ssh.newSFTPClient()
            SftpSessionMsg(register(Session(ssh, sftp, hostKey)), hostKey, true)
        } catch (e: Exception) {
            runCatching { ssh.disconnect() }
            throw mapError(e)
        }
    }

    private suspend fun authMethods(endpoint: SftpEndpointMsg): List<AuthMethod> {
        val methods = ArrayList<AuthMethod>()
        endpoint.privateKeySecretRef?.let { ref ->
            val key = secrets.read(ref) ?: throw FlutterError("missingSecret", "No private key stored for this source")
            val passphrase = endpoint.keyPassphraseSecretRef?.let { secrets.read(it) }
            methods += AuthPublickey(SshKeys.provider(key, passphrase))
        }
        endpoint.passwordSecretRef?.let { ref ->
            val password = secrets.read(ref) ?: throw FlutterError("missingSecret", "No password stored for this source")
            val finder = object : PasswordFinder {
                override fun reqPassword(resource: Resource<*>?): CharArray = password.toCharArray()
                override fun shouldRetry(resource: Resource<*>?) = false
            }
            methods += AuthPassword(finder)
            methods += AuthKeyboardInteractive(PasswordResponseProvider(finder))
        }
        if (methods.isEmpty()) throw FlutterError("missingSecret", "No password or key for this source")
        return methods
    }

    private fun register(session: Session): String {
        val id = "s${ids.getAndIncrement()}"
        sessions[id] = session
        return id
    }

    private suspend fun <T> withSftp(sessionId: String, op: (Session, SFTPClient) -> T): T = withContext(Dispatchers.IO) {
        val session = sessions[sessionId] ?: throw FlutterError("closed", "SFTP session $sessionId is closed")
        val sftp = session.sftp ?: throw FlutterError("notAuthenticated", "Confirm the host key first")
        session.lock.withLock {
            try {
                op(session, sftp)
            } catch (e: Exception) {
                throw mapError(e)
            }
        }
    }

    override suspend fun list(sessionId: String, path: String): List<SftpEntryMsg> = withSftp(sessionId) { _, sftp ->
        sftp.ls(path).filter { it.name != "." && it.name != ".." }.map { entry(it.path, it.attributes) }
    }

    override suspend fun stat(sessionId: String, path: String): SftpEntryMsg = withSftp(sessionId) { _, sftp ->
        entry(path, sftp.stat(path))
    }

    override suspend fun read(sessionId: String, path: String, offset: Long, length: Long): ByteArray =
        withSftp(sessionId) { session, sftp ->
            val file = session.open[path] ?: sftp.open(path, EnumSet.of(OpenMode.READ)).also {
                session.open[path] = it
                if (session.open.size > MAX_OPEN) {
                    val eldest = session.open.entries.first()
                    session.open.remove(eldest.key)
                    runCatching { eldest.value.close() }
                }
            }
            val buf = ByteArray(length.toInt())
            var read = 0
            while (read < buf.size) {
                val n = file.read(offset + read, buf, read, buf.size - read)
                if (n <= 0) break
                read += n
            }
            if (read == buf.size) buf else buf.copyOf(read)
        }

    override suspend fun rename(sessionId: String, from: String, to: String) = withSftp(sessionId) { session, sftp ->
        session.open.remove(from)?.let { runCatching { it.close() } }
        sftp.rename(from, to)
    }

    override suspend fun delete(sessionId: String, path: String) = withSftp(sessionId) { session, sftp ->
        session.open.remove(path)?.let { runCatching { it.close() } }
        if (sftp.stat(path).type == FileMode.Type.DIRECTORY) sftp.rmdir(path) else sftp.rm(path)
    }

    override suspend fun mkdir(sessionId: String, path: String) = withSftp(sessionId) { _, sftp -> sftp.mkdir(path) }

    override suspend fun openWrite(sessionId: String, path: String, truncate: Boolean): String =
        withSftp(sessionId) { session, sftp ->
            val modes = EnumSet.of(OpenMode.WRITE, OpenMode.CREAT)
            if (truncate) modes += OpenMode.TRUNC
            val file = sftp.open(path, modes)
            val offset = if (truncate) 0L else file.length()
            val id = "w${ids.getAndIncrement()}"
            sinks[id] = Sink(session, file, offset, path)
            id
        }

    override suspend fun write(sinkId: String, data: ByteArray) = withContext(Dispatchers.IO) {
        val sink = sinks[sinkId] ?: throw FlutterError("closed", "Write $sinkId is closed")
        sink.session.lock.withLock {
            try {
                sink.file.write(sink.offset, data, 0, data.size)
                sink.offset += data.size
            } catch (e: Exception) {
                throw mapError(e)
            }
        }
    }

    override suspend fun closeWrite(sinkId: String, abort: Boolean) = withContext(Dispatchers.IO) {
        val sink = sinks.remove(sinkId) ?: return@withContext
        sink.session.lock.withLock {
            try {
                sink.file.close()
                if (abort) sink.session.sftp?.rm(sink.path)
            } catch (e: Exception) {
                if (!abort) throw mapError(e)
            }
        }
    }

    override suspend fun close(sessionId: String) = withContext(Dispatchers.IO) {
        val session = sessions.remove(sessionId) ?: return@withContext
        sinks.entries.removeIf { it.value.session === session }
        session.open.values.forEach { runCatching { it.close() } }
        runCatching { session.sftp?.close() }
        runCatching { session.ssh.disconnect() }
        Unit
    }

    fun dispose() {
        sessions.values.forEach { runCatching { it.ssh.disconnect() } }
        sessions.clear()
        sinks.clear()
    }

    private fun entry(path: String, a: FileAttributes) = SftpEntryMsg(
        path = path,
        isDirectory = a.type == FileMode.Type.DIRECTORY,
        size = if (a.type == FileMode.Type.DIRECTORY) null else a.size,
        modifiedMs = a.mtime.takeIf { it > 0 }?.times(1000),
    )

    companion object {
        private const val TIMEOUT_MS = 20_000
        private const val MAX_OPEN = 8

        /** SHA-256 of the SSH public-key blob, as `AB:CD:…` (like TLS fingerprints). */
        fun fingerprint(key: PublicKey): String {
            val blob = Buffer.PlainBuffer().putPublicKey(key).compactData
            return MessageDigest.getInstance("SHA-256").digest(blob).joinToString(":") { "%02X".format(it) }
        }

        fun normalize(fp: String) = fp.replace(":", "").replace(" ", "").uppercase()

        fun mapError(e: Exception): Exception = when (e) {
            is FlutterError -> e
            is SFTPException -> when (e.statusCode) {
                Response.StatusCode.NO_SUCH_FILE, Response.StatusCode.NO_SUCH_PATH ->
                    FlutterError("notFound", e.message)
                Response.StatusCode.PERMISSION_DENIED -> FlutterError("permissionDenied", e.message)
                Response.StatusCode.FILE_ALREADY_EXISTS -> FlutterError("alreadyExists", e.message)
                Response.StatusCode.NO_SPACE_ON_FILESYSTEM, Response.StatusCode.QUOTA_EXCEEDED ->
                    FlutterError("noSpace", e.message)
                else -> FlutterError("io", e.message)
            }
            is UserAuthException -> FlutterError("authFailed", e.message)
            is SocketTimeoutException -> FlutterError("timeout", e.message)
            is UnknownHostException, is ConnectException -> FlutterError("connectFailed", e.message)
            is TransportException -> FlutterError("connectFailed", e.message)
            is IOException -> FlutterError("io", e.message)
            else -> FlutterError("io", e.message)
        }
    }
}
