package com.navivibe.navivibe

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** Small on-disk cache of cover art, shared by the content provider and the widgets. */
object ArtCache {
    private const val MAX_BYTES = 3 * 1024 * 1024
    private const val MAX_FILES = 60

    private fun dir(context: Context) = File(context.cacheDir, "art").also { it.mkdirs() }

    private fun name(url: String) =
        MessageDigest.getInstance("SHA-1").digest(url.toByteArray())
            .joinToString("") { "%02x".format(it) }

    /** The cached file for [url] if it is already downloaded; never touches the network. */
    fun cached(context: Context, url: String): File? =
        File(dir(context), name(url)).takeIf { it.exists() && it.length() > 0 }

    /** Returns the cached file for an http(s) [url], downloading it if needed. Null on any failure. */
    fun fetch(context: Context, url: String): File? {
        if (!url.startsWith("http://") && !url.startsWith("https://")) return null
        val file = File(dir(context), name(url))
        if (file.exists() && file.length() > 0) return file
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.inputStream.use { input ->
                val tmp = File(file.path + ".tmp")
                tmp.outputStream().use { out ->
                    val buf = ByteArray(8192)
                    var total = 0
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        total += n
                        if (total > MAX_BYTES) { tmp.delete(); return null }
                        out.write(buf, 0, n)
                    }
                }
                if (!tmp.renameTo(file)) { tmp.delete(); return null }
            }
            prune(context)
            file
        } catch (e: Exception) {
            null
        }
    }

    private fun prune(context: Context) {
        val files = dir(context).listFiles() ?: return
        if (files.size <= MAX_FILES) return
        files.sortedBy { it.lastModified() }.take(files.size - MAX_FILES).forEach { it.delete() }
    }

    /** Decodes [file] at most [maxPx] on a side with rounded corners; null if it isn't an image. */
    fun rounded(file: File, maxPx: Int, radiusFraction: Float = 0.12f): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxPx) sample *= 2
        val src = BitmapFactory.decodeFile(
            file.path, BitmapFactory.Options().apply { inSampleSize = sample },
        ) ?: return null
        val side = minOf(src.width, src.height, maxPx)
        val out = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = side * radiusFraction
        canvas.drawRoundRect(RectF(0f, 0f, side.toFloat(), side.toFloat()), r, r, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        val left = (src.width - minOf(src.width, src.height)) / 2
        val top = (src.height - minOf(src.width, src.height)) / 2
        val sq = minOf(src.width, src.height)
        canvas.drawBitmap(
            src,
            android.graphics.Rect(left, top, left + sq, top + sq),
            RectF(0f, 0f, side.toFloat(), side.toFloat()),
            paint,
        )
        if (src !== out) src.recycle()
        return out
    }
}
