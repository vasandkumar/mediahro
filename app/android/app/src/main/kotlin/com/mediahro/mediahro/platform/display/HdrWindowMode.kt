package com.mediahro.mediahro.platform.display

import android.content.pm.ActivityInfo
import android.view.Window
import java.util.WeakHashMap

/**
 * Puts a window in HDR colour mode while at least one HDR view (the video
 * SurfaceView, ADR-022, or the image view, IMG-002) needs it, and restores
 * the previous mode when the last one is gone. Main thread only.
 */
object HdrWindowMode {
    private class Entry(val previous: Int, var users: Int)

    private val entries = WeakHashMap<Window, Entry>()

    fun acquire(window: Window) {
        val entry = entries.getOrPut(window) {
            Entry(window.colorMode, 0).also { window.colorMode = ActivityInfo.COLOR_MODE_HDR }
        }
        entry.users++
    }

    fun release(window: Window) {
        val entry = entries[window] ?: return
        if (--entry.users > 0) return
        entries.remove(window)
        window.colorMode = entry.previous
    }
}
