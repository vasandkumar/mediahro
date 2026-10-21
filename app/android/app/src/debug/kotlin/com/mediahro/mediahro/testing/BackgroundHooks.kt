package com.mediahro.mediahro.testing

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Data
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.mediahro.mediahro.platform.background.BackgroundPlan
import com.mediahro.mediahro.platform.background.PeriodicWorker
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Debug-only hooks for the background work test (lane C4a, ADR-049): WorkManager
 * only runs a 15-minute periodic job every 15 minutes, so the test starts a run
 * of the same worker at once and reads the state back. `mediahro.test/background`
 * takes `[op, ...]`:
 * - `job`, id: what WorkManager holds for the id's periodic job:
 *   `{state, intervalMs, network, charging}`, or null when there is none.
 * - `run`, id: starts one run of the worker for the id now; replies its work id.
 * - `state`, work id: the run's state name and attempt count, `[state, attempts]`.
 * - `stop`, work id: cancels the run (a run that failed waits to be retried).
 */
internal object BackgroundHooks {
    private val io = Executors.newSingleThreadExecutor()

    fun install(context: Context, messenger: BinaryMessenger) {
        val main = Handler(Looper.getMainLooper())
        BasicMessageChannel(messenger, "mediahro.test/background", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val args = message as List<*>
                io.execute {
                    val work = WorkManager.getInstance(context)
                    val result: Any? = when (args[0]) {
                        "job" -> job(work, args[1] as String)
                        "run" -> {
                            val request = OneTimeWorkRequestBuilder<PeriodicWorker>()
                                .setInputData(Data.Builder().putString(PeriodicWorker.KEY_ID, args[1] as String).build())
                                .build()
                            work.enqueue(request).result.get()
                            request.id.toString()
                        }
                        "state" -> work.getWorkInfoById(UUID.fromString(args[1] as String)).get()
                            ?.let { listOf(it.state.name, it.runAttemptCount) }
                        "stop" -> {
                            work.cancelWorkById(UUID.fromString(args[1] as String)).result.get()
                            true
                        }
                        else -> null
                    }
                    main.post { reply.reply(result) }
                }
            }
    }

    private fun job(work: WorkManager, id: String): Map<String, Any?>? {
        val info = work.getWorkInfosForUniqueWork(BackgroundPlan.uniqueName(id)).get()
            .firstOrNull { it.state != WorkInfo.State.CANCELLED } ?: return null
        return mapOf(
            "state" to info.state.name,
            "intervalMs" to info.periodicityInfo?.repeatIntervalMillis,
            "network" to info.constraints.requiredNetworkType.name,
            "charging" to info.constraints.requiresCharging(),
        )
    }
}
