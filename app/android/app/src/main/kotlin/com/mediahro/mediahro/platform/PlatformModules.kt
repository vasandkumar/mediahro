package com.mediahro.mediahro.platform

import android.content.Context
import com.mediahro.mediahro.pigeon.AudioDeviceChangesStreamHandler
import com.mediahro.mediahro.pigeon.AudioInterruptionsStreamHandler
import com.mediahro.mediahro.pigeon.AudioOutputHostApi
import com.mediahro.mediahro.pigeon.DisplayChangesStreamHandler
import com.mediahro.mediahro.pigeon.DisplayHostApi
import com.mediahro.mediahro.pigeon.PipHostApi
import com.mediahro.mediahro.pigeon.PipStatesStreamHandler
import com.mediahro.mediahro.pigeon.MediaSessionHostApi
import com.mediahro.mediahro.pigeon.PhotoLibraryHostApi
import com.mediahro.mediahro.pigeon.RemoteCommandsStreamHandler
import com.mediahro.mediahro.pigeon.StorageChangesStreamHandler
import com.mediahro.mediahro.pigeon.StorageHostApi
import com.mediahro.mediahro.platform.display.DisplayModule
import com.mediahro.mediahro.platform.display.PipModule
import com.mediahro.mediahro.platform.media.AudioOutputModule
import com.mediahro.mediahro.platform.media.MediaSessionModule
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
    private var session: MediaSessionModule? = null

    private var display: DisplayModule? = null

    /** The live PiP module (MainActivity forwards PiP callbacks to it). */
    var pip: PipModule? = null
        private set

    /** The live audio module (debug hooks drive its focus listener). */
    var audio: AudioOutputModule? = null
        private set

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

        session?.dispose()
        val sessionModule = MediaSessionModule(context.applicationContext, host).also { session = it }
        MediaSessionHostApi.setUp(messenger, sessionModule)
        RemoteCommandsStreamHandler.register(messenger, sessionModule.commandsHandler)

        audio?.dispose()
        val audioModule = AudioOutputModule(context.applicationContext).also { audio = it }
        AudioOutputHostApi.setUp(messenger, audioModule)
        AudioDeviceChangesStreamHandler.register(messenger, audioModule.devicesHandler)
        AudioInterruptionsStreamHandler.register(messenger, audioModule.interruptionsHandler)

        display?.dispose()
        val displayModule = DisplayModule(context.applicationContext, host).also { display = it }
        DisplayHostApi.setUp(messenger, displayModule)
        DisplayChangesStreamHandler.register(messenger, displayModule.changesHandler)

        val pipModule = PipModule(context.applicationContext, host).also { pip = it }
        PipHostApi.setUp(messenger, pipModule)
        PipStatesStreamHandler.register(messenger, pipModule.statesHandler)
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
