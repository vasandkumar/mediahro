package com.mediahro.mediahro.platform.imaging

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.pdf.PrintedPdfDocument
import android.provider.OpenableColumns
import java.io.FileOutputStream
import kotlin.math.ceil
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Prints images through the system print framework with [perPage] images in
 * a grid per page, fit or fill, and optional captions (IMG-015).
 */
internal class ImagePrintAdapter(
    private val context: Context,
    private val images: List<Uri>,
    private val perPage: Int,
    private val fill: Boolean,
    private val captions: Boolean,
) : PrintDocumentAdapter() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var attributes: PrintAttributes? = null

    private val pages: Int get() = ceil(images.size.toDouble() / perPage.coerceIn(1, 16)).toInt().coerceAtLeast(1)

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onLayoutCancelled()
            return
        }
        val changed = attributes != newAttributes
        attributes = newAttributes
        val info = PrintDocumentInfo.Builder("mediahro-images.pdf")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_PHOTO)
            .setPageCount(pages)
            .build()
        callback.onLayoutFinished(info, changed)
    }

    override fun onWrite(
        ranges: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal,
        callback: WriteResultCallback,
    ) {
        val attrs = attributes ?: run {
            callback.onWriteFailed("no layout")
            return
        }
        scope.launch {
            val doc = PrintedPdfDocument(context, attrs)
            try {
                val n = perPage.coerceIn(1, 16)
                for (page in 0 until pages) {
                    if (cancellationSignal.isCanceled) {
                        callback.onWriteCancelled()
                        return@launch
                    }
                    if (!wanted(ranges, page)) continue
                    val pdfPage = doc.startPage(page)
                    draw(pdfPage.canvas, pdfPage.info.pageWidth.toFloat(), pdfPage.info.pageHeight.toFloat(), page, n)
                    doc.finishPage(pdfPage)
                }
                FileOutputStream(destination.fileDescriptor).use { doc.writeTo(it) }
                callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
            } catch (e: Exception) {
                callback.onWriteFailed(e.message)
            } finally {
                doc.close()
            }
        }
    }

    override fun onFinish() {
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }

    private fun wanted(ranges: Array<out PageRange>, page: Int) =
        ranges.any { it == PageRange.ALL_PAGES || page in it.start..it.end }

    private fun draw(canvas: Canvas, pageW: Float, pageH: Float, page: Int, n: Int) {
        val margin = 36f
        val captionH = if (captions) 14f else 0f
        val cells = ImagingMath.printGrid(n, pageW, pageH, margin, if (n > 1) 12f else 0f)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 9f }
        for ((i, cell) in cells.withIndex()) {
            val uri = images.getOrNull(page * n + i) ?: break
            val bmp = try {
                decodeFor(uri, cell)
            } catch (e: Exception) {
                continue
            }
            val (src, dst) = ImagingMath.place(bmp.width, bmp.height, cell, fill, captionH)
            canvas.drawBitmap(
                bmp,
                android.graphics.Rect(src[0].toInt(), src[1].toInt(), src[2].toInt(), src[3].toInt()),
                RectF(dst[0], dst[1], dst[2], dst[3]),
                paint,
            )
            if (captions) canvas.drawText(displayName(uri), cell.left, cell.top + cell.height - 3f, text)
            bmp.recycle()
        }
    }

    /** Decodes [uri] at about 200 dpi for the cell (points are 1/72 inch). */
    private fun decodeFor(uri: Uri, cell: ImagingMath.Cell): Bitmap {
        val edge = (max(cell.width, cell.height) * 200f / 72f).toInt().coerceIn(256, 3000)
        return ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { d, info, _ ->
            d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val (w, h) = ImagingMath.targetSize(info.size.width, info.size.height, edge)
            d.setTargetSize(w, h)
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
            try {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) return it.getString(0)
                }
            } catch (e: Exception) {
                // Fall through to the path.
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: ""
    }
}
