package com.mediahro.mediahro.platform

import android.content.Context
import com.mediahro.mediahro.pigeon.PhotoLibraryHostApi
import com.mediahro.mediahro.pigeon.StorageChangesStreamHandler
import com.mediahro.mediahro.pigeon.StorageHostApi
import com.mediahro.mediahro.platform.storage.PhotoLibraryModule
import com.mediahro.mediahro.platform.storage.StorageModule
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers every Android platform module (docs/05 §8) on a Flutter
 * engine. Feature code reaches them only through the typed facades in
 * `app/lib/platform/android/`.
 */
object PlatformModules {
    @Volatile private var activityHost: ActivityHost? = null
    private var storage: StorageModule? = null

    fun host(context: Context): ActivityHost =
        activityHost ?: synchronized(this) {
            activityHost ?: ActivityHost(context.applicationContext).also { activityHost = it }
        }

    fun register(context: Context, engine: FlutterEngine) {
        val host = host(context)
        val messenger = engine.dartExecutor.binaryMessenger
        storage?.dispose()
        val storageModule = StorageModule(context.applicationContext, host).also { storage = it }
        StorageHostApi.setUp(messenger, storageModule)
        StorageChangesStreamHandler.register(messenger, storageModule.changesHandler)
        PhotoLibraryHostApi.setUp(messenger, PhotoLibraryModule(context.applicationContext, host))
        debugHooks(host, engine)
    }

    /** Debug builds add integration-test hooks (src/debug); absent in release. */
    private fun debugHooks(host: ActivityHost, engine: FlutterEngine) {
        try {
            Class.forName("com.mediahro.mediahro.testing.DebugHooks")
                .getMethod("install", ActivityHost::class.java, FlutterEngine::class.java)
                .invoke(null, host, engine)
        } catch (e: ClassNotFoundException) {
            // Release and profile builds.
        }
    }
}
