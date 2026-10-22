package com.mediahro.mediahro.platform.background

import android.os.Handler
import android.os.Looper
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.RunsStreamHandler
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The meeting point of a WorkManager worker and Dart (ADR-049): the worker
 * posts an id on `runs` and waits; Dart's `complete(id, success)` answers.
 *
 * The worker may run before Dart has started listening (a cold process whose
 * engine was only just started), so [run] waits for a listener, up to its
 * timeout, before it posts. [post] puts the delivery on the thread event sinks
 * belong to (the main thread on Android); it is a parameter so the logic can
 * be tested on the JVM.
 */
internal class RunBroker(private val post: (() -> Unit) -> Unit) {
    private val pending = ConcurrentHashMap<String, CompletableDeferred<Boolean>>()

    @Volatile private var emit: ((String) -> Unit)? = null

    /** Completed when Dart listens to `runs`; replaced with a fresh one when it stops. */
    @Volatile private var listening = CompletableDeferred<Unit>()

    /** Dart started listening; [emit] delivers an id to it. */
    fun attach(emit: (String) -> Unit) {
        this.emit = emit
        listening.complete(Unit)
    }

    /** Dart stopped listening. */
    fun detach() {
        emit = null
        if (listening.isCompleted) listening = CompletableDeferred()
    }

    /**
     * Delivers [id] to Dart and waits for its answer: true for success, false
     * for a failure or when Dart did not listen or answer within [timeoutMs].
     */
    suspend fun run(id: String, timeoutMs: Long): Boolean {
        val answer = CompletableDeferred<Boolean>()
        // A run of the same id that is still waiting (it was stopped) is over.
        pending.put(id, answer)?.complete(false)
        try {
            return withTimeoutOrNull(timeoutMs) {
                listening.await()
                post { emit?.invoke(id) }
                answer.await()
            } ?: false
        } finally {
            pending.remove(id, answer)
        }
    }

    /** Dart finished the run of [id]. A late or unknown answer is ignored. */
    fun complete(id: String, success: Boolean) {
        pending[id]?.complete(success)
    }

    /** The engine went away: Dart cannot answer any more, so the waiting runs fail (and retry). */
    fun reset() {
        detach()
        pending.values.forEach { it.complete(false) }
    }
}

internal object BackgroundHub {
    private val main by lazy { Handler(Looper.getMainLooper()) }
    val broker = RunBroker { main.post { it() } }

    val handler = object : RunsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<String>) {
            broker.attach { sink.success(it) }
        }

        override fun onCancel(p0: Any?) {
            broker.detach()
        }
    }
}
