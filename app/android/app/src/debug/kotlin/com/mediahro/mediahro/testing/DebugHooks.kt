package com.mediahro.mediahro.testing

import android.media.MediaScannerConnection
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import com.mediahro.mediahro.platform.ActivityHost
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.StandardMessageCodec
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Debug-only integration-test hooks (lane C4a). `mediahro.test/pickers`
 * queues answers for the next system pickers: a URI string (or a list of
 * them for multi-select), or null for "cancelled". Only picker contracts are
 * answered; permission prompts and consent dialogs stay real.
 */
object DebugHooks {
    private val queue = ConcurrentLinkedQueue<Any>()
    private object Cancelled

    @Volatile private var lastContract: String? = null

    @JvmStatic
    fun install(host: ActivityHost, engine: FlutterEngine) {
        BasicMessageChannel(engine.dartExecutor.binaryMessenger, "mediahro.test/pickers", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                // "last": the contract that answered the latest picker call.
                if (message == "last") {
                    reply.reply(lastContract)
                    return@setMessageHandler
                }
                (message as? List<*>)?.forEach { queue.add(it ?: Cancelled) }
                if (message == null) queue.clear()
                reply.reply(queue.size)
            }
        // Indexes files the test wrote through the file system, as the OS
        // does for files other apps create (rows otherwise stay pending).
        BasicMessageChannel(engine.dartExecutor.binaryMessenger, "mediahro.test/scan", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val paths = (message as List<*>).map { it as String }.toTypedArray()
                val left = java.util.concurrent.atomic.AtomicInteger(paths.size)
                val main = android.os.Handler(android.os.Looper.getMainLooper())
                MediaScannerConnection.scanFile(host.context, paths, null) { _, _ ->
                    if (left.decrementAndGet() == 0) main.post { reply.reply(paths.size) }
                }
            }
        host.fake = { contract, _ -> answer(contract) }
        SessionHooks.install(host.context, engine.dartExecutor.binaryMessenger)
        WindowHooks.install(host, engine.dartExecutor.binaryMessenger)
        SecureHooks.install(host.context, engine.dartExecutor.binaryMessenger)
        NetHooks.install(host.context, engine.dartExecutor.binaryMessenger)
    }

    private fun answer(contract: ActivityResultContract<*, *>): Result<Any?>? {
        val picker = contract is ActivityResultContracts.OpenDocumentTree ||
            contract is ActivityResultContracts.OpenDocument ||
            contract is ActivityResultContracts.OpenMultipleDocuments ||
            contract is ActivityResultContracts.PickVisualMedia ||
            contract is ActivityResultContracts.PickMultipleVisualMedia ||
            contract is ActivityResultContracts.CreateDocument
        if (!picker) return null
        val next = queue.poll() ?: return null
        lastContract = contract.javaClass.simpleName
        val multi = contract is ActivityResultContracts.OpenMultipleDocuments ||
            contract is ActivityResultContracts.PickMultipleVisualMedia
        return Result.success(
            when {
                next === Cancelled -> if (multi) emptyList<Uri>() else null
                next is List<*> -> next.map { Uri.parse(it as String) }
                multi -> listOf(Uri.parse(next as String))
                else -> Uri.parse(next as String)
            },
        )
    }
}
