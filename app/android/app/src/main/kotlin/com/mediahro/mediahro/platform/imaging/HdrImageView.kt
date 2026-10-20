package com.mediahro.mediahro.platform.imaging

import android.content.Context
import android.graphics.ImageDecoder
import android.graphics.drawable.AnimatedImageDrawable
import android.net.Uri
import android.view.View
import android.widget.ImageView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The native HDR still view (ADR-022 for images, IMG-002): an `ImageView`
 * showing the image through `ImageDecoder` with its gain map or PQ/HLG
 * colour space kept, in a window switched to HDR colour mode by
 * `ImagingModule.openHdrView`. Creation params: `{'uri': String}`.
 */
internal class HdrImageViewFactory(private val appContext: Context) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val uri = (args as? Map<*, *>)?.get("uri") as? String
        return HdrImagePlatformView(context, appContext, uri?.let(Uri::parse))
    }

    companion object {
        /** The platform-view type Dart passes to `AndroidView`. */
        const val VIEW_TYPE = "mediahro/hdr_image"

        /** Decode edge cap: a 4096 px RGBA bitmap is 64 MB; F16 twice that. */
        const val MAX_EDGE = 4096
    }
}

private class HdrImagePlatformView(context: Context, appContext: Context, uri: Uri?) : PlatformView {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val image = ImageView(context).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        contentDescription = null
    }

    init {
        if (uri != null) {
            scope.launch {
                val drawable = try {
                    withContext(Dispatchers.IO) {
                        ImageDecoder.decodeDrawable(ImageDecoder.createSource(appContext.contentResolver, uri)) { d, info, _ ->
                            val (w, h) = ImagingMath.targetSize(info.size.width, info.size.height, HdrImageViewFactory.MAX_EDGE)
                            if (w != info.size.width) d.setTargetSize(w, h)
                        }
                    }
                } catch (e: Exception) {
                    null
                }
                image.setImageDrawable(drawable)
                (drawable as? AnimatedImageDrawable)?.start()
            }
        }
    }

    override fun getView(): View = image

    override fun dispose() {
        scope.cancel()
        (image.drawable as? AnimatedImageDrawable)?.stop()
        image.setImageDrawable(null)
    }
}
