package com.mediahro.mediahro.platform.purchases

import android.content.Context
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PurchaseResultMsg
import com.mediahro.mediahro.pigeon.StoreProductMsg
import com.mediahro.mediahro.platform.ActivityHost

/**
 * The `direct`, `foss` and `enterprise` flavours have no store rail and link
 * no billing library (docs/07 rule 5): tips go through links, so
 * `isSupported` is false and nothing else is available.
 */
object PurchasesBinding {
    fun create(@Suppress("UNUSED_PARAMETER") context: Context, @Suppress("UNUSED_PARAMETER") host: ActivityHost): PurchasesModule =
        NoPurchasesModule()
}

private class NoPurchasesModule : PurchasesModule {
    private fun unsupported(): Nothing = throw FlutterError("unsupported", "This build has no store payments")

    override suspend fun isSupported(): Boolean = false

    override suspend fun storefrontCountry(): String? = null

    override suspend fun products(ids: List<String>): List<StoreProductMsg> = emptyList()

    override suspend fun purchase(productId: String): PurchaseResultMsg = unsupported()

    override suspend fun restore(): List<PurchaseResultMsg> = emptyList()

    override suspend fun manageSubscriptions() = unsupported()

    override fun close() {}
}
