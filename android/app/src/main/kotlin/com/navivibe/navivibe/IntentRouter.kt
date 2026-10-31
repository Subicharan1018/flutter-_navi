package com.navivibe.navivibe

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns

/**
 * Turns the intents NaviVibe handles as a music player into plain maps for Dart:
 *  - MEDIA_PLAY_FROM_SEARCH ("play X on NaviVibe") -> {kind: search, query, focus, artist, album, title}
 *  - VIEW / SEND of audio ("Open with")             -> {kind: view, uri, name}
 */
object IntentRouter {
    fun parse(ctx: Context, intent: Intent?): Map<String, Any?>? {
        intent ?: return null
        when (intent.action) {
            "android.media.action.MEDIA_PLAY_FROM_SEARCH" -> return mapOf(
                "kind" to "search",
                "query" to (intent.getStringExtra(SearchManager.QUERY) ?: ""),
                "focus" to intent.getStringExtra(MediaStore.EXTRA_MEDIA_FOCUS),
                "artist" to intent.getStringExtra(MediaStore.EXTRA_MEDIA_ARTIST),
                "album" to intent.getStringExtra(MediaStore.EXTRA_MEDIA_ALBUM),
                "title" to intent.getStringExtra(MediaStore.EXTRA_MEDIA_TITLE),
            )
            Intent.ACTION_VIEW -> return view(ctx, intent.data)
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                return if (intent.type?.startsWith("audio/") == true) view(ctx, uri) else null
            }
        }
        return null
    }

    private fun view(ctx: Context, uri: Uri?): Map<String, Any?>? {
        uri ?: return null
        if (uri.scheme != "content" && uri.scheme != "file") return null
        return mapOf("kind" to "view", "uri" to uri.toString(), "name" to displayName(ctx, uri))
    }

    private fun displayName(ctx: Context, uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) {
            uri.lastPathSegment
        }
    }
}
