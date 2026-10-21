package com.mediahro.mediahro.platform.display

/**
 * The open presentations (ADR-044) and what closes them: no Android types,
 * so closing on display removal is unit-tested. Every close runs the entry's
 * [Entry.close] once, however it was triggered.
 */
internal class PresentationRegistry {
    class Entry(val id: Long, val displayId: String, val close: () -> Unit)

    private val entries = LinkedHashMap<Long, Entry>()
    private var next = 0L

    /** Registers a presentation on [displayId]; [close] releases its native resources. */
    @Synchronized
    fun add(displayId: String, close: () -> Unit): Long {
        val id = ++next
        entries[id] = Entry(id, displayId, close)
        return id
    }

    @Synchronized
    fun contains(id: Long): Boolean = id in entries

    @Synchronized
    fun displayOf(id: Long): String? = entries[id]?.displayId

    /** Closes [id]; false if it was not open (already closed). */
    fun close(id: Long): Boolean {
        val entry = synchronized(this) { entries.remove(id) } ?: return false
        runCatching(entry.close)
        return true
    }

    /** The display is gone: closes every presentation on it and returns their ids. */
    fun closeForDisplay(displayId: String): List<Long> {
        val ids = synchronized(this) { entries.values.filter { it.displayId == displayId }.map { it.id } }
        ids.forEach(::close)
        return ids
    }

    /** The engine is going away. */
    fun closeAll() {
        val ids = synchronized(this) { entries.keys.toList() }
        ids.forEach(::close)
    }

    @get:Synchronized
    val count: Int get() = entries.size
}
