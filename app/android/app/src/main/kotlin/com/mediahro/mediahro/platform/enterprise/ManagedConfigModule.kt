package com.mediahro.mediahro.platform.enterprise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.RestrictionsManager
import androidx.core.content.ContextCompat
import com.mediahro.mediahro.pigeon.ManagedChangesStreamHandler
import com.mediahro.mediahro.pigeon.ManagedConfigHostApi
import com.mediahro.mediahro.pigeon.ManagedEntryMsg
import com.mediahro.mediahro.pigeon.ManagedKindMsg
import com.mediahro.mediahro.pigeon.ManagedSnapshotMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink

/**
 * ManagedConfigFacade on Android (B2B-001): the app restrictions an MDM sets
 * through Android Enterprise (`RestrictionsManager`), declared in
 * `res/xml/app_restrictions.xml`. Read-only; any key the MDM sets comes
 * through, whether or not it is declared. Changes arrive on
 * `ACTION_APPLICATION_RESTRICTIONS_CHANGED`.
 */
class ManagedConfigModule(private val context: Context) : ManagedConfigHostApi {
    private val restrictions = context.getSystemService(Context.RESTRICTIONS_SERVICE) as RestrictionsManager
    private var sink: PigeonEventSink<ManagedSnapshotMsg>? = null

    override fun read(): ManagedSnapshotMsg {
        val bundle = restrictions.applicationRestrictions
        return ManagedSnapshotMsg(convert(bundle.keySet().associateWith { bundle.get(it) }))
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            sink?.success(read())
        }
    }

    val changesHandler = object : ManagedChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<ManagedSnapshotMsg>) {
            this@ManagedConfigModule.sink = sink
            ContextCompat.registerReceiver(
                context,
                receiver,
                IntentFilter(Intent.ACTION_APPLICATION_RESTRICTIONS_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }

        override fun onCancel(p0: Any?) {
            stop()
        }
    }

    private fun stop() {
        runCatching { context.unregisterReceiver(receiver) }
        sink = null
    }

    fun dispose() = stop()

    companion object {
        /**
         * Restriction values to entries: strings, booleans, integers and
         * string arrays or lists. Nested bundles and unknown types are
         * dropped; the MDM schema is flat.
         */
        fun convert(values: Map<String, Any?>): List<ManagedEntryMsg> = values.mapNotNull { (key, v) ->
            when (v) {
                is String -> ManagedEntryMsg(key, ManagedKindMsg.STRING, v, null, null, null)
                is Boolean -> ManagedEntryMsg(key, ManagedKindMsg.BOOLEAN, null, v, null, null)
                is Int -> ManagedEntryMsg(key, ManagedKindMsg.INTEGER, null, null, v.toLong(), null)
                is Long -> ManagedEntryMsg(key, ManagedKindMsg.INTEGER, null, null, v, null)
                is Array<*> -> list(key, v.asList())
                is List<*> -> list(key, v)
                else -> null
            }
        }.sortedBy { it.key }

        private fun list(key: String, items: List<Any?>): ManagedEntryMsg? =
            if (items.all { it is String }) {
                ManagedEntryMsg(key, ManagedKindMsg.LIST, null, null, null, items.map { it as String })
            } else {
                null
            }
    }
}
