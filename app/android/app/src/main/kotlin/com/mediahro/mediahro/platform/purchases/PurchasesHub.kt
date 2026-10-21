package com.mediahro.mediahro.platform.purchases

import android.os.Handler
import android.os.Looper
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.PurchaseResultMsg
import com.mediahro.mediahro.pigeon.PurchaseUpdatesStreamHandler
import com.mediahro.mediahro.pigeon.PurchasesHostApi

/** The Android half of `PurchasesFacade`; closed when its engine goes away. */
interface PurchasesModule : PurchasesHostApi, AutoCloseable

/** Purchases finished outside a `purchase` call (deferred approval, renewals). */
object PurchasesHub {
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var sink: PigeonEventSink<PurchaseResultMsg>? = null

    val handler = object : PurchaseUpdatesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<PurchaseResultMsg>) {
            this@PurchasesHub.sink = sink
        }

        override fun onCancel(p0: Any?) {
            sink = null
        }
    }

    fun publish(result: PurchaseResultMsg) {
        main.post { sink?.success(result) }
    }
}
