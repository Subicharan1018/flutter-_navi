package com.navivibe.navivibe

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Storage Access Framework bridge for the "Local music" setting.
 *
 * The user picks a folder once; the grant is persisted, so the app can list
 * and read it on every launch without any storage permission (this is the
 * scoped-storage way on Android 11+). Dart never sees file contents here: it
 * gets document URIs to hand to the player, and `/proc/self/fd/N` paths to
 * read tags with `dart:io`.
 */
class SafChannel(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val PICK_REQUEST = 7301
        private val AUDIO_EXT = setOf(
            "mp3", "flac", "m4a", "aac", "ogg", "oga", "opus", "wav", "aiff", "aif", "wma", "ape", "mka", "webm",
        )
        private val ART_NAMES = setOf("cover", "folder", "front", "album", "albumart")
        private val ART_EXT = setOf("jpg", "jpeg", "png", "webp")
    }

    private val io = Executors.newFixedThreadPool(2)
    private val open = ConcurrentHashMap<Int, ParcelFileDescriptor>()
    private val nextToken = AtomicInteger(1)
    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "com.navivibe/saf").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTree" -> pickTree(result)
                "releaseTree" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    try {
                        activity.contentResolver.releasePersistableUriPermission(
                            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                "hasAccess" -> {
                    val uri = call.argument<String>("uri")
                    result.success(activity.contentResolver.persistedUriPermissions.any {
                        it.uri.toString() == uri && it.isReadPermission
                    })
                }
                "listTree" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    io.execute {
                        try {
                            val rows = ArrayList<Map<String, Any>>()
                            walk(uri, DocumentsContract.getTreeDocumentId(uri), rows)
                            activity.runOnUiThread { result.success(rows) }
                        } catch (e: Exception) {
                            activity.runOnUiThread { result.error("list_failed", e.message, null) }
                        }
                    }
                }
                "openFd" -> {
                    val uri = Uri.parse(call.argument<String>("uri"))
                    try {
                        val pfd = activity.contentResolver.openFileDescriptor(uri, "r")
                        if (pfd == null) {
                            result.error("open_failed", "No descriptor", null)
                        } else {
                            val token = nextToken.getAndIncrement()
                            open[token] = pfd
                            result.success(mapOf("token" to token, "path" to "/proc/self/fd/${pfd.fd}"))
                        }
                    } catch (e: Exception) {
                        result.error("open_failed", e.message, null)
                    }
                }
                "closeFd" -> {
                    val token = call.argument<Int>("token")
                    if (token != null) {
                        try {
                            open.remove(token)?.close()
                        } catch (_: Exception) {
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A folder picker is already open", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        activity.startActivityForResult(intent, PICK_REQUEST)
    }

    /** Called from MainActivity.onActivityResult. Returns true when handled. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pending
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result?.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: Exception) {
            result?.error("permission", e.message, null)
            return true
        }
        val docId = DocumentsContract.getTreeDocumentId(uri)
        val name = docId.substringAfterLast(':').substringAfterLast('/').ifEmpty { "Music" }
        result?.success(mapOf("uri" to uri.toString(), "name" to name))
        return true
    }

    private fun walk(tree: Uri, parentId: String, out: MutableList<Map<String, Any>>) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val dirUri = DocumentsContract.buildDocumentUriUsingTree(tree, parentId).toString()
        val cols = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val subdirs = ArrayList<String>()
        activity.contentResolver.query(children, cols, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0)
                val name = c.getString(1) ?: continue
                val mime = c.getString(2) ?: ""
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (!name.startsWith(".")) subdirs.add(id)
                    continue
                }
                val ext = name.substringAfterLast('.', "").lowercase()
                val base = name.substringBeforeLast('.').lowercase()
                val wanted = ext in AUDIO_EXT || ext == "lrc" || (ext in ART_EXT && base in ART_NAMES)
                if (!wanted) continue
                out.add(
                    mapOf(
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                        "name" to name,
                        "dir" to dirUri,
                        "size" to c.getLong(3),
                        "modified" to c.getLong(4),
                    ),
                )
            }
        }
        for (id in subdirs) walk(tree, id, out)
    }
}
