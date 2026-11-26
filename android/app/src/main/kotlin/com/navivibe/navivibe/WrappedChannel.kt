package com.navivibe.navivibe

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayList
import java.util.concurrent.Executors

/**
 * NaviVibe Wrapped: RGBA frames from Dart become an H.264 MP4 on the phone's own encoder, and
 * finished files are saved to the gallery or handed to one app. One video at a time, off the UI thread.
 */
class WrappedChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var encoder: FilmEncoder? = null

    // share_plus's provider may read this folder, so one provider serves both.
    private val folder: File get() = File(activity.cacheDir, "share_plus").apply { mkdirs() }

    init {
        MethodChannel(messenger, "com.navivibe/wrapped").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> run(result) {
                    encoder?.release()
                    val file = File(folder, safe(call.argument<String>("name")!!) + ".mp4")
                    encoder = FilmEncoder(
                        file,
                        call.argument<Int>("width")!!,
                        call.argument<Int>("height")!!,
                        call.argument<Int>("fps")!!,
                    )
                    null
                }
                "frame" -> {
                    val rgba = call.arguments as ByteArray
                    run(result) { encoder!!.add(rgba); null }
                }
                "finish" -> run(result) {
                    val e = encoder!!
                    encoder = null
                    e.finish()
                }
                "cancel" -> run(result) {
                    encoder?.release()
                    encoder?.file?.delete()
                    encoder = null
                    null
                }
                "keep" -> run(result) {
                    val file = File(folder, safe(call.argument<String>("name")!!) + ".png")
                    file.writeBytes(call.argument<ByteArray>("bytes")!!)
                    file.path
                }
                "sendTo" -> result.success(
                    sendTo(call.argument<String>("package")!!, call.argument<List<String>>("paths")!!, call.argument<String>("mime")!!),
                )
                "save" -> run(result) { save(call.argument<List<String>>("paths")!!, call.argument<String>("mime")!!) }
                else -> result.notImplemented()
            }
        }
    }

    private fun safe(name: String) = name.replace(Regex("[^A-Za-z0-9_-]"), "_")

    private fun run(result: MethodChannel.Result, block: () -> Any?) {
        work.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("wrapped", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun sendTo(target: String, paths: List<String>, mime: String): Boolean {
        val uris = ArrayList<Uri>()
        for (p in paths) {
            uris.add(FileProvider.getUriForFile(activity, activity.packageName + ".flutter.share_provider", File(p)))
        }
        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
        intent.type = mime
        intent.setPackage(target)
        val clip = ClipData.newRawUri(null, uris[0])
        for (u in uris.drop(1)) clip.addItem(ClipData.Item(u))
        intent.clipData = clip
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun save(paths: List<String>, mime: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val video = mime.startsWith("video")
        val resolver = activity.contentResolver
        for (p in paths) {
            val file = File(p)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    (if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES) + "/NaviVibe",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val table = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val uri = resolver.insert(table, values) ?: return false
            try {
                resolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
        }
        return true
    }
}

/** RGBA frames in, MP4 out. */
private class FilmEncoder(val file: File, private val width: Int, private val height: Int, private val fps: Int) {
    private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val muxer: MediaMuxer
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var muxing = false
    private var frame = 0L
    private var released = false

    init {
        file.delete()
        muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 8_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
    }

    private fun inputBuffer(): Int {
        val giveUp = System.currentTimeMillis() + 5000
        while (true) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) return index
            drain(false)
            check(System.currentTimeMillis() < giveUp) { "The video encoder stopped responding" }
        }
    }

    fun add(rgba: ByteArray) {
        check(rgba.size == width * height * 4) { "Frame is ${rgba.size} bytes" }
        val index = inputBuffer()
        val image = codec.getInputImage(index) ?: error("The encoder takes no image")
        val y = image.planes[0]
        val cb = image.planes[1]
        val cr = image.planes[2]
        val yBuf = y.buffer
        val cbBuf = cb.buffer
        val crBuf = cr.buffer
        val row = ByteArray(width)
        val w = width
        for (j in 0 until height) {
            var p = j * w * 4
            for (i in 0 until w) {
                row[i] = (((66 * (rgba[p].toInt() and 255) + 129 * (rgba[p + 1].toInt() and 255) + 25 * (rgba[p + 2].toInt() and 255) + 128) shr 8) + 16).toByte()
                p += 4
            }
            if (j and 1 == 0) {
                var q = j * w * 4
                var cbAt = (j / 2) * cb.rowStride
                var crAt = (j / 2) * cr.rowStride
                for (i in 0 until w / 2) {
                    val r = rgba[q].toInt() and 255
                    val g = rgba[q + 1].toInt() and 255
                    val b = rgba[q + 2].toInt() and 255
                    cbBuf.put(cbAt, (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte())
                    crBuf.put(crAt, (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte())
                    cbAt += cb.pixelStride
                    crAt += cr.pixelStride
                    q += 8
                }
            }
            if (y.pixelStride == 1) {
                yBuf.position(j * y.rowStride)
                yBuf.put(row)
            } else {
                for (i in 0 until width) yBuf.put(j * y.rowStride + i * y.pixelStride, row[i])
            }
        }
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, frame * 1_000_000L / fps, 0)
        frame++
        drain(false)
    }

    private fun drain(end: Boolean) {
        val giveUp = System.currentTimeMillis() + 8000
        while (true) {
            val out = codec.dequeueOutputBuffer(info, if (end) 10_000 else 0)
            if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                track = muxer.addTrack(codec.outputFormat)
                muxer.start()
                muxing = true
            } else if (out >= 0) {
                val buffer = codec.getOutputBuffer(out)!!
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                if (info.size > 0 && muxing) {
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    muxer.writeSampleData(track, buffer, info)
                }
                codec.releaseOutputBuffer(out, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
            } else if (!end) {
                return
            } else {
                check(System.currentTimeMillis() < giveUp) { "The video could not be finished" }
            }
        }
    }

    fun finish(): String {
        try {
            codec.queueInputBuffer(inputBuffer(), 0, 0, frame * 1_000_000L / fps, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
            muxer.stop()
            muxing = false
        } finally {
            release()
        }
        return file.path
    }

    fun release() {
        if (released) return
        released = true
        try { codec.stop() } catch (_: Exception) {}
        codec.release()
        try { if (muxing) muxer.stop() } catch (_: Exception) {}
        try { muxer.release() } catch (_: Exception) {}
    }
}
