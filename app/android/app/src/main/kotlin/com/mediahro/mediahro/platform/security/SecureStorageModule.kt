package com.mediahro.mediahro.platform.security

import android.content.Context
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import androidx.biometric.BiometricPrompt
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.SecureStorageHostApi
import com.mediahro.mediahro.platform.ActivityHost
import java.security.GeneralSecurityException
import java.security.InvalidAlgorithmParameterException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * SecureStorageFacade on Android (PRIV-006, ADR-008). Values are sealed with
 * a Keystore AES-256-GCM key (StrongBox where present) bound to their key
 * name, and only the ciphertext is stored, in app-private preferences that
 * are excluded from backups. Vault keys are wrapped with the same AES key,
 * or with a Keystore RSA key that needs the user for every unwrap.
 */
class SecureStorageModule(private val context: Context, private val host: ActivityHost) : SecureStorageHostApi {
    private val keystore by lazy { Keystore(context) }
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override suspend fun read(key: String): String? = withContext(Dispatchers.IO) {
        val stored = prefs.getString(key, null) ?: return@withContext null
        try {
            String(
                keystore.open(keystore.secretKey(STORAGE_KEY), Base64.decode(stored, Base64.NO_WRAP), key.toByteArray()),
                Charsets.UTF_8,
            )
        } catch (e: GeneralSecurityException) {
            // The Keystore key is gone (device restore, cleared credentials):
            // the secret cannot be recovered, so it reads as absent.
            prefs.edit().remove(key).apply()
            null
        }
    }

    override suspend fun write(key: String, value: String) = withContext(Dispatchers.IO) {
        val sealed = keystore.seal(keystore.secretKey(STORAGE_KEY), value.toByteArray(Charsets.UTF_8), key.toByteArray())
        if (!prefs.edit().putString(key, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()) {
            throw FlutterError("io", "Could not store $key")
        }
    }

    override suspend fun delete(key: String) = withContext(Dispatchers.IO) {
        prefs.edit().remove(key).commit()
        Unit
    }

    override suspend fun wrapKey(key: ByteArray, requireBiometry: Boolean): ByteArray = withContext(Dispatchers.IO) {
        if (!requireBiometry) {
            return@withContext byteArrayOf(VERSION, MODE_PLAIN) + keystore.seal(keystore.secretKey(WRAP_KEY), key)
        }
        val (public, _) = try {
            keystore.authKeyPair(AUTH_KEY)
        } catch (e: InvalidAlgorithmParameterException) {
            // No secure lock screen: a user-bound key cannot exist.
            throw FlutterError("notEnrolled", "Set a screen lock to protect the vault: ${e.message}")
        } catch (e: IllegalStateException) {
            throw FlutterError("notEnrolled", "Set a screen lock to protect the vault: ${e.message}")
        }
        byteArrayOf(VERSION, MODE_USER) + keystore.rsaEncrypt(public, key)
    }

    override suspend fun unwrapKey(wrapped: ByteArray, reason: String): ByteArray {
        if (wrapped.size < 3 || wrapped[0] != VERSION) throw FlutterError("invalidArgument", "Unknown wrapped-key format")
        val body = wrapped.copyOfRange(2, wrapped.size)
        return when (wrapped[1]) {
            MODE_PLAIN -> withContext(Dispatchers.IO) {
                try {
                    keystore.open(keystore.secretKey(WRAP_KEY), body)
                } catch (e: GeneralSecurityException) {
                    throw FlutterError("keyLost", "The device key for this vault is gone: ${e.message}")
                }
            }
            MODE_USER -> unwrapWithUser(body, reason)
            else -> throw FlutterError("invalidArgument", "Unknown wrapped-key mode")
        }
    }

    private suspend fun unwrapWithUser(body: ByteArray, reason: String): ByteArray {
        val cipher = try {
            keystore.rsaDecryptCipher(keystore.authKeyPair(AUTH_KEY).second)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // Biometrics changed: the key is unusable by design.
            keystore.delete(AUTH_KEY)
            throw FlutterError("keyInvalidated", "Biometric enrolment changed; the vault needs its recovery key")
        } catch (e: UserNotAuthenticatedException) {
            throw FlutterError("authFailed", e.message)
        }
        return when (val outcome = BiometricAuth.prompt(host.requireActivity(), reason, BiometricPrompt.CryptoObject(cipher))) {
            is BiometricAuth.Outcome.Success -> withContext(Dispatchers.IO) {
                val c = outcome.result.cryptoObject?.cipher ?: throw FlutterError("authFailed", "No cipher")
                c.doFinal(body)
            }
            BiometricAuth.Outcome.Cancelled -> throw FlutterError("cancelled", "Unlock cancelled")
            is BiometricAuth.Outcome.Failed -> throw BiometricAuth.failure(outcome)
        }
    }

    companion object {
        /** Preferences file; excluded from backups (res/xml/backup_rules.xml). */
        const val PREFS = "mediahro.secure"
        private const val STORAGE_KEY = "mediahro.secure.storage"
        private const val WRAP_KEY = "mediahro.secure.wrap"
        private const val AUTH_KEY = "mediahro.secure.wrap.user"
        private const val VERSION: Byte = 1
        private const val MODE_PLAIN: Byte = 0
        private const val MODE_USER: Byte = 1
    }
}
