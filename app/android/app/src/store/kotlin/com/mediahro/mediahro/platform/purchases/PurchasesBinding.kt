package com.mediahro.mediahro.platform.purchases

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.GetBillingConfigParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.consumePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PurchaseResultMsg
import com.mediahro.mediahro.pigeon.PurchaseStateMsg
import com.mediahro.mediahro.pigeon.StoreProductMsg
import com.mediahro.mediahro.platform.ActivityHost
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/** The `store` flavour: Play Billing for tips and the supporter subscription (SUP-002, docs/07 rule 5). */
object PurchasesBinding {
    fun create(context: Context, host: ActivityHost): PurchasesModule = PlayBillingModule(context.applicationContext, host)
}

/**
 * PurchasesFacade on Android. Tips are consumable in-app products: a
 * purchase is consumed straight away so it can be bought again; the optional
 * supporter subscription is acknowledged. Nothing unlocks anything but
 * cosmetics (SUP-004), so purchases are not verified on a server; the app has
 * none. The Billing Library only talks to the Play Store app on the device.
 */
internal class PlayBillingModule(
    private val context: Context,
    private val host: ActivityHost,
) : PurchasesModule, PurchasesUpdatedListener {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val connecting = Mutex()

    private val main = Handler(Looper.getMainLooper())

    private fun newClient(): BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    /** Built on the first call and rebuilt after an idle disconnect; nothing connects at app start. */
    private var client: BillingClient = newClient()

    /** Ends the connection once the tip screen has been quiet for [IDLE_MS] and no purchase is open. */
    private val idle = Runnable {
        if (waiting == null && client.isReady) {
            client.endConnection()
            client = newClient()
        }
    }

    private fun touch() {
        main.removeCallbacks(idle)
        main.postDelayed(idle, IDLE_MS)
    }

    /** Product id to `ProductType`, learned from product queries. */
    private val kinds = ConcurrentHashMap<String, String>()

    /** The `purchase` call waiting for the sheet's outcome. */
    @Volatile private var waiting: Pair<String, CompletableDeferred<PurchaseResultMsg>>? = null

    private suspend fun ready(): Boolean {
        touch()
        if (client.isReady) return true
        return connecting.withLock {
            if (client.isReady) return@withLock true
            suspendCancellableCoroutine { cont ->
                client.startConnection(object : BillingClientStateListener {
                    override fun onBillingSetupFinished(result: BillingResult) {
                        if (cont.isActive) cont.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                    }

                    override fun onBillingServiceDisconnected() {
                        // Automatic reconnection is enabled; the next call connects again.
                    }
                })
            }
        }
    }

    private suspend fun requireReady() {
        if (!ready()) throw FlutterError("unavailable", "The Play Store is not available")
    }

    override suspend fun isSupported(): Boolean = ready()

    override suspend fun storefrontCountry(): String? {
        if (!ready()) return null
        return suspendCancellableCoroutine { cont ->
            client.getBillingConfigAsync(GetBillingConfigParams.newBuilder().build()) { result, config ->
                // Used once for link gating and never stored (Play policy).
                val code = if (result.responseCode == BillingClient.BillingResponseCode.OK) config?.countryCode else null
                if (cont.isActive) cont.resume(code)
            }
        }
    }

    private suspend fun detailsOf(type: String, ids: List<String>): List<ProductDetails> {
        val products = ids.map {
            QueryProductDetailsParams.Product.newBuilder().setProductId(it).setProductType(type).build()
        }
        val result = client.queryProductDetails(QueryProductDetailsParams.newBuilder().setProductList(products).build())
        if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) return emptyList()
        return result.productDetailsList.orEmpty().onEach { kinds[it.productId] = type }
    }

    private suspend fun allDetails(ids: List<String>): List<ProductDetails> {
        if (ids.isEmpty()) return emptyList()
        return detailsOf(BillingClient.ProductType.INAPP, ids) + detailsOf(BillingClient.ProductType.SUBS, ids)
    }

    override suspend fun products(ids: List<String>): List<StoreProductMsg> {
        if (!ready()) return emptyList()
        return allDetails(ids.distinct()).map { d ->
            val sub = d.productType == BillingClient.ProductType.SUBS
            val phase = d.subscriptionOfferDetails?.firstOrNull()?.pricingPhases?.pricingPhaseList?.lastOrNull()
            StoreProductMsg(
                id = d.productId,
                subscription = sub,
                title = d.title,
                displayPrice = if (sub) phase?.formattedPrice.orEmpty() else priceOf(d),
                subscriptionPeriod = phase?.billingPeriod?.takeIf { sub },
            )
        }
    }

    private fun priceOf(d: ProductDetails): String =
        d.oneTimePurchaseOfferDetailsList?.firstOrNull()?.formattedPrice
            ?: d.oneTimePurchaseOfferDetails?.formattedPrice.orEmpty()

    override suspend fun purchase(productId: String): PurchaseResultMsg {
        requireReady()
        val details = allDetails(listOf(productId)).firstOrNull()
            ?: throw FlutterError("notFound", "Unknown product", productId)
        val activity = host.requireActivity()
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
        val token = if (details.productType == BillingClient.ProductType.SUBS) {
            details.subscriptionOfferDetails?.firstOrNull()?.offerToken
        } else {
            details.oneTimePurchaseOfferDetailsList?.firstOrNull()?.offerToken
        }
        if (token != null) params.setOfferToken(token)
        val outcome = CompletableDeferred<PurchaseResultMsg>()
        waiting = productId to outcome
        try {
            val launched = withContext(Dispatchers.Main) {
                client.launchBillingFlow(
                    activity,
                    BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params.build())).build(),
                )
            }
            if (launched.responseCode != BillingClient.BillingResponseCode.OK) {
                return PurchaseResultMsg(productId, stateOf(launched.responseCode), null)
            }
            return outcome.await()
        } finally {
            waiting = null
        }
    }

    /** The sheet's outcome, and purchases finished outside a `purchase` call. */
    override fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        scope.launch {
            val results = if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
                purchases.flatMap { settle(it, restored = false) }
            } else {
                // A cancel or failure names no product: it belongs to the waiting call.
                val w = waiting
                if (w == null) emptyList() else listOf(PurchaseResultMsg(w.first, stateOf(result.responseCode), null))
            }
            for (r in results) {
                val w = waiting
                if (w != null && w.first == r.productId && !w.second.isCompleted) {
                    w.second.complete(r)
                } else {
                    PurchasesHub.publish(r)
                }
            }
        }
    }

    /** Consumes a tip or acknowledges a subscription once the store says it is paid. */
    private suspend fun settle(p: Purchase, restored: Boolean): List<PurchaseResultMsg> {
        val ids = p.products
        if (p.purchaseState == Purchase.PurchaseState.PENDING) {
            return ids.map { PurchaseResultMsg(it, PurchaseStateMsg.PENDING, p.orderId) }
        }
        if (p.purchaseState != Purchase.PurchaseState.PURCHASED) {
            return ids.map { PurchaseResultMsg(it, PurchaseStateMsg.FAILED, p.orderId) }
        }
        val known = ids.all { kinds.containsKey(it) }
        if (!known) allDetails(ids)
        val subscription = ids.any { kinds[it] == BillingClient.ProductType.SUBS }
        val ok = try {
            if (subscription) {
                p.isAcknowledged || client.acknowledgePurchase(
                    AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.purchaseToken).build(),
                ).responseCode == BillingClient.BillingResponseCode.OK
            } else {
                client.consumePurchase(ConsumeParams.newBuilder().setPurchaseToken(p.purchaseToken).build())
                    .billingResult.responseCode == BillingClient.BillingResponseCode.OK
            }
        } catch (e: Exception) {
            false
        }
        val state = when {
            !ok -> PurchaseStateMsg.FAILED
            restored -> PurchaseStateMsg.RESTORED
            else -> PurchaseStateMsg.PURCHASED
        }
        return ids.map { PurchaseResultMsg(it, state, p.orderId) }
    }

    override suspend fun restore(): List<PurchaseResultMsg> {
        requireReady()
        val out = mutableListOf<PurchaseResultMsg>()
        for (type in listOf(BillingClient.ProductType.SUBS, BillingClient.ProductType.INAPP)) {
            val owned = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build())
            if (owned.billingResult.responseCode != BillingClient.BillingResponseCode.OK) continue
            for (p in owned.purchasesList) {
                kinds.putIfAbsent(p.products.firstOrNull() ?: continue, type)
                out += settle(p, restored = true)
            }
        }
        return out
    }

    override suspend fun manageSubscriptions() {
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/account/subscriptions?package=${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    override fun close() {
        main.removeCallbacks(idle)
        scope.cancel()
        waiting?.second?.cancel()
        if (client.isReady) client.endConnection()
    }

    companion object {
        /** The connection ends this long after the last call (the user left the tip screen). */
        const val IDLE_MS = 60_000L

        fun stateOf(code: Int): PurchaseStateMsg = when (code) {
            BillingClient.BillingResponseCode.OK -> PurchaseStateMsg.PURCHASED
            BillingClient.BillingResponseCode.USER_CANCELED -> PurchaseStateMsg.CANCELLED
            else -> PurchaseStateMsg.FAILED
        }
    }
}
