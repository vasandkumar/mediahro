package com.mediahro.mediahro.platform.sftp

import com.hierynomus.sshj.key.KeyAlgorithms
import com.hierynomus.sshj.transport.cipher.BlockCiphers
import com.hierynomus.sshj.transport.cipher.GcmCiphers
import com.hierynomus.sshj.transport.kex.DHGroups
import com.hierynomus.sshj.transport.kex.ExtInfoClientFactory
import com.hierynomus.sshj.transport.kex.ExtendedDHGroups
import com.hierynomus.sshj.transport.mac.Macs
import com.hierynomus.sshj.userauth.keyprovider.OpenSSHKeyV1KeyFile
import java.security.Signature
import javax.crypto.KeyAgreement
import net.schmizz.keepalive.KeepAliveProvider
import net.schmizz.sshj.ConfigImpl
import net.schmizz.sshj.common.Factory
import net.schmizz.sshj.common.LoggerFactory
import net.schmizz.sshj.transport.cipher.Cipher
import net.schmizz.sshj.transport.compression.NoneCompression
import net.schmizz.sshj.transport.kex.Curve25519SHA256
import net.schmizz.sshj.transport.kex.DHGexSHA256
import net.schmizz.sshj.transport.kex.ECDHNistP
import net.schmizz.sshj.transport.random.JCERandom
import net.schmizz.sshj.transport.random.SingletonRandomFactory
import net.schmizz.sshj.userauth.keyprovider.PuTTYKeyFile
import org.slf4j.Logger
import org.slf4j.helpers.NOPLogger

/**
 * sshj on the platform JCA only (ADR-017): no BouncyCastle on the class
 * path, and only algorithms the device's providers (Conscrypt) implement.
 * Curve25519 key exchange and Ed25519 keys are offered when the device's
 * JCA has X25519 / Ed25519; otherwise ECDH/ECDSA (NIST curves), DH groups
 * and RSA-SHA2 cover every mainstream server.
 */
internal class JcaSshConfig : ConfigImpl() {
    init {
        // `DefaultConfig` sets sshj's logger factory; a bare `ConfigImpl` leaves it null
        // and `SSHClient` fails with a NullPointerException. sshj must never log (host
        // names, user names and key exchange details), so it gets loggers that drop everything.
        loggerFactory = NoLogs
        version = "Mediahro"
        keepAliveProvider = KeepAliveProvider.KEEP_ALIVE
        randomFactory = SingletonRandomFactory(JCERandom.Factory())
        compressionFactories = listOf(NoneCompression.Factory())

        val kex = ArrayList<Factory.Named<net.schmizz.sshj.transport.kex.KeyExchange>>()
        if (hasX25519) {
            kex += Curve25519SHA256.Factory()
            kex += Curve25519SHA256.FactoryLibSsh()
        }
        kex += listOf(
            ECDHNistP.Factory521(),
            ECDHNistP.Factory384(),
            ECDHNistP.Factory256(),
            DHGexSHA256.Factory(),
            DHGroups.Group18SHA512(),
            DHGroups.Group16SHA512(),
            DHGroups.Group14SHA256(),
            ExtendedDHGroups.Group14SHA256AtSSH(),
            ExtendedDHGroups.Group16SHA512AtSSH(),
            ExtendedDHGroups.Group18SHA512AtSSH(),
            DHGroups.Group14SHA1(),
            ExtInfoClientFactory(),
        )
        keyExchangeFactories = kex

        val keys = ArrayList<Factory.Named<com.hierynomus.sshj.key.KeyAlgorithm>>()
        if (hasEd25519) {
            keys += KeyAlgorithms.EdDSA25519CertV01()
            keys += KeyAlgorithms.EdDSA25519()
        }
        keys += listOf(
            KeyAlgorithms.ECDSASHANistp521CertV01(),
            KeyAlgorithms.ECDSASHANistp521(),
            KeyAlgorithms.ECDSASHANistp384CertV01(),
            KeyAlgorithms.ECDSASHANistp384(),
            KeyAlgorithms.ECDSASHANistp256CertV01(),
            KeyAlgorithms.ECDSASHANistp256(),
            KeyAlgorithms.RSASHA512(),
            KeyAlgorithms.RSASHA256(),
            KeyAlgorithms.SSHRSACertV01(),
            KeyAlgorithms.SSHRSA(),
        )
        keyAlgorithms = keys

        cipherFactories = listOf(
            GcmCiphers.AES256GCM(),
            GcmCiphers.AES128GCM(),
            BlockCiphers.AES256CTR(),
            BlockCiphers.AES192CTR(),
            BlockCiphers.AES128CTR(),
            BlockCiphers.AES256CBC(),
            BlockCiphers.AES192CBC(),
            BlockCiphers.AES128CBC(),
        ).filter(::works)

        macFactories = listOf(
            Macs.HMACSHA2512Etm(),
            Macs.HMACSHA2256Etm(),
            Macs.HMACSHA2512(),
            Macs.HMACSHA2256(),
            Macs.HMACSHA1Etm(),
            Macs.HMACSHA1(),
        )

        fileKeyProviderFactories = listOf(OpenSSHKeyV1KeyFile.Factory(), PuTTYKeyFile.Factory())
    }

    /** A cipher is offered only if the device can initialise it. */
    private fun works(factory: Factory.Named<Cipher>): Boolean = try {
        val c = factory.create()
        c.init(Cipher.Mode.Encrypt, ByteArray(c.blockSize), ByteArray(c.ivSize))
        true
    } catch (e: Exception) {
        false
    }

    companion object {
        val hasX25519: Boolean by lazy { runCatching { KeyAgreement.getInstance("X25519") }.isSuccess }
        val hasEd25519: Boolean by lazy { runCatching { Signature.getInstance("Ed25519") }.isSuccess }
    }
}

/** Loggers that discard everything: sshj logs hosts, user names and algorithms, and the app logs none of it. */
internal object NoLogs : LoggerFactory {
    override fun getLogger(name: String?): Logger = NOPLogger.NOP_LOGGER

    override fun getLogger(clazz: Class<*>?): Logger = NOPLogger.NOP_LOGGER
}
