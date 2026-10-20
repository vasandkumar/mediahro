package com.mediahro.mediahro_engine

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

/** JNI half of the render bridge (src/main/cpp/mediahro_engine_jni.cpp). */
internal object NativeBridge {
    val loaded: Boolean =
        try {
            System.loadLibrary("mediahro_engine_jni")
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        }

    @JvmStatic external fun libmpvLoaded(): Boolean

    @JvmStatic external fun newGlobalRef(surface: Any): Long

    @JvmStatic external fun deleteGlobalRef(ref: Long)

    @JvmStatic external fun attach(mpv: Long, surfaceRef: Long, width: Int, height: Int): Int

    @JvmStatic external fun detach(mpv: Long): Int

    @JvmStatic external fun resize(mpv: Long, width: Int, height: Int): Int
}

/**
 * One video surface: a Flutter [TextureRegistry.SurfaceProducer] whose
 * `Surface` mpv draws into with `vo=gpu-next` (docs/05 §4.3). MediaCodec
 * frames stay on the GPU; Flutter composites the producer's texture.
 *
 * Surface lifecycle is handled natively and synchronously: when Flutter
 * recreates the surface (app returns from background) mpv is re-attached,
 * and before Flutter destroys it mpv is detached.
 */
private class VideoSurface(
    val mpv: Long,
    val producer: TextureRegistry.SurfaceProducer,
) : TextureRegistry.SurfaceProducer.Callback {
    var width = 1280
    var height = 720
    private var ref = 0L

    fun attach() {
        producer.setSize(width, height)
        val surface = producer.surface ?: return
        val newRef = NativeBridge.newGlobalRef(surface)
        NativeBridge.attach(mpv, newRef, width, height)
        releaseRef()
        ref = newRef
    }

    fun detach() {
        NativeBridge.detach(mpv)
        releaseRef()
    }

    fun resize(w: Int, h: Int) {
        width = w
        height = h
        producer.setSize(w, h)
        NativeBridge.resize(mpv, w, h)
    }

    private fun releaseRef() {
        if (ref != 0L) {
            NativeBridge.deleteGlobalRef(ref)
            ref = 0L
        }
    }

    override fun onSurfaceAvailable() = attach()

    override fun onSurfaceCleanup() = detach()

    fun release() {
        detach()
        producer.release()
    }
}

/** Engine plugin: render bridge channel (ADR-011). */
class MediahroEnginePlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var audioChannel: MethodChannel? = null
    private var bitPerfect: BitPerfectOutput? = null
    private var textures: TextureRegistry? = null
    private val surfaces = mutableMapOf<Long, VideoSurface>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        FontConfig.prepare(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "com.mediahro.engine/bridge")
        channel.setMethodCallHandler(this)
        textures = binding.textureRegistry
        val output = BitPerfectOutput(binding.applicationContext)
        bitPerfect = output
        audioChannel =
            MethodChannel(binding.binaryMessenger, "com.mediahro.engine/audio").also {
                it.setMethodCallHandler { call, result ->
                    if (call.method == "prefer") {
                        result.success(
                            output.prefer(
                                call.argument<Boolean>("bitPerfect") == true,
                                call.argument<Int>("sampleRate"),
                                call.argument<Int>("channels"),
                                call.argument<Int>("bitDepth"),
                            ),
                        )
                    } else {
                        result.notImplemented()
                    }
                }
            }
        // Loads the JNI helper early so FFmpeg has the JavaVM before Dart
        // creates the first mpv core.
        NativeBridge.loaded
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            "bridgeInfo" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "create" -> create(call, result)
            "resize" -> {
                val id = (call.argument<Number>("textureId"))!!.toLong()
                surfaces[id]?.resize(call.argument<Int>("width")!!, call.argument<Int>("height")!!)
                result.success(null)
            }
            "stats" -> {
                // mpv draws into the Surface itself: no native frame count.
                val id = (call.argument<Number>("textureId"))!!.toLong()
                result.success(
                    if (surfaces.containsKey(id)) mapOf("frames" to -1, "backend" to "android-surface") else null,
                )
            }
            "dispose" -> {
                val id = (call.argument<Number>("textureId"))!!.toLong()
                surfaces.remove(id)?.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun create(
        call: MethodCall,
        result: Result,
    ) {
        val registry = textures
        if (!NativeBridge.loaded || registry == null) {
            result.error("unavailable", "render bridge not loaded", null)
            return
        }
        val mpv = (call.argument<Number>("handle"))!!.toLong()
        val producer = registry.createSurfaceProducer()
        val surface = VideoSurface(mpv, producer)
        producer.setCallback(surface)
        surface.attach()
        surfaces[producer.id()] = surface
        result.success(
            mapOf(
                "textureId" to producer.id(),
                "backend" to "android-surface",
            ),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        audioChannel?.setMethodCallHandler(null)
        bitPerfect?.release()
        surfaces.values.forEach { it.release() }
        surfaces.clear()
        textures = null
    }
}
