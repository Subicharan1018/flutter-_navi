package com.navivibe.navivibe

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File
import java.util.concurrent.Executors

/**
 * Now-playing widgets in three sizes. Dart pushes state (only when the song,
 * artwork or play state changes); it is kept in prefs so a widget keeps showing
 * the last state while the app process is gone. Nothing here polls or runs on a timer.
 */
abstract class NaviWidget : AppWidgetProvider() {
    abstract val layout: Int
    abstract val artPx: Int
    abstract fun bind(ctx: Context, v: RemoteViews, s: State, art: Bitmap?)

    class State(
        val title: String, val artist: String, val playing: Boolean,
        val active: Boolean, val art: String,
    )

    override fun onUpdate(ctx: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = build(ctx, this)
        ids.forEach { manager.updateAppWidget(it, views) }
    }

    companion object {
        private const val PREFS = "navivibe_widget"
        private val io = Executors.newSingleThreadExecutor()
        private val all = listOf(
            NowPlayingWidget::class.java, SmallWidget::class.java, CompactWidget::class.java,
        )

        private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun state(ctx: Context): State {
            val p = prefs(ctx)
            return State(
                p.getString("title", "NaviVibe") ?: "NaviVibe",
                p.getString("artist", "Nothing playing") ?: "",
                p.getBoolean("playing", false), p.getBoolean("active", false),
                p.getString("art", "") ?: "",
            )
        }

        /** Called from the app when playback state changes. Cheap when no widget is placed. */
        fun save(ctx: Context, title: String, artist: String, playing: Boolean, active: Boolean, art: String) {
            prefs(ctx).edit().putString("title", title).putString("artist", artist)
                .putBoolean("playing", playing).putBoolean("active", active)
                .putString("art", art).apply()
            val app = ctx.applicationContext
            if (providersWithIds(app).isEmpty()) return
            refreshAll(app)
            // Artwork may need a download; do it off the main thread, then redraw.
            if (art.startsWith("http") && artFile(app, art) == null) {
                io.execute {
                    if (ArtCache.fetch(app, art) != null && prefs(app).getString("art", "") == art) {
                        refreshAll(app)
                    }
                }
            }
        }

        private fun providersWithIds(ctx: Context): List<Pair<Class<out NaviWidget>, IntArray>> {
            val m = AppWidgetManager.getInstance(ctx)
            return all.map { it to m.getAppWidgetIds(ComponentName(ctx, it)) }.filter { it.second.isNotEmpty() }
        }

        private fun refreshAll(ctx: Context) {
            val m = AppWidgetManager.getInstance(ctx)
            providersWithIds(ctx).forEach { (cls, ids) ->
                val views = build(ctx, cls.getDeclaredConstructor().newInstance())
                ids.forEach { m.updateAppWidget(it, views) }
            }
        }

        /** Cached/local file for the artwork, never touching the network. */
        private fun artFile(ctx: Context, art: String): File? = when {
            art.startsWith("file:") -> Uri.parse(art).path?.let { File(it) }?.takeIf { it.exists() }
            art.startsWith("http") -> {
                // Same key scheme as ArtCache.fetch; a miss means "not downloaded yet".
                ArtCache.cached(ctx, art)
            }
            else -> null
        }

        private fun build(ctx: Context, w: NaviWidget): RemoteViews {
            val s = state(ctx)
            val v = RemoteViews(ctx.packageName, w.layout)
            v.setTextViewText(R.id.widget_title, s.title)
            v.setTextViewText(R.id.widget_artist, s.artist)
            val art = artFile(ctx, s.art)?.let { ArtCache.rounded(it, w.artPx) }
            if (art != null) v.setImageViewBitmap(R.id.widget_art, art)
            else v.setImageViewResource(R.id.widget_art, R.drawable.widget_art_placeholder)
            v.setImageViewResource(
                R.id.widget_play, if (s.playing) R.drawable.navi_pause else R.drawable.navi_play,
            )
            w.bind(ctx, v, s, art)
            return v
        }

        fun openApp(ctx: Context): PendingIntent? =
            ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
                PendingIntent.getActivity(ctx, 0, it, PendingIntent.FLAG_IMMUTABLE)
            }

        /**
         * A media key via audio_service's own receiver (starts or controls the player
         * service). With nothing loaded the button opens the app instead: a cold service
         * would have nothing to play, and a tap on the widget is what lets Android 12+
         * start the app from the background.
         */
        fun control(ctx: Context, s: State, keyCode: Int): PendingIntent? {
            if (!s.active) return openApp(ctx)
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(ctx, "com.ryanheise.audioservice.MediaButtonReceiver")
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            return PendingIntent.getBroadcast(ctx, keyCode, intent, PendingIntent.FLAG_IMMUTABLE)
        }
    }
}

private fun RemoteViews.tap(id: Int, pi: PendingIntent?) {
    if (pi != null) setOnClickPendingIntent(id, pi)
}

/** 4x2: art, title, artist, previous / play / next. */
class NowPlayingWidget : NaviWidget() {
    override val layout = R.layout.widget_now_playing
    override val artPx = 240
    override fun bind(ctx: Context, v: RemoteViews, s: State, art: Bitmap?) {
        v.tap(R.id.widget_root, openApp(ctx))
        v.tap(R.id.widget_prev, control(ctx, s, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        v.tap(R.id.widget_play, control(ctx, s, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        v.tap(R.id.widget_next, control(ctx, s, KeyEvent.KEYCODE_MEDIA_NEXT))
    }
}

/** 2x2: artwork with a play button. */
class SmallWidget : NaviWidget() {
    override val layout = R.layout.widget_small
    override val artPx = 360
    override fun bind(ctx: Context, v: RemoteViews, s: State, art: Bitmap?) {
        v.tap(R.id.widget_root, openApp(ctx))
        v.tap(R.id.widget_play, control(ctx, s, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
    }
}

/** 4x1: slim bar with art, title / artist, play and next. */
class CompactWidget : NaviWidget() {
    override val layout = R.layout.widget_compact
    override val artPx = 140
    override fun bind(ctx: Context, v: RemoteViews, s: State, art: Bitmap?) {
        v.tap(R.id.widget_root, openApp(ctx))
        v.tap(R.id.widget_play, control(ctx, s, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        v.tap(R.id.widget_next, control(ctx, s, KeyEvent.KEYCODE_MEDIA_NEXT))
    }
}
