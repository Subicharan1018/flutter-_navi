package com.navivibe.navivibe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/**
 * App notifications (downloads, updates, invitations). The media notification
 * belongs to audio_service on its own channel and is untouched by this.
 */
object AppNotifications {
    private val channels = listOf(
        Triple("navivibe_downloads", "Downloads", NotificationManager.IMPORTANCE_LOW),
        Triple("navivibe_updates", "App updates", NotificationManager.IMPORTANCE_DEFAULT),
        Triple("navivibe_social", "Invitations", NotificationManager.IMPORTANCE_DEFAULT),
    )

    /** Channels must exist before the first post, and before the user can configure them in system settings. */
    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val m = ctx.getSystemService(NotificationManager::class.java)
        channels.forEach { (id, name, importance) ->
            if (m.getNotificationChannel(id) == null) m.createNotificationChannel(NotificationChannel(id, name, importance))
        }
    }

    /** False when the user denied the permission, turned the app off, or blocked this channel. */
    fun canPost(ctx: Context, channelId: String): Boolean {
        val m = ctx.getSystemService(NotificationManager::class.java)
        if (!m.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 26) {
            val c = m.getNotificationChannel(channelId)
            if (c != null && c.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        return true
    }

    fun show(ctx: Context, channelId: String, id: Int, title: String, text: String): Boolean {
        ensureChannels(ctx)
        if (!canPost(ctx, channelId)) return false
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
            PendingIntent.getActivity(ctx, id, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channelId) else Notification.Builder(ctx)
        b.setSmallIcon(R.drawable.navi_play)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(open)
        ctx.getSystemService(NotificationManager::class.java).notify(id, b.build())
        return true
    }

    /** "Permission granted?" as the app sees it: system toggle, not channel state. */
    fun enabled(ctx: Context): Boolean =
        ctx.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    fun openSettings(ctx: Context) {
        val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }
}
