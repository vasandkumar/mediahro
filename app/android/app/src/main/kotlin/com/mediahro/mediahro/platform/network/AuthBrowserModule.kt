package com.mediahro.mediahro.platform.network

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.browser.customtabs.CustomTabsIntent
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.pigeon.AuthBrowserHostApi
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.platform.ActivityHost
import kotlinx.coroutines.CompletableDeferred

/**
 * AuthBrowserFacade on Android (NET-007, LIB-010; RFC 8252). The sign-in
 * page opens in a Custom Tab: the user's own browser with their existing
 * sessions, so the app never sees the password. The provider redirects to
 * the app's custom scheme `<applicationId>:/oauth2redirect`, which
 * [AuthRedirectActivity] catches. Closing the tab without a redirect is a
 * cancel.
 */
class AuthBrowserModule(private val host: ActivityHost) : AuthBrowserHostApi {
    private val main = Handler(Looper.getMainLooper())

    override suspend fun authorize(authorizationUrl: String, redirectUri: String): String {
        val expected = redirectScheme(host.context.packageName)
        if (Uri.parse(redirectUri).scheme != expected) {
            throw FlutterError("unsupportedRedirect", "Android redirects to $expected:/oauth2redirect (got $redirectUri)")
        }
        val activity = host.requireActivity()
        pending?.completeExceptionally(FlutterError("cancelled", "Superseded by a new sign-in"))
        val result = CompletableDeferred<Uri>()
        pending = result
        try {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, Uri.parse(authorizationUrl))
        } catch (e: ActivityNotFoundException) {
            pending = null
            throw FlutterError("noBrowser", "No browser to sign in with")
        }
        return try {
            result.await().toString()
        } finally {
            if (pending === result) pending = null
        }
    }

    /** The app is in front again: without a redirect, the user closed the tab. */
    fun onAppResumed() {
        val waiting = pending ?: return
        // The redirect activity completes just before the app resumes; wait a beat.
        main.postDelayed({
            if (pending === waiting && waiting.isActive) {
                waiting.completeExceptionally(FlutterError("cancelled", "Sign-in closed"))
            }
        }, CANCEL_GRACE_MS)
    }

    companion object {
        private const val CANCEL_GRACE_MS = 800L

        @Volatile private var pending: CompletableDeferred<Uri>? = null

        /** The redirect scheme: the application id (`com.mediahro.app`, `….enterprise`). */
        fun redirectScheme(packageName: String) = packageName

        /** From [AuthRedirectActivity]; false when no sign-in is waiting. */
        fun complete(uri: Uri): Boolean = pending?.complete(uri) ?: false
    }
}

/**
 * Receives `<applicationId>:/oauth2redirect?code=…&state=…` (RFC 8252 §7.1),
 * hands it to [AuthBrowserModule] and brings the app back over the Custom
 * Tab. It has no UI of its own.
 */
class AuthRedirectActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.let(AuthBrowserModule::complete)
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }
}
