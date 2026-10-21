package com.mediahro.mediahro.platform.vault

import javax.crypto.BadPaddingException
import javax.crypto.IllegalBlockSizeException

/**
 * How a failure while opening stored key material is told to Dart (no Android
 * types, so the mapping is unit-tested). Only a failed authentication or a
 * block that cannot be a valid sealing means the key material does not belong
 * to this key (`keyLost`); every other failure (a Keystore that is not
 * reachable, an invalid key, a provider error, a runtime error) says nothing
 * about the key and is `unavailable`, so the UI never offers a reset for a
 * temporary fault. `KeyPermanentlyInvalidatedException` and
 * `UserNotAuthenticatedException` are handled by the caller before this.
 */
internal object KeystoreErrors {
    fun opening(e: Throwable): VaultFailure = when (e) {
        // AEADBadTagException is a BadPaddingException: AES-GCM or RSA-OAEP rejected the data.
        is BadPaddingException -> VaultFailure("keyLost", "The device key cannot open this key material")
        is IllegalBlockSizeException -> VaultFailure("keyLost", "Damaged key material")
        else -> VaultFailure("unavailable", "Keystore failure: ${e.javaClass.simpleName}: ${e.message}")
    }
}
