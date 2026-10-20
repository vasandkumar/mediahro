package com.mediahro.mediahro.platform

import android.content.Context
import com.mediahro.mediahro.pigeon.AudioDeviceChangesStreamHandler
import com.mediahro.mediahro.pigeon.AudioInterruptionsStreamHandler
import com.mediahro.mediahro.pigeon.AlarmHostApi
import com.mediahro.mediahro.pigeon.AlarmsFiredStreamHandler
import com.mediahro.mediahro.pigeon.AppIntentsStreamHandler
import com.mediahro.mediahro.pigeon.AudioOutputHostApi
import com.mediahro.mediahro.pigeon.IntentsHostApi
import com.mediahro.mediahro.pigeon.OpenRequestsStreamHandler
import com.mediahro.mediahro.pigeon.SystemHostApi
import com.mediahro.mediahro.pigeon.MediaBrowseFlutterApi
import com.mediahro.mediahro.pigeon.HomeWidgetsHostApi
import com.mediahro.mediahro.pigeon.MediaBrowseHostApi
import com.mediahro.mediahro.pigeon.AuthBrowserHostApi
import com.mediahro.mediahro.pigeon.MulticastHostApi
import com.mediahro.mediahro.pigeon.NetworkChangesStreamHandler
import com.mediahro.mediahro.pigeon.NetworkStatusHostApi
import com.mediahro.mediahro.pigeon.BiometricsHostApi
import com.mediahro.mediahro.pigeon.CaptionStyleChangesStreamHandler
import com.mediahro.mediahro.pigeon.CaptionStyleHostApi
import com.mediahro.mediahro.pigeon.SecureStorageHostApi
import com.mediahro.mediahro.pigeon.SftpHostApi
import com.mediahro.mediahro.pigeon.SpeechHostApi
import com.mediahro.mediahro.pigeon.TlsEventsStreamHandler
import com.mediahro.mediahro.pigeon.TlsServerHostApi
import com.mediahro.mediahro.pigeon.TlsSocketHostApi
import com.mediahro.mediahro.pigeon.DisplayChangesStreamHandler
import com.mediahro.mediahro.pigeon.DisplayHostApi
import com.mediahro.mediahro.pigeon.PipHostApi
import com.mediahro.mediahro.pigeon.PowerStatusChangesStreamHandler
import com.mediahro.mediahro.pigeon.PowerStatusHostApi
import com.mediahro.mediahro.pigeon.PipStatesStreamHandler
import com.mediahro.mediahro.pigeon.MediaSessionHostApi
import com.mediahro.mediahro.pigeon.PhotoLibraryHostApi
import com.mediahro.mediahro.pigeon.RemoteCommandsStreamHandler
import com.mediahro.mediahro.pigeon.StorageChangesStreamHandler
import com.mediahro.mediahro.pigeon.StorageHostApi
import com.mediahro.mediahro.platform.captions.CaptionStyleModule
import com.mediahro.mediahro.platform.display.DisplayModule
import com.mediahro.mediahro.platform.display.PipModule
import com.mediahro.mediahro.platform.display.PowerStatusModule
import com.mediahro.mediahro.platform.media.AlarmHub
import com.mediahro.mediahro.platform.media.AlarmModule
import com.mediahro.mediahro.platform.media.AudioOutputModule
import com.mediahro.mediahro.platform.media.BrowseHub
import com.mediahro.mediahro.platform.media.MediaBrowseModule
import com.mediahro.mediahro.platform.media.MediaSessionModule
import com.mediahro.mediahro.platform.network.AuthBrowserModule
import com.mediahro.mediahro.platform.network.MulticastModule
import com.mediahro.mediahro.platform.network.NetworkStatusModule
import com.mediahro.mediahro.platform.security.BiometricsModule
import com.mediahro.mediahro.platform.security.SecureStorageModule
import com.mediahro.mediahro.platform.sftp.SftpModule
import com.mediahro.mediahro.platform.text.SpeechModule
import com.mediahro.mediahro.platform.storage.PhotoLibraryModule
import com.mediahro.mediahro.platform.system.IncomingIntents
import com.mediahro.mediahro.platform.system.IntentsModule
import com.mediahro.mediahro.platform.system.SystemModule
import com.mediahro.mediahro.platform.tls.TlsHub
import com.mediahro.mediahro.platform.widgets.HomeWidgetsModule
import com.mediahro.mediahro.platform.tls.TlsServerModule
import com.mediahro.mediahro.platform.tls.TlsSocketModule
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
    private var speech: SpeechModule? = null
    private var powerStatus: PowerStatusModule? = null
    private var captions: CaptionStyleModule? = null
    private var tlsServer: TlsServerModule? = null
    private var sftp: SftpModule? = null

    /** The live PiP module (MainActivity forwards PiP callbacks to it). */
    var pip: PipModule? = null
        private set

    private var network: NetworkStatusModule? = null

    /** The live multicast module (debug hooks read its leases). */
    var multicast: MulticastModule? = null
        private set

    /** The live auth browser (MainActivity reports resumes for cancel detection). */
    var authBrowser: AuthBrowserModule? = null
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

        // Android Auto and voice (MUS-013): a new engine registers its provider again.
        BrowseHub.registered = false
        BrowseHub.flutter = MediaBrowseFlutterApi(messenger)
        MediaBrowseHostApi.setUp(messenger, MediaBrowseModule())

        AlarmHostApi.setUp(messenger, AlarmModule(context.applicationContext, host))
        AlarmsFiredStreamHandler.register(messenger, AlarmHub.handler)
        HomeWidgetsHostApi.setUp(messenger, HomeWidgetsModule(context.applicationContext))

        // Open with, share targets, shortcuts and App Actions (CORE-003, SYS-003/004).
        SystemHostApi.setUp(messenger, SystemModule(host))
        IntentsHostApi.setUp(messenger, IntentsModule(context.applicationContext))
        OpenRequestsStreamHandler.register(messenger, IncomingIntents.openHandler)
        AppIntentsStreamHandler.register(messenger, IncomingIntents.intentHandler)

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

        speech?.dispose()
        SpeechHostApi.setUp(messenger, SpeechModule(context.applicationContext).also { speech = it })

        powerStatus?.dispose()
        val powerModule = PowerStatusModule(context.applicationContext).also { powerStatus = it }
        PowerStatusHostApi.setUp(messenger, powerModule)
        PowerStatusChangesStreamHandler.register(messenger, powerModule.changesHandler)

        captions?.dispose()
        val captionModule = CaptionStyleModule(context.applicationContext).also { captions = it }
        CaptionStyleHostApi.setUp(messenger, captionModule)
        CaptionStyleChangesStreamHandler.register(messenger, captionModule.changesHandler)

        val secureStorage = SecureStorageModule(context.applicationContext, host)
        SecureStorageHostApi.setUp(messenger, secureStorage)
        BiometricsHostApi.setUp(messenger, BiometricsModule(context.applicationContext, host))

        network?.dispose()
        val networkModule = NetworkStatusModule(context.applicationContext).also { network = it }
        NetworkStatusHostApi.setUp(messenger, networkModule)
        NetworkChangesStreamHandler.register(messenger, networkModule.changesHandler)

        multicast?.dispose()
        MulticastHostApi.setUp(messenger, MulticastModule(context.applicationContext).also { multicast = it })

        AuthBrowserHostApi.setUp(messenger, AuthBrowserModule(host).also { authBrowser = it })

        // A new engine starts with no connections of the old one.
        TlsHub.closeAll()
        tlsServer?.dispose()
        TlsSocketHostApi.setUp(messenger, TlsSocketModule())
        TlsServerHostApi.setUp(messenger, TlsServerModule().also { tlsServer = it })
        TlsEventsStreamHandler.register(messenger, TlsHub.eventsHandler)

        sftp?.dispose()
        SftpHostApi.setUp(messenger, SftpModule(secureStorage).also { sftp = it })
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
