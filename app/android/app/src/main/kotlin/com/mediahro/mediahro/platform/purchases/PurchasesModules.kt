package com.mediahro.mediahro.platform.purchases

import android.content.Context
import com.mediahro.mediahro.pigeon.PurchaseUpdatesStreamHandler
import com.mediahro.mediahro.pigeon.PurchasesHostApi
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.plugin.common.BinaryMessenger

/**
 * Registers tips and the supporter subscription (SUP-002) on an engine: Play
 * Billing in the `store` flavour, a no-op elsewhere (`PurchasesBinding`).
 * Nothing connects to the Play Store here; the first facade call does.
 */
object PurchasesModules {
    private var purchases: PurchasesModule? = null

    fun register(context: Context, host: ActivityHost, messenger: BinaryMessenger) {
        purchases?.close()
        val module = PurchasesBinding.create(context, host).also { purchases = it }
        PurchasesHostApi.setUp(messenger, module)
        PurchaseUpdatesStreamHandler.register(messenger, PurchasesHub.handler)
    }
}
