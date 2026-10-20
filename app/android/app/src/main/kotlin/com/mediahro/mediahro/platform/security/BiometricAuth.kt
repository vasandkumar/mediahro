package com.mediahro.mediahro.platform.security

import android.os.Build
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.mediahro.mediahro.pigeon.FlutterError
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * BiometricPrompt as a suspend call (PRIV-008, IMG-011, LIB-013). The
 * prompt offers the device PIN/pattern/password next to biometrics, so
 * users without enrolled biometrics are not locked out. [title] is the
 * localised reason from Dart (ARB), never a native string.
 */
internal object BiometricAuth {
    sealed interface Outcome {
        data class Success(val result: BiometricPrompt.AuthenticationResult) : Outcome
        data object Cancelled : Outcome
        data class Failed(val code: Int, val message: String) : Outcome
    }

    /**
     * [crypto]: a Keystore operation that needs the user (strong biometrics
     * or the device credential); null for a plain identity check.
     */
    suspend fun prompt(activity: FragmentActivity, title: String, crypto: BiometricPrompt.CryptoObject?): Outcome =
        suspendCancellableCoroutine { cont ->
            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (cont.isActive) cont.resume(Outcome.Success(result))
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (!cont.isActive) return
                    val cancelled = errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                        errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_CANCELED
                    cont.resume(if (cancelled) Outcome.Cancelled else Outcome.Failed(errorCode, errString.toString()))
                }
                // onAuthenticationFailed: a non-matching finger; the prompt stays up.
            }
            val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            val info = BiometricPrompt.PromptInfo.Builder().setTitle(title)
            if (Build.VERSION.SDK_INT >= 30) {
                info.setAllowedAuthenticators((if (crypto != null) BIOMETRIC_STRONG else BIOMETRIC_WEAK) or DEVICE_CREDENTIAL)
            } else if (crypto == null) {
                @Suppress("DEPRECATION")
                info.setDeviceCredentialAllowed(true)
            } else {
                // Android 10 allows only strong biometrics with a CryptoObject.
                info.setAllowedAuthenticators(BIOMETRIC_STRONG).setNegativeButtonText(activity.getString(android.R.string.cancel))
            }
            try {
                if (crypto != null) prompt.authenticate(info.build(), crypto) else prompt.authenticate(info.build())
            } catch (e: IllegalArgumentException) {
                cont.resume(Outcome.Failed(-1, e.message ?: "invalid prompt"))
            }
            cont.invokeOnCancellation { prompt.cancelAuthentication() }
        }

    fun failure(outcome: Outcome.Failed): FlutterError = when (outcome.code) {
        BiometricPrompt.ERROR_NO_BIOMETRICS, BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL ->
            FlutterError("notEnrolled", outcome.message)
        BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
            FlutterError("lockedOut", outcome.message)
        BiometricPrompt.ERROR_HW_NOT_PRESENT, BiometricPrompt.ERROR_HW_UNAVAILABLE ->
            FlutterError("unavailable", outcome.message)
        else -> FlutterError("authFailed", outcome.message)
    }
}
