package com.mediahro.mediahro.testing

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.mediahro.mediahro.platform.sftp.SftpModule
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.util.Base64
import java.util.concurrent.atomic.AtomicInteger
import org.apache.sshd.common.config.keys.KeyUtils
import org.apache.sshd.common.file.virtualfs.VirtualFileSystemFactory
import org.apache.sshd.common.keyprovider.MappedKeyPairProvider
import org.apache.sshd.common.util.io.PathUtils
import org.apache.sshd.server.SshServer
import org.apache.sshd.sftp.server.SftpSubsystemFactory

/**
 * Debug-only SFTP server on 127.0.0.1 for the SftpFacade tests (lane C4a),
 * Apache MINA SSHD in debug builds only. `mediahro.test/sftp` takes `[op]`:
 * - `start`: a server rooted at `cache/sftp-test` with a fresh RSA host
 *   key; user `test` logs in with the password `s3cret-test` or the
 *   returned PKCS#8 key. Replies `{port, hostKeySha256, password,
 *   keyPem}`.
 * - `authAttempts`: authentication attempts the server saw.
 * - `stop`.
 */
internal object SftpHooks {
    private var server: SshServer? = null
    private val attempts = AtomicInteger()
    private const val USER = "test"
    private const val PASSWORD = "s3cret-test"

    fun install(context: Context, messenger: BinaryMessenger) {
        val main = Handler(Looper.getMainLooper())
        BasicMessageChannel(messenger, "mediahro.test/sftp", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                when ((message as List<*>)[0]) {
                    "start" -> Thread {
                        val result = runCatching { start(context) }.getOrElse { mapOf("error" to it.toString()) }
                        main.post { reply.reply(result) }
                    }.start()
                    "authAttempts" -> reply.reply(attempts.get())
                    "stop" -> {
                        stop()
                        reply.reply(true)
                    }
                    else -> reply.reply(null)
                }
            }
    }

    private fun rsa(): KeyPair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()

    private fun start(context: Context): Map<String, Any> {
        stop()
        attempts.set(0)
        val root = File(context.cacheDir, "sftp-test").apply {
            deleteRecursively()
            mkdirs()
        }
        File(root, "Films").mkdirs()
        File(root, "Films/clip.bin").writeBytes(ByteArray(100_000) { (it % 251).toByte() })
        // Android has no user home folder, which SSHD asks for (known_hosts, key lookup).
        PathUtils.setUserHomeFolderResolver { root.toPath() }
        val host = rsa()
        val client = rsa()
        val ssh = SshServer.setUpDefaultServer().apply {
            this.host = "127.0.0.1"
            port = 0
            keyPairProvider = MappedKeyPairProvider(host)
            setPasswordAuthenticator { user, password, _ ->
                attempts.incrementAndGet()
                user == USER && password == PASSWORD
            }
            setPublickeyAuthenticator { user, key, _ ->
                attempts.incrementAndGet()
                user == USER && KeyUtils.compareKeys(key, client.public)
            }
            subsystemFactories = listOf(SftpSubsystemFactory())
            fileSystemFactory = VirtualFileSystemFactory(root.toPath())
        }
        ssh.start()
        server = ssh
        val pem = "-----BEGIN PRIVATE KEY-----\n" +
            Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(client.private.encoded) +
            "\n-----END PRIVATE KEY-----\n"
        return mapOf(
            "port" to ssh.port,
            "hostKeySha256" to SftpModule.fingerprint(host.public),
            "password" to PASSWORD,
            "keyPem" to pem,
        )
    }

    private fun stop() {
        runCatching { server?.stop(true) }
        server = null
    }
}
