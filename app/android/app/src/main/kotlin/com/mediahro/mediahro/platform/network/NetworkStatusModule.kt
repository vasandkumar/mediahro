package com.mediahro.mediahro.platform.network

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.mediahro.mediahro.pigeon.MulticastHostApi
import com.mediahro.mediahro.pigeon.NetworkChangesStreamHandler
import com.mediahro.mediahro.pigeon.NetworkStateMsg
import com.mediahro.mediahro.pigeon.NetworkStatusHostApi
import com.mediahro.mediahro.pigeon.NetworkTransportMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/**
 * NetworkStatusFacade on Android (NET-018, NET-019): the default network's
 * transport, whether it is metered (no NOT_METERED or TEMPORARILY_NOT_METERED
 * capability), and Data Saver as "constrained".
 */
class NetworkStatusModule(private val context: Context) : NetworkStatusHostApi {
    private val cm = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    override fun current(): NetworkStateMsg = stateOf(cm.getNetworkCapabilities(cm.activeNetwork))

    private fun stateOf(caps: NetworkCapabilities?): NetworkStateMsg {
        val constrained = cm.restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
        if (caps == null || !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            return NetworkStateMsg(NetworkTransportMsg.NONE, false, constrained)
        }
        val transport = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkTransportMsg.ETHERNET
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkTransportMsg.WIFI
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkTransportMsg.CELLULAR
            else -> NetworkTransportMsg.OTHER
        }
        val notMetered = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) ||
            (
                Build.VERSION.SDK_INT >= 30 &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_TEMPORARILY_NOT_METERED)
                )
        return NetworkStateMsg(transport, !notMetered, constrained)
    }

    private var sink: PigeonEventSink<NetworkStateMsg>? = null
    private var last: NetworkStateMsg? = null

    private fun publish(state: NetworkStateMsg) {
        if (state == last) return
        last = state
        sink?.success(state)
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            main.post { publish(stateOf(caps)) }
        }

        override fun onLost(network: Network) {
            main.post { publish(current()) }
        }
    }

    private val dataSaver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = publish(current())
    }

    val changesHandler = object : NetworkChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<NetworkStateMsg>) {
            this@NetworkStatusModule.sink = sink
            last = null
            cm.registerDefaultNetworkCallback(callback, main)
            ContextCompat.registerReceiver(
                context,
                dataSaver,
                IntentFilter(ConnectivityManager.ACTION_RESTRICT_BACKGROUND_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            publish(current())
        }

        override fun onCancel(p0: Any?) {
            stop()
            sink = null
        }
    }

    private fun stop() {
        runCatching { cm.unregisterNetworkCallback(callback) }
        runCatching { context.unregisterReceiver(dataSaver) }
    }

    fun dispose() = stop()
}

/**
 * MulticastFacade on Android (NET-001/005 discovery): a Wi-Fi multicast lock
 * per lease, so SSDP, mDNS and WS-Discovery packets are not filtered. Each
 * lease is its own non-counted lock.
 */
class MulticastModule(context: Context) : MulticastHostApi {
    private val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
    private val leases = ConcurrentHashMap<Long, WifiManager.MulticastLock>()
    private val ids = AtomicLong(1)

    override fun acquire(tag: String): Long {
        val lock = wifi.createMulticastLock(tag.ifBlank { "mediahro" }).apply {
            setReferenceCounted(false)
            acquire()
        }
        val id = ids.getAndIncrement()
        leases[id] = lock
        return id
    }

    override fun release(leaseId: Long) {
        leases.remove(leaseId)?.let { if (it.isHeld) it.release() }
    }

    /** Debug read-back: leases currently held. */
    val held: Int get() = leases.values.count { it.isHeld }

    fun dispose() {
        leases.values.forEach { if (it.isHeld) it.release() }
        leases.clear()
    }
}
