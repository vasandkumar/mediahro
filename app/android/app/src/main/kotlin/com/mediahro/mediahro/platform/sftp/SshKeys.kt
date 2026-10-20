package com.mediahro.mediahro.platform.sftp


import com.hierynomus.sshj.userauth.keyprovider.OpenSSHKeyV1KeyFile
import com.mediahro.mediahro.pigeon.FlutterError
import java.io.StringReader
import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.MessageDigest
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.RSAPrivateCrtKeySpec
import java.security.spec.RSAPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import net.schmizz.sshj.userauth.keyprovider.KeyPairWrapper
import net.schmizz.sshj.userauth.keyprovider.KeyProvider
import net.schmizz.sshj.userauth.keyprovider.PuTTYKeyFile
import net.schmizz.sshj.userauth.password.PasswordFinder
import net.schmizz.sshj.userauth.password.Resource

/**
 * SSH private keys without BouncyCastle (ADR-017): OpenSSH v1 keys
 * (RSA, ECDSA, Ed25519 where the device has Ed25519; encrypted with bcrypt
 * + AES) and PuTTY v2 through sshj, and the legacy PEM formats parsed here
 * on the JCA: PKCS#8, PKCS#1 RSA and SEC1 EC, optionally encrypted with the
 * OpenSSL key derivation (AES-128/192/256-CBC, DES-EDE3-CBC).
 */
internal object SshKeys {
    fun provider(text: String, passphrase: String?): KeyProvider {
        val pem = text.trim()
        val finder = passphrase?.let(::finderOf)
        return when {
            pem.contains("BEGIN OPENSSH PRIVATE KEY") ->
                OpenSSHKeyV1KeyFile().apply { init(pem, null, finder) }
            pem.startsWith("PuTTY-User-Key-File-2") ->
                PuTTYKeyFile().apply { init(StringReader(pem), finder) }
            pem.startsWith("PuTTY-User-Key-File-") ->
                throw FlutterError("unsupportedKey", "PuTTY v3 keys: export the key in OpenSSH format in PuTTYgen")
            else -> KeyPairWrapper(legacyPem(pem, passphrase))
        }
    }

    private fun finderOf(passphrase: String) = object : PasswordFinder {
        override fun reqPassword(resource: Resource<*>?): CharArray = passphrase.toCharArray()
        override fun shouldRetry(resource: Resource<*>?) = false
    }

    // ---- Legacy PEM.

    fun legacyPem(pem: String, passphrase: String?): KeyPair {
        val type = Regex("-----BEGIN ([A-Z ]+)-----").find(pem)?.groupValues?.get(1)
            ?: throw FlutterError("unsupportedKey", "Not a private key")
        val lines = pem.lines().map(String::trim).filter { it.isNotEmpty() && !it.startsWith("-----") }
        val headers = lines.filter { ':' in it }.associate { it.substringBefore(':').trim() to it.substringAfter(':').trim() }
        val body = java.util.Base64.getMimeDecoder().decode(lines.filterNot { ':' in it }.joinToString(""))
        val der = headers["DEK-Info"]?.let { decrypt(body, it, passphrase) } ?: body
        return when (type) {
            "PRIVATE KEY" -> pkcs8(der)
            "RSA PRIVATE KEY" -> rsaPkcs1(der)
            "EC PRIVATE KEY" -> sec1(der, null)
            "ENCRYPTED PRIVATE KEY" ->
                throw FlutterError("unsupportedKey", "Encrypted PKCS#8: convert with ssh-keygen -p -f key")
            else -> throw FlutterError("unsupportedKey", "Unsupported key type $type")
        }
    }

    /** OpenSSL's EVP_BytesToKey (MD5, one round) as used by encrypted PEM. */
    private fun decrypt(body: ByteArray, dekInfo: String, passphrase: String?): ByteArray {
        val pass = passphrase ?: throw FlutterError("keyPassphrase", "The key is encrypted")
        val (alg, ivHex) = dekInfo.split(',').map(String::trim).let { it[0] to it.getOrElse(1) { "" } }
        val iv = ivHex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val (transform, keyLen, keyAlg) = when (alg) {
            "AES-128-CBC" -> Triple("AES/CBC/PKCS5Padding", 16, "AES")
            "AES-192-CBC" -> Triple("AES/CBC/PKCS5Padding", 24, "AES")
            "AES-256-CBC" -> Triple("AES/CBC/PKCS5Padding", 32, "AES")
            "DES-EDE3-CBC" -> Triple("DESede/CBC/PKCS5Padding", 24, "DESede")
            else -> throw FlutterError("unsupportedKey", "Unsupported PEM cipher $alg")
        }
        val key = ByteArray(keyLen)
        var prev = ByteArray(0)
        var filled = 0
        while (filled < keyLen) {
            val md = MessageDigest.getInstance("MD5")
            md.update(prev)
            md.update(pass.toByteArray(Charsets.UTF_8))
            md.update(iv, 0, 8)
            prev = md.digest()
            val n = minOf(prev.size, keyLen - filled)
            System.arraycopy(prev, 0, key, filled, n)
            filled += n
        }
        return try {
            Cipher.getInstance(transform).run {
                init(Cipher.DECRYPT_MODE, SecretKeySpec(key, keyAlg), IvParameterSpec(iv))
                doFinal(body)
            }
        } catch (e: Exception) {
            throw FlutterError("keyPassphrase", "Wrong passphrase for the key")
        }
    }

    private fun pkcs8(der: ByteArray): KeyPair {
        val outer = Der(der).sequence()
        outer.integer()
        val algorithm = outer.sequence()
        val oid = algorithm.oid()
        return when (oid) {
            RSA_OID -> {
                val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(der)) as RSAPrivateCrtKey
                KeyPair(KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(key.modulus, key.publicExponent)), key)
            }
            EC_OID -> sec1(outer.octets(), algorithm.oid())
            else -> throw FlutterError("unsupportedKey", "Unsupported PKCS#8 key $oid")
        }
    }

    private fun rsaPkcs1(der: ByteArray): KeyPair {
        val s = Der(der).sequence()
        s.integer()
        val n = s.integer()
        val e = s.integer()
        val d = s.integer()
        val p = s.integer()
        val q = s.integer()
        val dp = s.integer()
        val dq = s.integer()
        val qi = s.integer()
        val kf = KeyFactory.getInstance("RSA")
        return KeyPair(kf.generatePublic(RSAPublicKeySpec(n, e)), kf.generatePrivate(RSAPrivateCrtKeySpec(n, e, d, p, q, dp, dq, qi)))
    }

    /** SEC1 ECPrivateKey; [curveOid] from PKCS#8 when the inner key omits it. */
    private fun sec1(der: ByteArray, curveOid: String?): KeyPair {
        val s = Der(der).sequence()
        s.integer()
        val d = BigInteger(1, s.octets())
        var oid = curveOid
        var point: ByteArray? = null
        while (s.hasMore()) {
            when (s.peekTag()) {
                0xA0 -> oid = s.explicit().oid()
                0xA1 -> point = s.explicit().bitString()
                else -> s.skip()
            }
        }
        val curve = when (oid) {
            "1.2.840.10045.3.1.7" -> "secp256r1"
            "1.3.132.0.34" -> "secp384r1"
            "1.3.132.0.35" -> "secp521r1"
            else -> throw FlutterError("unsupportedKey", "Unsupported EC curve $oid")
        }
        val params = AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec(curve)) }
            .getParameterSpec(ECParameterSpec::class.java)
        val w = if (point != null) {
            if (point[0].toInt() != 4) throw FlutterError("unsupportedKey", "Compressed EC points are not supported")
            val len = (point.size - 1) / 2
            ECPoint(BigInteger(1, point.copyOfRange(1, 1 + len)), BigInteger(1, point.copyOfRange(1 + len, point.size)))
        } else {
            // PKCS#8 from Java/Conscrypt often omits the public point.
            multiply(params, d)
        }
        val kf = KeyFactory.getInstance("EC")
        return KeyPair(kf.generatePublic(ECPublicKeySpec(w, params)), kf.generatePrivate(ECPrivateKeySpec(d, params)))
    }

    /** Q = d·G on a prime curve (affine double-and-add; the user's own key). */
    private fun multiply(params: ECParameterSpec, d: BigInteger): ECPoint {
        val field = params.curve.field as java.security.spec.ECFieldFp
        val p = field.p
        val a = params.curve.a
        fun add(q: ECPoint, r: ECPoint): ECPoint {
            if (q == ECPoint.POINT_INFINITY) return r
            if (r == ECPoint.POINT_INFINITY) return q
            val lambda = if (q.affineX == r.affineX) {
                if ((q.affineY + r.affineY).mod(p) == BigInteger.ZERO) return ECPoint.POINT_INFINITY
                (q.affineX.pow(2).multiply(BigInteger.valueOf(3)) + a)
                    .multiply(q.affineY.shiftLeft(1).modInverse(p)).mod(p)
            } else {
                (r.affineY - q.affineY).multiply((r.affineX - q.affineX).modInverse(p)).mod(p)
            }
            val x = (lambda.pow(2) - q.affineX - r.affineX).mod(p)
            val y = (lambda.multiply(q.affineX - x) - q.affineY).mod(p)
            return ECPoint(x, y)
        }
        var result = ECPoint.POINT_INFINITY
        var addend = params.generator
        for (i in 0 until d.bitLength()) {
            if (d.testBit(i)) result = add(result, addend)
            addend = add(addend, addend)
        }
        return result
    }

    private const val RSA_OID = "1.2.840.113549.1.1.1"
    private const val EC_OID = "1.2.840.10045.2.1"
}

/** A minimal DER reader for the key structures above. */
internal class Der(private val bytes: ByteArray, private var pos: Int = 0, private val end: Int = bytes.size) {
    fun hasMore() = pos < end

    fun peekTag(): Int = bytes[pos].toInt() and 0xFF

    private fun header(expected: Int?): Pair<Int, Int> {
        val tag = bytes[pos++].toInt() and 0xFF
        if (expected != null && tag != expected) throw FlutterError("unsupportedKey", "Malformed key (tag $tag)")
        var len = bytes[pos++].toInt() and 0xFF
        if (len and 0x80 != 0) {
            val n = len and 0x7F
            len = 0
            repeat(n) { len = (len shl 8) or (bytes[pos++].toInt() and 0xFF) }
        }
        return pos to len
    }

    private fun take(tag: Int): ByteArray {
        val (start, len) = header(tag)
        pos = start + len
        return bytes.copyOfRange(start, start + len)
    }

    fun sequence(): Der {
        val (start, len) = header(0x30)
        pos = start + len
        return Der(bytes, start, start + len)
    }

    fun explicit(): Der {
        val (start, len) = header(null)
        pos = start + len
        return Der(bytes, start, start + len)
    }

    fun integer(): BigInteger = BigInteger(take(0x02))

    fun octets(): ByteArray = take(0x04)

    fun bitString(): ByteArray = take(0x03).let { it.copyOfRange(1, it.size) }

    fun skip() {
        val (start, len) = header(null)
        pos = start + len
    }

    fun oid(): String {
        val b = take(0x06)
        val parts = ArrayList<Long>()
        parts += (b[0].toInt() and 0xFF) / 40L
        parts += (b[0].toInt() and 0xFF) % 40L
        var v = 0L
        for (i in 1 until b.size) {
            v = (v shl 7) or (b[i].toLong() and 0x7F)
            if (b[i].toInt() and 0x80 == 0) {
                parts += v
                v = 0
            }
        }
        return parts.joinToString(".")
    }
}
