package com.mediahro.mediahro.platform

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint

/**
 * The app's one Flutter engine when no activity started it (ADR-036).
 *
 * Android Auto and the Assistant can connect to the playback service while
 * the app is not running (MUS-013). The service then starts the app's own
 * engine without a screen: the normal `main` entrypoint, the same services
 * and providers, so the music player and its browse tree come up exactly as
 * on a normal launch. The engine goes into [FlutterEngineCache]; if the user
 * then opens the app, MainActivity shows this engine instead of starting a
 * second one, so there is never a second player, database writer or session
 * owner. It is destroyed when neither the playback service nor the activity
 * needs it.
 */
object AppEngine {
    private const val TAG = "MediahroAppEngine"

    /** Id in [FlutterEngineCache]; MainActivity adopts the engine by this id. */
    const val CACHE_ID = "mediahro.app"

    @Volatile private var serviceAlive = false
    @Volatile private var activityAttached = false
    @Volatile private var workers = 0

    /** The headless engine, if one is running. */
    fun cached(): FlutterEngine? = FlutterEngineCache.getInstance().get(CACHE_ID)

    /**
     * Starts the engine without a screen if no engine is alive (main thread).
     * Returns true when it started one.
     */
    fun startHeadless(context: Context): Boolean {
        check(Looper.myLooper() == Looper.getMainLooper()) { "main thread only" }
        if (PlatformModules.engineAlive) return false
        val app = context.applicationContext
        // Loads the Flutter runtime if needed; plugins register themselves.
        val engine = FlutterEngine(app)
        PlatformModules.register(app, engine)
        engine.dartExecutor.executeDartEntrypoint(DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(CACHE_ID, engine)
        Log.i(TAG, "headless engine started for a car or voice request")
        return true
    }

    /** The playback service started or stopped. */
    fun onService(alive: Boolean) {
        serviceAlive = alive
        if (!alive) releaseIfUnused()
    }

    /** MainActivity started showing, or stopped showing, the cached engine. */
    fun onActivity(attached: Boolean, finishing: Boolean) {
        activityAttached = attached
        Log.i(TAG, if (attached) "activity adopted the cached engine" else "activity detached (finishing=$finishing)")
        if (!attached && finishing) releaseIfUnused()
    }

    /**
     * A background job (ADR-049) started or finished using the engine. The
     * engine a job started is released once no job, service or activity needs it.
     */
    @Synchronized
    fun onWork(active: Boolean) {
        workers = if (active) workers + 1 else maxOf(0, workers - 1)
        if (!active) releaseIfUnused()
    }

    private fun releaseIfUnused() {
        // After the current callbacks: the service may be restarting.
        Handler(Looper.getMainLooper()).post {
            if (serviceAlive || activityAttached || workers > 0) return@post
            val engine = cached() ?: return@post
            FlutterEngineCache.getInstance().remove(CACHE_ID)
            Log.i(TAG, "headless engine released")
            engine.destroy()
        }
    }
}
