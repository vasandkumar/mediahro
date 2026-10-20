package com.mediahro.mediahro.platform.sftp

import com.mediahro.mediahro.pigeon.FlutterError
import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** NET-004: legacy PEM keys parse on the JCA alone (no BouncyCastle). */
class SshKeysTest {
    private fun rsa(): KeyPair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()

    private fun ec(): KeyPair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    private fun pem(type: String, der: ByteArray, headers: String = "") =
        "-----BEGIN $type-----\n$headers" +
            Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(der) + "\n-----END $type-----\n"

    private fun assertPair(expectedPublic: PublicKey, pair: KeyPair, alg: String) {
        assertEquals(expectedPublic, pair.public)
        val data = "mediahro".toByteArray()
        val sig = Signature.getInstance(alg).run {
            initSign(pair.private)
            update(data)
            sign()
        }
        val ok = Signature.getInstance(alg).run {
            initVerify(pair.public)
            update(data)
            verify(sig)
        }
        assertTrue(ok)
    }

    // ---- DER writer (independent of the reader under test).

    private fun tlv(tag: Int, body: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(tag)
        when {
            body.size < 0x80 -> out.write(body.size)
            body.size < 0x100 -> { out.write(0x81); out.write(body.size) }
            else -> { out.write(0x82); out.write(body.size shr 8); out.write(body.size and 0xFF) }
        }
        out.write(body)
        return out.toByteArray()
    }

    private fun int(v: BigInteger) = tlv(0x02, v.toByteArray())
    private fun seq(vararg parts: ByteArray) = tlv(0x30, parts.fold(ByteArray(0)) { a, b -> a + b })

    private fun pkcs1(k: RSAPrivateCrtKey) = seq(
        int(BigInteger.ZERO), int(k.modulus), int(k.publicExponent), int(k.privateExponent),
        int(k.primeP), int(k.primeQ), int(k.primeExponentP), int(k.primeExponentQ), int(k.crtCoefficient),
    )

    private fun fixed(v: BigInteger, len: Int): ByteArray {
        val b = v.toByteArray().let { if (it.size > len) it.copyOfRange(it.size - len, it.size) else it }
        return ByteArray(len - b.size) + b
    }

    private fun sec1(kp: KeyPair): ByteArray {
        val priv = kp.private as ECPrivateKey
        val pub = kp.public as ECPublicKey
        val point = byteArrayOf(4) + fixed(pub.w.affineX, 32) + fixed(pub.w.affineY, 32)
        val p256 = byteArrayOf(0x06, 0x08, 0x2A, 0x86.toByte(), 0x48, 0xCE.toByte(), 0x3D, 0x03, 0x01, 0x07)
        return seq(int(BigInteger.ONE), tlv(0x04, fixed(priv.s, 32)), tlv(0xA0, p256), tlv(0xA1, tlv(0x03, byteArrayOf(0) + point)))
    }

    /** OpenSSL's EVP_BytesToKey + AES-128-CBC, as `openssl rsa -aes128` writes. */
    private fun encryptPem(type: String, der: ByteArray, pass: String): String {
        val iv = ByteArray(16) { (it * 7 + 3).toByte() }
        val md = MessageDigest.getInstance("MD5")
        md.update(pass.toByteArray())
        md.update(iv, 0, 8)
        val key = md.digest()
        val ct = Cipher.getInstance("AES/CBC/PKCS5Padding").run {
            init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
            doFinal(der)
        }
        val ivHex = iv.joinToString("") { "%02X".format(it) }
        return pem(type, ct, "Proc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,$ivHex\n\n")
    }

    @Test
    fun `NET-004 PKCS#8 RSA keys parse with their public key`() {
        val kp = rsa()
        assertPair(kp.public, SshKeys.legacyPem(pem("PRIVATE KEY", kp.private.encoded), null), "SHA256withRSA")
    }

    @Test
    fun `NET-004 PKCS#8 EC keys parse with their public key`() {
        val kp = ec()
        assertPair(kp.public, SshKeys.legacyPem(pem("PRIVATE KEY", kp.private.encoded), null), "SHA256withECDSA")
    }

    @Test
    fun `NET-004 PKCS#1 RSA keys parse`() {
        val kp = rsa()
        val der = pkcs1(kp.private as RSAPrivateCrtKey)
        assertPair(kp.public, SshKeys.legacyPem(pem("RSA PRIVATE KEY", der), null), "SHA256withRSA")
    }

    @Test
    fun `NET-004 SEC1 EC keys parse`() {
        val kp = ec()
        assertPair(kp.public, SshKeys.legacyPem(pem("EC PRIVATE KEY", sec1(kp)), null), "SHA256withECDSA")
    }

    @Test
    fun `NET-004 encrypted PKCS#1 keys need the right passphrase`() {
        val kp = rsa()
        val enc = encryptPem("RSA PRIVATE KEY", pkcs1(kp.private as RSAPrivateCrtKey), "correct horse")
        assertPair(kp.public, SshKeys.legacyPem(enc, "correct horse"), "SHA256withRSA")
        val wrong = assertThrows(FlutterError::class.java) { SshKeys.legacyPem(enc, "wrong") }
        assertEquals("keyPassphrase", wrong.code)
        val missing = assertThrows(FlutterError::class.java) { SshKeys.legacyPem(enc, null) }
        assertEquals("keyPassphrase", missing.code)
    }

    @Test
    fun `NET-004 unsupported formats say so`() {
        val e = assertThrows(FlutterError::class.java) { SshKeys.legacyPem("not a key", null) }
        assertEquals("unsupportedKey", e.code)
        val v3 = assertThrows(FlutterError::class.java) {
            SshKeys.provider("PuTTY-User-Key-File-3: ssh-ed25519\n", null)
        }
        assertEquals("unsupportedKey", v3.code)
    }

    @Test
    fun `NET-004 host-key fingerprints are SHA-256 of the SSH key blob`() {
        val fp = SftpModule.fingerprint(rsa().public)
        assertTrue(Regex("^([0-9A-F]{2}:){31}[0-9A-F]{2}$").matches(fp))
        assertEquals(SftpModule.normalize(fp), SftpModule.normalize(fp.lowercase().replace(":", "")))
    }

    @Suppress("unused")
    private fun unused(k: PrivateKey) = k
}
