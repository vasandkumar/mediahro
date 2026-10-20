package com.mediahro.mediahro.platform.enterprise

import android.content.Context
import com.mediahro.mediahro.pigeon.KioskHostApi
import com.mediahro.mediahro.pigeon.KioskStatesStreamHandler
import com.mediahro.mediahro.pigeon.ManagedChangesStreamHandler
import com.mediahro.mediahro.pigeon.ManagedConfigHostApi
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.plugin.common.BinaryMessenger

/**
 * Registers managed configuration and the kiosk (B2B-001/002) on an engine.
 * Kept in its own file so `PlatformModules` needs one line for it.
 */
object EnterpriseModules {
    private var managed: ManagedConfigModule? = null
    private var kiosk: KioskModule? = null

    fun register(context: Context, host: ActivityHost, messenger: BinaryMessenger) {
        managed?.dispose()
        val managedModule = ManagedConfigModule(context).also { managed = it }
        ManagedConfigHostApi.setUp(messenger, managedModule)
        ManagedChangesStreamHandler.register(messenger, managedModule.changesHandler)
        kiosk?.dispose()
        val kioskModule = KioskModule(context, host).also { kiosk = it }
        KioskHostApi.setUp(messenger, kioskModule)
        KioskStatesStreamHandler.register(messenger, kioskModule.statesHandler)
    }
}
