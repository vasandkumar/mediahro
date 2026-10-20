package com.mediahro.mediahro_engine

import android.view.Surface
import java.util.concurrent.ConcurrentHashMap

/**
 * Native HDR video views (VID-031, ADR-022): lane C4's platform view
 * registers its [Surface] here under the opaque handle it passes to
 * `VideoTarget.platformView(handle)`; the engine looks it up to point mpv at
 * it. Unregister when the view's surface is destroyed.
 */
object MediahroEngineViews {
    private val surfaces = ConcurrentHashMap<Int, Surface>()

    @JvmStatic
    fun register(
        handle: Int,
        surface: Surface,
    ) {
        surfaces[handle] = surface
    }

    @JvmStatic
    fun unregister(handle: Int) {
        surfaces.remove(handle)
    }

    internal fun lookup(handle: Int): Surface? = surfaces[handle]?.takeIf { it.isValid }
}
