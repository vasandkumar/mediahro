package com.mediahro.mediahro.platform.system

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.IntentCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.mediahro.mediahro.MainActivity
import com.mediahro.mediahro.R
import com.mediahro.mediahro.pigeon.AppIntentKindMsg
import com.mediahro.mediahro.pigeon.AppIntentMsg
import com.mediahro.mediahro.pigeon.AppIntentsStreamHandler
import com.mediahro.mediahro.pigeon.AppShortcutMsg
import com.mediahro.mediahro.pigeon.IntentsHostApi
import com.mediahro.mediahro.pigeon.OpenRequestMsg
import com.mediahro.mediahro.pigeon.OpenRequestsStreamHandler
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.SystemHostApi
import com.mediahro.mediahro.platform.ActivityHost

/**
 * Intents that open the app with something to do: files and links from
 * "Open with" (CORE-003) and the share sheet (SYS-004), and shortcuts and
 * App Actions (SYS-003). They usually arrive on a cold start, before Dart
 * listens, so each stream holds them until it does.
 */
object IncomingIntents {
    private var openSink: PigeonEventSink<OpenRequestMsg>? = null
    private var intentSink: PigeonEventSink<AppIntentMsg>? = null
    private val pendingOpens = ArrayList<OpenRequestMsg>()
    private val pendingIntents = ArrayList<AppIntentMsg>()

    const val ACTION_SHORTCUT = "com.mediahro.mediahro.SHORTCUT"
    const val EXTRA_KIND = "mediahro.intent.kind"
    const val EXTRA_ARGUMENT = "mediahro.intent.argument"

    /** App Actions' OPEN_APP_FEATURE passes the feature name as `feature`. */
    private const val EXTRA_FEATURE = "feature"

    val openHandler = object : OpenRequestsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<OpenRequestMsg>) {
            synchronized(this@IncomingIntents) {
                openSink = sink
                pendingOpens.forEach(sink::success)
                pendingOpens.clear()
            }
        }

        override fun onCancel(p0: Any?) {
            openSink = null
        }
    }

    val intentHandler = object : AppIntentsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<AppIntentMsg>) {
            synchronized(this@IncomingIntents) {
                intentSink = sink
                pendingIntents.forEach(sink::success)
                pendingIntents.clear()
            }
        }

        override fun onCancel(p0: Any?) {
            intentSink = null
        }
    }

    /** From MainActivity.onCreate / onNewIntent. True when it was one of ours. */
    fun handle(context: Context, intent: Intent?): Boolean {
        intent ?: return false
        appIntentOf(intent)?.let {
            emit(it)
            return true
        }
        val uris = urisOf(context, intent)
        if (uris.isEmpty()) {
            // A shared text that is not a link is a search, never a fetch (SYS-004).
            val query = sharedSearchText(intent.action, intent.getStringExtra(Intent.EXTRA_TEXT)) ?: return false
            emit(AppIntentMsg(AppIntentKindMsg.search, query))
            return true
        }
        emit(OpenRequestMsg(uris.map(Uri::toString)))
        return true
    }

    /** The longest search text taken from a share. */
    const val MAX_SEARCH_TEXT = 200

    /**
     * The text of a SEND that holds no link: trimmed, control characters turned into
     * spaces, cut to [MAX_SEARCH_TEXT]. Null for anything else. Pure, so it is unit-tested on the JVM.
     */
    fun sharedSearchText(action: String?, text: String?): String? {
        if (action != Intent.ACTION_SEND || text == null || linkTextIn(text) != null) return null
        val clean = text.map { if (it.isISOControl()) ' ' else it }.joinToString("").trim()
        return clean.take(MAX_SEARCH_TEXT).ifEmpty { null }
    }

    @Synchronized
    private fun emit(msg: OpenRequestMsg) {
        openSink?.success(msg) ?: pendingOpens.add(msg)
    }

    @Synchronized
    private fun emit(msg: AppIntentMsg) {
        intentSink?.success(msg) ?: pendingIntents.add(msg)
    }

    private fun appIntentOf(intent: Intent): AppIntentMsg? {
        if (intent.action == ACTION_SHORTCUT) {
            val kind = intent.getStringExtra(EXTRA_KIND)?.let { name ->
                AppIntentKindMsg.entries.firstOrNull { it.name == name }
            } ?: return null
            return AppIntentMsg(kind, intent.getStringExtra(EXTRA_ARGUMENT))
        }
        return null
    }

    /**
     * Files and links in VIEW, SEND and SEND_MULTIPLE (with their read grants
     * kept for this process); a shared text that is a link counts as one.
     */
    fun urisOf(context: Context, intent: Intent): List<Uri> {
        val uris = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(
                IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                    ?: intent.getStringExtra(Intent.EXTRA_TEXT)?.let(::linkIn),
            )
            Intent.ACTION_SEND_MULTIPLE ->
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
            else -> emptyList()
        }.ifEmpty { clipUris(intent.clipData) }
        // A persistable grant survives the activity (only when the sender allowed it).
        for (uri in uris) {
            if (uri.scheme == "content") {
                runCatching {
                    context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
        }
        return uris
    }

    private fun clipUris(clip: ClipData?): List<Uri> =
        clip?.let { c -> (0 until c.itemCount).mapNotNull { c.getItemAt(it).uri } }.orEmpty()

    /** The first http(s)/rtsp/rtmp/… link in shared text (a browser "Share" of a stream). */
    private fun linkIn(text: String): Uri? = linkTextIn(text)?.let(Uri::parse)

    /** [linkIn]'s text part; pure, so it is unit-tested on the JVM. */
    fun linkTextIn(text: String): String? =
        Regex("""(?i)\b(?:https?|rtsps?|rtmps?|mms|srt|udp|rtp)://[^\s<>"']+""").find(text)
            ?.value?.trimEnd('.', ',', ')', ']')
}

/** SystemIntegrationFacade on Android: default-app guidance; window members are no-ops. */
class SystemModule(private val host: ActivityHost) : SystemHostApi {
    override fun showDefaultAppGuidance() {
        val context = host.activity ?: host.context
        val pkg = Uri.parse("package:${host.context.packageName}")
        val candidates = buildList {
            if (Build.VERSION.SDK_INT >= 31) add(Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, pkg))
            add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg))
        }
        for (intent in candidates) {
            if (host.activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return
            } catch (e: ActivityNotFoundException) {
                // Try the next page.
            }
        }
    }
}

/**
 * IntentsFacade on Android (SYS-003): dynamic launcher shortcuts, also
 * offered to the Assistant as suggestions; static App Actions live in
 * res/xml/shortcuts.xml. Taps arrive on [IncomingIntents].
 */
class IntentsModule(private val context: Context) : IntentsHostApi {
    override fun publishShortcuts(shortcuts: List<AppShortcutMsg>) {
        val infos = shortcuts.take(ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)).mapIndexed { i, s ->
            ShortcutInfoCompat.Builder(context, s.id)
                .setShortLabel(s.title)
                .setLongLabel(s.title)
                .setRank(i)
                .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
                .setIntent(shortcutIntent(context, s.kind, s.argument))
                .build()
        }
        ShortcutManagerCompat.setDynamicShortcuts(context, infos)
        // Lets the Assistant and the launcher suggest them.
        infos.forEach { ShortcutManagerCompat.pushDynamicShortcut(context, it) }
    }

    companion object {
        fun shortcutIntent(context: Context, kind: AppIntentKindMsg, argument: String?): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(IncomingIntents.ACTION_SHORTCUT)
                .putExtra(IncomingIntents.EXTRA_KIND, kind.name)
                .putExtra(IncomingIntents.EXTRA_ARGUMENT, argument)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
}
