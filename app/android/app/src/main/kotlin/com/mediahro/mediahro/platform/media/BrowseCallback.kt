package com.mediahro.mediahro.platform.media

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.annotation.OptIn
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionError
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.mediahro.mediahro.pigeon.MediaBrowseFlutterApi
import com.mediahro.mediahro.pigeon.MediaBrowseHostApi
import com.mediahro.mediahro.pigeon.MediaBrowseNodeMsg
import com.mediahro.mediahro.platform.AppEngine
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.guava.future
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The car and voice side of the session (MUS-013): Android Auto and the
 * Assistant browse, search and play through the Media3 library session;
 * every request goes to the Dart [MediaBrowseFacade] provider through
 * [MediaBrowseFlutterApi]. When the app is not running, the first request
 * starts it without a screen ([AppEngine], ADR-036) and waits for Dart to
 * register its provider; only if that fails is the session reported as
 * disconnected.
 */
@OptIn(UnstableApi::class)
object BrowseHub {
    /** How long a car request waits for a cold-started app (ADR-036). */
    const val START_TIMEOUT_MS = 15_000L

    @Volatile var flutter: MediaBrowseFlutterApi? = null
    private val ready = MutableStateFlow<MediaBrowseFlutterApi?>(null)

    /** Dart registered its provider on the current engine. */
    var registered: Boolean
        get() = ready.value != null
        set(value) {
            ready.value = if (value) flutter else null
        }

    /** The provider, or null until Dart registers one. */
    fun current(): MediaBrowseFlutterApi? = ready.value

    /** Waits up to [timeoutMs] for Dart to register its provider. */
    suspend fun await(timeoutMs: Long = START_TIMEOUT_MS): MediaBrowseFlutterApi? =
        ready.value ?: withTimeoutOrNull(timeoutMs) { ready.filterNotNull().first() }

    /** The engine is gone (or a new one starts): no provider until Dart registers. */
    fun reset() {
        ready.value = null
        flutter = null
    }

    /** Nodes seen recently, for onGetItem and voice play. */
    val nodes = ConcurrentHashMap<String, MediaBrowseNodeMsg>()
    val searches = ConcurrentHashMap<String, List<MediaBrowseNodeMsg>>()
}

/** MediaBrowseFacade on Android: Dart says it is ready and when nodes change. */
@OptIn(UnstableApi::class)
class MediaBrowseModule : MediaBrowseHostApi {
    override fun registered() {
        BrowseHub.registered = true
    }

    override fun notifyChildrenChanged(nodeId: String) {
        val session = SessionHub.service?.librarySession ?: return
        session.notifyChildrenChanged(nodeId, Int.MAX_VALUE, null)
    }
}

@OptIn(UnstableApi::class)
internal class BrowseCallback(private val context: Context) : MediaLibrarySession.Callback {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** The Dart provider, starting the app without a screen if needed (ADR-036). */
    private suspend fun api(): MediaBrowseFlutterApi? {
        BrowseHub.current()?.let { return it }
        AppEngine.startHeadless(context)
        return BrowseHub.await()
    }

    private fun <T : Any> notReady(): LibraryResult<T> =
        LibraryResult.ofError(SessionError(SessionError.ERROR_SESSION_DISCONNECTED, "app not running"))

    override fun onGetLibraryRoot(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<MediaItem>> {
        val root = MediaItem.Builder()
            .setMediaId(ROOT_ID)
            .setMediaMetadata(
                MediaMetadata.Builder().setIsBrowsable(true).setIsPlayable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED).build(),
            )
            .build()
        // The car shows the root at once; the app warms up behind it.
        if (BrowseHub.current() == null) AppEngine.startHeadless(context)
        return Futures.immediateFuture(LibraryResult.ofItem(root, params))
    }

    override fun onGetChildren(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        parentId: String,
        page: Int,
        pageSize: Int,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        return scope.future {
            val api = api() ?: return@future notReady()
            val nodes = try {
                api.children(parentId, page.toLong())
            } catch (e: Exception) {
                return@future LibraryResult.ofError(SessionError(SessionError.ERROR_UNKNOWN, e.message ?: "browse failed"))
            }
            LibraryResult.ofItemList(nodes.map { item(it, browser.packageName) }, params)
        }
    }

    override fun onGetItem(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        mediaId: String,
    ): ListenableFuture<LibraryResult<MediaItem>> {
        val node = BrowseHub.nodes[mediaId]
            ?: return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE))
        return Futures.immediateFuture(LibraryResult.ofItem(item(node, browser.packageName), null))
    }

    override fun onSearch(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        query: String,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<Void>> {
        return scope.future {
            val api = api() ?: return@future notReady()
            val found = try {
                api.search(query)
            } catch (e: Exception) {
                emptyList()
            }
            BrowseHub.searches[query] = found
            found.forEach { BrowseHub.nodes[it.id] = it }
            session.notifySearchResultChanged(browser, query, found.size, params)
            LibraryResult.ofVoid(params)
        }
    }

    override fun onGetSearchResult(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        query: String,
        page: Int,
        pageSize: Int,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        val found = BrowseHub.searches[query].orEmpty()
        val slice = found.drop(page * pageSize).take(pageSize)
        return Futures.immediateFuture(LibraryResult.ofItemList(slice.map { item(it, browser.packageName) }, params))
    }

    /**
     * A car tap or a voice request ("play … by …"): Dart starts playback
     * itself and reports it back through setNowPlaying, so the items pass
     * through to the mirror player unchanged.
     */
    override fun onSetMediaItems(
        mediaSession: MediaSession,
        controller: MediaSession.ControllerInfo,
        mediaItems: MutableList<MediaItem>,
        startIndex: Int,
        startPositionMs: Long,
    ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
        val first = mediaItems.getOrNull(maxOf(startIndex, 0))
        if (first != null) {
            scope.future {
                val api = api() ?: return@future
                val query = first.requestMetadata.searchQuery
                val id = if (!query.isNullOrBlank() && first.mediaId.isEmpty()) {
                    api.search(query).firstOrNull { it.playable }?.id
                } else {
                    first.mediaId
                }
                if (id != null) api.play(id)
            }
        }
        return Futures.immediateFuture(MediaSession.MediaItemsWithStartPosition(mediaItems, startIndex, startPositionMs))
    }

    override fun onAddMediaItems(
        mediaSession: MediaSession,
        controller: MediaSession.ControllerInfo,
        mediaItems: MutableList<MediaItem>,
    ): ListenableFuture<MutableList<MediaItem>> = Futures.immediateFuture(mediaItems)

    private fun item(n: MediaBrowseNodeMsg, browserPackage: String): MediaItem {
        BrowseHub.nodes[n.id] = n
        val metadata = MediaMetadata.Builder()
            .setTitle(n.title)
            .setSubtitle(n.subtitle)
            .setArtist(n.subtitle)
            .setArtworkUri(artwork(n.artworkUri, browserPackage))
            .setIsBrowsable(n.browsable)
            .setIsPlayable(n.playable)
            .setMediaType(if (n.browsable) MediaMetadata.MEDIA_TYPE_FOLDER_MIXED else MediaMetadata.MEDIA_TYPE_MUSIC)
            .build()
        return MediaItem.Builder().setMediaId(n.id).setMediaMetadata(metadata).build()
    }

    /** App-private artwork goes to the car as a granted content URI. */
    private fun artwork(uri: String?, browserPackage: String): Uri? {
        val u = uri?.let(Uri::parse) ?: return null
        if (u.scheme != "file") return u
        return try {
            val content = FileProvider.getUriForFile(context, "${context.packageName}.files", File(u.path ?: return null))
            context.grantUriPermission(browserPackage, content, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            content
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    companion object {
        /** `MediaBrowseNode.rootId`. */
        const val ROOT_ID = "root"
    }
}
