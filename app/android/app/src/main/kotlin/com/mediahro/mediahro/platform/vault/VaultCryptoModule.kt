package com.mediahro.mediahro.platform.vault

import android.content.Context
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import androidx.biometric.BiometricPrompt
import com.mediahro.mediahro.R
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.VaultCryptoHostApi
import com.mediahro.mediahro.platform.ActivityHost
import com.mediahro.mediahro.platform.security.BiometricAuth
import com.mediahro.mediahro.platform.security.Keystore
import com.mediahro.mediahro.platform.security.SecureStorageModule
import java.security.GeneralSecurityException
import java.security.InvalidAlgorithmParameterException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.SecretKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * VaultCryptoFacade on Android (IMG-011, ADR-039): AES-256-GCM through
 * `javax.crypto`, always off the main thread.
 *
 * - **Master key without the user step:** an AES-256-GCM Keystore key (StrongBox
 *   where present). It never leaves the Keystore; per-file keys are wrapped and
 *   unwrapped inside it.
 * - **Master key with biometry:** a random 256-bit master secret, stored
 *   encrypted to a Keystore RSA public key whose private key needs the user for
 *   every use (strong biometrics or the device credential). Opening the vault
 *   shows one BiometricPrompt with a CryptoObject, unwraps the secret into
 *   memory under the handle, and [close] zeroes it. Per-file keys are wrapped
 *   under it in software, so there is no prompt per file.
 *
 * Per-file data keys live in native memory only while their handle is open.
 * The Dart side never sees a master key or a data key.
 */
class VaultCryptoModule(private val context: Context, private val host: ActivityHost) : VaultCryptoHostApi {
    private val keystore by lazy { Keystore(context) }
    private val prefs = context.getSharedPreferences(SecureStorageModule.PREFS, Context.MODE_PRIVATE)
    private val ids = AtomicLong()
    private val masters = ConcurrentHashMap<Long, Master>()

    /** Unwrapped data keys per handle, by the wrapped bytes (Base64). */
    private val dataKeys = ConcurrentHashMap<Pair<Long, String>, ByteArray>()

    private sealed interface Master {
        class Device(val key: SecretKey) : Master

        class User(val secret: ByteArray) : Master
    }

    override suspend fun openMasterKey(requireBiometry: Boolean): Long {
        val master = if (requireBiometry) openUser() else openDevice()
        return ids.incrementAndGet().also { masters[it] = master }
    }

    private suspend fun openDevice(): Master = withContext(Dispatchers.IO) {
        try {
            Master.Device(keystore.secretKey(DEVICE_KEY))
        } catch (e: GeneralSecurityException) {
            throw FlutterError("unavailable", "No Keystore key: ${e.message}")
        }
    }

    private suspend fun openUser(): Master {
        val cipher = try {
            withContext(Dispatchers.IO) { userCipher() }
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometrics changed: the key is unusable by design; the vault needs its recovery key.
            keystore.delete(USER_KEY)
            prefs.edit().remove(USER_SECRET).apply()
            throw FlutterError("keyInvalidated", "Biometric enrolment changed")
        } catch (e: UserNotAuthenticatedException) {
            throw FlutterError("authFailed", e.message)
        } catch (e: InvalidAlgorithmParameterException) {
            // No secure lock screen: a user-bound key cannot exist.
            throw FlutterError("notEnrolled", "Set a screen lock to protect the vault: ${e.message}")
        } catch (e: IllegalStateException) {
            throw FlutterError("notEnrolled", "Set a screen lock to protect the vault: ${e.message}")
        } ?: return createUser()
        val title = context.getString(R.string.mediahro_vault_unlock)
        return when (val outcome = BiometricAuth.prompt(host.requireActivity(), title, BiometricPrompt.CryptoObject(cipher))) {
            is BiometricAuth.Outcome.Success -> withContext(Dispatchers.IO) {
                val c = outcome.result.cryptoObject?.cipher ?: throw FlutterError("authFailed", "No cipher")
                val stored = Base64.decode(prefs.getString(USER_SECRET, null), Base64.NO_WRAP)
                try {
                    Master.User(c.doFinal(stored))
                } catch (e: GeneralSecurityException) {
                    throw FlutterError("keyLost", "The device key for this vault is gone: ${e.message}")
                }
            }
            BiometricAuth.Outcome.Cancelled -> throw FlutterError("cancelled", "Unlock cancelled")
            is BiometricAuth.Outcome.Failed -> throw BiometricAuth.failure(outcome)
        }
    }

    /** A decrypt cipher for the stored secret, or null when there is none yet. */
    private fun userCipher() = prefs.getString(USER_SECRET, null)?.let {
        keystore.rsaDecryptCipher(keystore.authKeyPair(USER_KEY).second)
    }

    /** First use: a new random secret, encrypted to the public key (no prompt needed to create). */
    private suspend fun createUser(): Master = withContext(Dispatchers.IO) {
        val secret = VaultCipher.newKey()
        val (public, _) = try {
            keystore.authKeyPair(USER_KEY)
        } catch (e: InvalidAlgorithmParameterException) {
            throw FlutterError("notEnrolled", "Set a screen lock to protect the vault: ${e.message}")
        } catch (e: IllegalStateException) {
            throw FlutterError("notEnrolled", "Set a screen lock to protect the vault: ${e.message}")
        }
        val stored = Base64.encodeToString(keystore.rsaEncrypt(public, secret), Base64.NO_WRAP)
        if (!prefs.edit().putString(USER_SECRET, stored).commit()) throw FlutterError("unavailable", "Could not store the vault key")
        Master.User(secret)
    }

    override suspend fun newFileKey(handle: Long): ByteArray = withContext(Dispatchers.Default) {
        val master = master(handle)
        val data = VaultCipher.newKey()
        val wrapped = wrap(master, data)
        dataKeys[handle to Base64.encodeToString(wrapped, Base64.NO_WRAP)] = data
        wrapped
    }

    override suspend fun adoptFileKey(handle: Long, wrapped: ByteArray) {
        withContext(Dispatchers.Default) { dataKey(handle, wrapped) }
    }

    override suspend fun seal(
        handle: Long,
        wrapped: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
        plaintext: ByteArray,
    ): ByteArray = withContext(Dispatchers.Default) {
        guard { VaultCipher.seal(dataKey(handle, wrapped), nonce, aad, plaintext) }
    }

    override suspend fun open(
        handle: Long,
        wrapped: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
        sealed: ByteArray,
    ): ByteArray = withContext(Dispatchers.Default) {
        guard { VaultCipher.open(dataKey(handle, wrapped), nonce, aad, sealed) }
    }

    override suspend fun close(handle: Long) {
        (masters.remove(handle) as? Master.User)?.secret?.fill(0)
        val mine = dataKeys.keys.filter { it.first == handle }
        mine.forEach { dataKeys.remove(it)?.fill(0) }
    }

    fun dispose() {
        masters.keys.toList().forEach { h ->
            (masters.remove(h) as? Master.User)?.secret?.fill(0)
        }
        dataKeys.values.forEach { it.fill(0) }
        dataKeys.clear()
    }

    private fun master(handle: Long): Master =
        masters[handle] ?: throw FlutterError("unavailable", "The vault key $handle is closed")

    private fun wrap(master: Master, data: ByteArray): ByteArray = when (master) {
        is Master.Device -> VaultCipher.header(VaultCipher.MODE_DEVICE) + keystore.seal(master.key, data, VaultCipher.WRAP_AAD)
        is Master.User -> VaultCipher.wrap(master.secret, data, VaultCipher.MODE_USER)
    }

    /** The unwrapped data key for [wrapped], cached while the handle is open. */
    private fun dataKey(handle: Long, wrapped: ByteArray): ByteArray {
        val id = handle to Base64.encodeToString(wrapped, Base64.NO_WRAP)
        dataKeys[id]?.let { return it }
        val key = guard {
            when (val master = master(handle)) {
                is Master.Device -> {
                    VaultCipher.checkHeader(wrapped, VaultCipher.MODE_DEVICE)
                    try {
                        keystore.open(master.key, wrapped.copyOfRange(VaultCipher.HEADER, wrapped.size), VaultCipher.WRAP_AAD)
                    } catch (e: GeneralSecurityException) {
                        throw VaultFailure("keyLost", "The device key for this vault is gone: ${e.message}")
                    }
                }
                is Master.User -> VaultCipher.unwrap(master.secret, wrapped, VaultCipher.MODE_USER)
            }
        }
        dataKeys[id] = key
        return key
    }

    private inline fun <T> guard(block: () -> T): T = try {
        block()
    } catch (e: VaultFailure) {
        throw FlutterError(e.code, e.message)
    }

    companion object {
        private const val DEVICE_KEY = "mediahro.vault.master"
        private const val USER_KEY = "mediahro.vault.master.user"
        private const val USER_SECRET = "vault.master.user"
    }
}
