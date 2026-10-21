package com.mediahro.mediahro.platform.security

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.security.keystore.KeyInfo
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.ProviderException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource

/**
 * Android Keystore keys for secure storage and vault key wrapping (PRIV-006,
 * ADR-008). Keys are created in StrongBox when the device has one, otherwise
 * in the TEE; their material never leaves the Keystore.
 *
 * - [secretKey]: AES-256-GCM, no user authentication. Encrypts stored
 *   secrets and wraps vault keys that do not require the user.
 * - [authKeyPair]: RSA-2048 OAEP whose private key needs the user
 *   (biometric or device credential) for every use. Wrapping uses only the
 *   public key, so it needs no prompt; unwrapping goes through
 *   BiometricPrompt with a CryptoObject.
 */
internal class Keystore(private val context: Context) {
    private val store: KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    private val strongBox: Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)

    @Synchronized
    fun secretKey(alias: String): SecretKey {
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        fun spec(strong: Boolean) = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setIsStrongBoxBacked(strong)
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        return try {
            generator.init(spec(strongBox))
            generator.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            generator.init(spec(false))
            generator.generateKey()
        }
    }

    @Synchronized
    fun authKeyPair(alias: String): Pair<PublicKey, PrivateKey> {
        val existing = store.getEntry(alias, null) as? KeyStore.PrivateKeyEntry
        if (existing != null) return existing.certificate.publicKey to existing.privateKey
        fun spec(strong: Boolean): KeyGenParameterSpec {
            val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA1)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                .setUserAuthenticationRequired(true)
                // A new fingerprint must not open an existing vault.
                .setInvalidatedByBiometricEnrollment(true)
                .setIsStrongBoxBacked(strong)
            if (Build.VERSION.SDK_INT >= 30) {
                b.setUserAuthenticationParameters(
                    0,
                    KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
                )
            }
            return b.build()
        }
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER)
        val pair = try {
            generator.initialize(spec(strongBox))
            generator.generateKeyPair()
        } catch (e: StrongBoxUnavailableException) {
            generator.initialize(spec(false))
            generator.generateKeyPair()
        }
        return pair.public to pair.private
    }

    /**
     * The vault's HMAC-SHA-256 key (ADR-039 amendment 2): non-exportable, used
     * only to turn a fixed label into the 32 bytes of key material that
     * [com.mediahro.mediahro.platform.vault.Hkdf] mixes with a caller secret
     * when the Keystore AES master key (whose bytes can never be read) is the
     * master. Same device-unlocked rule as the AES key.
     */
    @Synchronized
    fun vaultHmacKey(alias: String): SecretKey {
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        fun spec(strong: Boolean) = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setUnlockedDeviceRequired(true)
            .setIsStrongBoxBacked(strong)
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, PROVIDER)
        return try {
            generator.init(spec(strongBox))
            generator.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            generator.init(spec(false))
            generator.generateKey()
        }
    }

    /** HMAC-SHA-256 of [data] under a Keystore HMAC key. */
    fun hmac(key: SecretKey, data: ByteArray): ByteArray =
        javax.crypto.Mac.getInstance("HmacSHA256").apply { init(key) }.doFinal(data)

    fun has(alias: String): Boolean = store.containsAlias(alias)

    /**
     * The vault's AES-256-GCM key (ADR-039): like [secretKey] but only usable
     * while the device is unlocked. Created once; use [has] to tell "never
     * created" from "gone".
     */
    @Synchronized
    fun vaultSecretKey(alias: String): SecretKey {
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        fun spec(strong: Boolean) = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUnlockedDeviceRequired(true)
            .setIsStrongBoxBacked(strong)
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        return try {
            generator.init(spec(strongBox))
            generator.generateKey()
        } catch (e: StrongBoxUnavailableException) {
            generator.init(spec(false))
            generator.generateKey()
        }
    }

    /**
     * The vault's RSA-OAEP key pair (ADR-039 amendment 1): its private key
     * needs a fresh **strong biometric** for every use and is invalidated when
     * biometrics change. (With the device credential also allowed, Android 11+
     * ignores that invalidation, so the vault key is fingerprint-only; the PIN
     * path is ADR-040's.) Tries StrongBox with SHA-256 only, then the TEE;
     * each attempt is checked with a public-key operation and replaced if the
     * Keystore refuses it. The existing [authKeyPair] is left alone.
     */
    @Synchronized
    fun vaultKeyPair(alias: String): Pair<PublicKey, PrivateKey> {
        val existing = store.getEntry(alias, null) as? KeyStore.PrivateKeyEntry
        if (existing != null) return existing.certificate.publicKey to existing.privateKey
        val attempts = buildList {
            if (strongBox) add(true to arrayOf(KeyProperties.DIGEST_SHA256))
            add(false to arrayOf(KeyProperties.DIGEST_SHA256))
            // Older Keystores authorise the OAEP MGF1-SHA-1 digest through the digest list.
            add(false to arrayOf(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA1))
        }
        var last: Exception? = null
        for ((strong, digests) in attempts) {
            try {
                val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_ENCRYPT)
                    .setKeySize(2048)
                    .setDigests(*digests)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true)
                    .setUnlockedDeviceRequired(true)
                    .setIsStrongBoxBacked(strong)
                if (Build.VERSION.SDK_INT >= 30) b.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, PROVIDER)
                generator.initialize(b.build())
                val pair = generator.generateKeyPair()
                checkOaepUsable(pair.public)
                return pair.public to pair.private
            } catch (e: StrongBoxUnavailableException) {
                last = e
            } catch (e: GeneralSecurityException) {
                last = e
                if (store.containsAlias(alias)) store.deleteEntry(alias)
            } catch (e: ProviderException) {
                last = e
                if (store.containsAlias(alias)) store.deleteEntry(alias)
            }
        }
        throw last ?: IllegalStateException("no vault key could be created")
    }

    /** A public-key OAEP operation inside the Keystore (needs no user): proves the digests are accepted. */
    private fun checkOaepUsable(public: PublicKey) {
        Cipher.getInstance(RSA_OAEP).apply { init(Cipher.ENCRYPT_MODE, public, OAEP) }.doFinal(ByteArray(1))
    }

    /** Whether the key lives in secure hardware (TEE or StrongBox), or null if the Keystore will not say. */
    fun isInsideSecureHardware(key: java.security.Key): Boolean? = try {
        val info = when (key) {
            is SecretKey -> (SecretKeyFactory.getInstance(key.algorithm, PROVIDER).getKeySpec(key, KeyInfo::class.java)) as KeyInfo
            else -> KeyFactory.getInstance(key.algorithm, PROVIDER).getKeySpec(key, KeyInfo::class.java)
        }
        info.isInsideSecureHardware
    } catch (e: GeneralSecurityException) {
        null
    }

    fun delete(alias: String) {
        if (store.containsAlias(alias)) store.deleteEntry(alias)
    }

    // ---- AES-GCM: iv (12) || ciphertext+tag.

    fun seal(key: SecretKey, plain: ByteArray, aad: ByteArray? = null): ByteArray {
        val cipher = Cipher.getInstance(AES_GCM)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        aad?.let(cipher::updateAAD)
        return cipher.iv + cipher.doFinal(plain)
    }

    fun open(key: SecretKey, sealed: ByteArray, aad: ByteArray? = null): ByteArray {
        require(sealed.size > IV_BYTES) { "sealed data too short" }
        val cipher = Cipher.getInstance(AES_GCM)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, IV_BYTES))
        aad?.let(cipher::updateAAD)
        return cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
    }

    // ---- RSA-OAEP (SHA-256, MGF1-SHA-1: the Keystore's supported MGF digest).

    fun rsaEncrypt(public: PublicKey, plain: ByteArray): ByteArray {
        // A software copy of the public key: encryption needs no Keystore
        // operation, so it needs no user authentication.
        val soft = KeyFactory.getInstance(public.algorithm).generatePublic(X509EncodedKeySpec(public.encoded))
        return Cipher.getInstance(RSA_OAEP).apply { init(Cipher.ENCRYPT_MODE, soft, OAEP) }.doFinal(plain)
    }

    /** A decrypt cipher to hand to BiometricPrompt as its CryptoObject. */
    fun rsaDecryptCipher(private: PrivateKey): Cipher =
        Cipher.getInstance(RSA_OAEP).apply { init(Cipher.DECRYPT_MODE, private, OAEP) }

    companion object {
        private const val PROVIDER = "AndroidKeyStore"
        private const val AES_GCM = "AES/GCM/NoPadding"
        private const val RSA_OAEP = "RSA/ECB/OAEPPadding"
        private const val IV_BYTES = 12
        private val OAEP = OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT)
    }
}
