package com.mediahro.mediahro.platform.background

import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest

/**
 * The decisions behind [BackgroundWorkModule], free of Android so they can be
 * unit tested (ADR-049): how a Dart request becomes a WorkManager request.
 */
internal object BackgroundPlan {
    /** WorkManager refuses shorter periods; the facade documents the same floor. */
    const val MIN_INTERVAL_MS = PeriodicWorkRequest.MIN_PERIODIC_INTERVAL_MILLIS

    /** Longer than a year is a mistake (an overflowing duration), not a schedule. */
    const val MAX_INTERVAL_MS = 366L * 24 * 60 * 60 * 1000

    const val MAX_ID_LENGTH = 128

    /** The most a worker waits for Dart to finish: the OS stops a worker after 10 minutes. */
    const val RUN_TIMEOUT_MS = 8L * 60 * 1000

    private const val NAME_PREFIX = "mediahro.bg."

    /** The interval WorkManager will use: at least 15 minutes, at most a year. */
    fun interval(requestedMs: Long): Long = requestedMs.coerceIn(MIN_INTERVAL_MS, MAX_INTERVAL_MS)

    /**
     * The unique work name for [id]; the same id always gives the same name, so
     * scheduling it again replaces the earlier schedule. Throws for an id that
     * is empty, too long or has control characters.
     */
    fun uniqueName(id: String): String {
        require(id.isNotBlank()) { "background work id is empty" }
        require(id.length <= MAX_ID_LENGTH) { "background work id is longer than $MAX_ID_LENGTH" }
        require(id.none { it.isISOControl() }) { "background work id has control characters" }
        return NAME_PREFIX + id
    }

    /**
     * The network the work needs. An unmetered requirement implies a network, so
     * `unmeteredOnly` wins over `requiresNetwork`.
     */
    fun network(requiresNetwork: Boolean, unmeteredOnly: Boolean): NetworkType = when {
        unmeteredOnly -> NetworkType.UNMETERED
        requiresNetwork -> NetworkType.CONNECTED
        else -> NetworkType.NOT_REQUIRED
    }
}
