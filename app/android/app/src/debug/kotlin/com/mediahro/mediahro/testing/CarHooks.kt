package com.mediahro.mediahro.testing

import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaBrowser
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.mediahro.mediahro.platform.media.AlarmModule
import com.mediahro.mediahro.platform.media.PlaybackService
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only hooks for the Android Auto and alarm tests (lane C4a),
 * `mediahro.test/car` taking `[op, arg]`. A Media3 MediaBrowser talks to
 * the library session the way Android Auto does:
 * - `root`, `children` (parent id), `search` (query): nodes as maps.
 * - `play` (media id): a car tap; `voice` (query): "play …" by voice.
 * - `canExactAlarms`: whether "Alarms & reminders" is granted.
 * - `openFromAlarm` (id): opens the app as the alarm notification does.
 * - `release`.
 */
internal object CarHooks {
    private var browser: MediaBrowser? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/car", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val args = message as List<*>
                val arg = args.getOrNull(1) as String?
                when (args[0]) {
                    "canExactAlarms" -> reply.reply(
                        Build.VERSION.SDK_INT < 31 ||
                            context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms(),
                    )
                    "openFromAlarm" -> {
                        context.startActivity(AlarmModule.launchIntent(context, arg ?: ""))
                        reply.reply(true)
                    }
                    "release" -> {
                        browser?.release()
                        browser = null
                        reply.reply(true)
                    }
                    else -> withBrowser(context) { b -> run(context, b, args[0] as String, arg) { reply.reply(it) } }
                }
            }
    }

    private fun run(context: Context, b: MediaBrowser, op: String, arg: String?, reply: (Any?) -> Unit) {
        when (op) {
            "root" -> await(context, b.getLibraryRoot(null)) { r -> reply(r.value?.let(::node) ?: error(r)) }
            "children" -> await(context, b.getChildren(arg!!, 0, 100, null)) { r ->
                reply(r.value?.map(::node) ?: error(r))
            }
            "search" -> await(context, b.search(arg!!, null)) { _ ->
                await(context, b.getSearchResult(arg, 0, 100, null)) { r -> reply(r.value?.map(::node) ?: error(r)) }
            }
            "play" -> {
                b.setMediaItem(MediaItem.Builder().setMediaId(arg!!).build())
                b.prepare()
                b.play()
                reply(true)
            }
            "voice" -> {
                b.setMediaItem(
                    MediaItem.Builder().setRequestMetadata(
                        MediaItem.RequestMetadata.Builder().setSearchQuery(arg).build(),
                    ).build(),
                )
                b.prepare()
                b.play()
                reply(true)
            }
            else -> reply("unknown op $op")
        }
    }

    private fun error(r: LibraryResult<*>) = mapOf("error" to r.resultCode)

    private fun node(item: MediaItem) = mapOf(
        "id" to item.mediaId,
        "title" to item.mediaMetadata.title?.toString(),
        "subtitle" to item.mediaMetadata.subtitle?.toString(),
        "browsable" to item.mediaMetadata.isBrowsable,
        "playable" to item.mediaMetadata.isPlayable,
        "artworkUri" to item.mediaMetadata.artworkUri?.toString(),
    )

    private fun <T> await(context: Context, f: ListenableFuture<T>, then: (T) -> Unit) =
        f.addListener({ then(f.get()) }, ContextCompat.getMainExecutor(context))

    private fun withBrowser(context: Context, block: (MediaBrowser) -> Unit) {
        browser?.takeIf { it.isConnected }?.let { return block(it) }
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaBrowser.Builder(context, token).buildAsync()
        future.addListener({
            val b = future.get()
            browser = b
            block(b)
        }, ContextCompat.getMainExecutor(context))
    }
}
