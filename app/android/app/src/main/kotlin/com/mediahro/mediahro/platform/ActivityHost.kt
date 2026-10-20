package com.mediahro.mediahro.platform

import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.mediahro.mediahro.pigeon.FlutterError
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * The foreground activity for modules that need system UI (pickers,
 * permission prompts, trash consent, biometrics). Modules hold the
 * application context and ask this host for the activity per call.
 */
class ActivityHost(val context: Context) {
    private var ref: WeakReference<FragmentActivity>? = null
    private val keys = AtomicInteger()

    /**
     * Debug builds' integration-test hook (`DebugHooks`): answers a system
     * picker with a queued result instead of showing it (null: not
     * answered, show the real UI). Unset in release builds.
     */
    @Volatile
    var fake: ((contract: ActivityResultContract<*, *>, input: Any?) -> Result<Any?>?)? = null

    fun attach(activity: FragmentActivity) {
        ref = WeakReference(activity)
    }

    fun detach(activity: FragmentActivity) {
        if (ref?.get() === activity) ref = null
    }

    val activity: FragmentActivity?
        get() = ref?.get()

    fun requireActivity(): FragmentActivity =
        activity ?: throw FlutterError("noActivity", "No foreground activity for system UI")

    /**
     * Launches [contract] through the activity's registry without a
     * lifecycle owner, so it can be registered at any time; the launcher is
     * unregistered when the result arrives.
     */
    suspend fun <I, O> launch(contract: ActivityResultContract<I, O>, input: I): O {
        fake?.invoke(contract, input)?.let {
            @Suppress("UNCHECKED_CAST")
            return it.getOrThrow() as O
        }
        val activity = requireActivity()
        return suspendCancellableCoroutine { cont ->
            val key = "mediahro.result.${keys.incrementAndGet()}"
            var launcher: ActivityResultLauncher<I>? = null
            launcher = activity.activityResultRegistry.register(key, contract) { result ->
                launcher?.unregister()
                if (cont.isActive) cont.resume(result)
            }
            cont.invokeOnCancellation { launcher.unregister() }
            launcher.launch(input)
        }
    }

    fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** Requests [permissions]; returns the grant per permission. */
    suspend fun request(permissions: List<String>): Map<String, Boolean> {
        val missing = permissions.filterNot(::granted)
        if (missing.isEmpty()) return permissions.associateWith { true }
        val result = launch(ActivityResultContracts.RequestMultiplePermissions(), missing.toTypedArray())
        return permissions.associateWith { granted(it) || result[it] == true }
    }
}
