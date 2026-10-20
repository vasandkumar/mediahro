package com.mediahro.mediahro.platform.security

import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import com.mediahro.mediahro.pigeon.BiometricKindMsg
import com.mediahro.mediahro.pigeon.BiometricsHostApi
import com.mediahro.mediahro.platform.ActivityHost

/**
 * BiometricsFacade on Android (PRIV-008, IMG-011, LIB-013): BiometricPrompt
 * with the device credential as the fallback.
 */
class BiometricsModule(private val context: Context, private val host: ActivityHost) : BiometricsHostApi {
    override fun available(): BiometricKindMsg {
        val pm = context.packageManager
        if (BiometricManager.from(context).canAuthenticate(BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS) {
            return when {
                pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT) -> BiometricKindMsg.FINGERPRINT
                Build.VERSION.SDK_INT >= 29 && pm.hasSystemFeature(PackageManager.FEATURE_FACE) -> BiometricKindMsg.FACE
                else -> BiometricKindMsg.FINGERPRINT
            }
        }
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        return if (keyguard?.isDeviceSecure == true) BiometricKindMsg.DEVICE_CREDENTIAL else BiometricKindMsg.NONE
    }

    override suspend fun authenticate(reason: String): Boolean {
        if (available() == BiometricKindMsg.NONE) return false
        return when (val outcome = BiometricAuth.prompt(host.requireActivity(), reason, null)) {
            is BiometricAuth.Outcome.Success -> true
            BiometricAuth.Outcome.Cancelled -> false
            is BiometricAuth.Outcome.Failed -> throw BiometricAuth.failure(outcome)
        }
    }
}
