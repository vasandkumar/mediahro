package com.mediahro.mediahro.platform.display

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.content.ContextCompat
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.pigeon.PowerStatusChangesStreamHandler
import com.mediahro.mediahro.pigeon.PowerStatusHostApi
import com.mediahro.mediahro.pigeon.PowerStatusMsg
import com.mediahro.mediahro.pigeon.ThermalLevelMsg

/**
 * PowerStatusFacade on Android (ADR-033): the thermal status and battery
 * saver, so the player steps shaders (VID-038) and interpolation (VID-039)
 * down before the system throttles the device.
 */
class PowerStatusModule(private val context: Context) : PowerStatusHostApi {
    private val power = context.getSystemService(PowerManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    override fun current(): PowerStatusMsg = PowerStatusMsg(levelOf(power.currentThermalStatus), power.isPowerSaveMode)

    private var sink: PigeonEventSink<PowerStatusMsg>? = null
    private var last: PowerStatusMsg? = null

    private fun publish() {
        val now = current()
        if (now == last) return
        last = now
        sink?.success(now)
    }

    private val thermal = PowerManager.OnThermalStatusChangedListener { publish() }

    private val saver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = publish()
    }

    val changesHandler = object : PowerStatusChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<PowerStatusMsg>) {
            this@PowerStatusModule.sink = sink
            last = null
            power.addThermalStatusListener(ContextCompat.getMainExecutor(context), thermal)
            ContextCompat.registerReceiver(
                context,
                saver,
                IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            main.post { publish() }
        }

        override fun onCancel(p0: Any?) {
            stop()
            sink = null
        }
    }

    private fun stop() {
        runCatching { power.removeThermalStatusListener(thermal) }
        runCatching { context.unregisterReceiver(saver) }
    }

    fun dispose() = stop()

    companion object {
        /**
         * Android's seven THERMAL_STATUS_* steps on the four shared levels:
         * light throttling is "fair", moderate is "serious", and severe or
         * worse is "critical" (step everything down).
         */
        fun levelOf(status: Int): ThermalLevelMsg = when (status) {
            PowerManager.THERMAL_STATUS_NONE -> ThermalLevelMsg.NOMINAL
            PowerManager.THERMAL_STATUS_LIGHT -> ThermalLevelMsg.FAIR
            PowerManager.THERMAL_STATUS_MODERATE -> ThermalLevelMsg.SERIOUS
            else -> ThermalLevelMsg.CRITICAL
        }
    }
}
