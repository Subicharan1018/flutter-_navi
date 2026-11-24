package com.navivibe.navivibe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Ongoing progress notifications for fetches, the sleep timer and a Jam.
 * On Android 16+ they ask to be promoted to a Live Update (a status-bar chip
 * with the progress); older versions show the same notification as a normal
 * ongoing one. Dart decides when to post (throttled) and always ends them.
 * Nothing here ticks: the countdown is drawn by the system chronometer.
 */
object LiveUpdates {
    const val CHANNEL = "navivibe_live"

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val m = ctx.getSystemService(NotificationManager::class.java)
        if (m.getNotificationChannel(CHANNEL) == null) {
            m.createNotificationChannel(NotificationChannel(CHANNEL, "Live updates", NotificationManager.IMPORTANCE_LOW))
        }
    }

    fun openApp(ctx: Context, requestCode: Int, playIds: String? = null): PendingIntent? {
        val i = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return null
        if (playIds != null) i.putExtra(IntentRouter.EXTRA_PLAY_IDS, playIds)
        return PendingIntent.getActivity(ctx, requestCode, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Applies the progress bar and, on Android 16, the promoted-ongoing request and chip text. */
    fun decorate(b: Notification.Builder, value: Int, max: Int, indeterminate: Boolean, chip: String?) {
        if (Build.VERSION.SDK_INT >= 36) {
            b.setStyle(
                Notification.ProgressStyle()
                    .setProgressIndeterminate(indeterminate)
                    .setProgressSegments(listOf(Notification.ProgressStyle.Segment(if (max > 0) max else 100)))
                    .setProgress(value),
            )
            b.setRequestPromotedOngoing(true)
            if (!chip.isNullOrEmpty()) b.setShortCriticalText(chip)
        } else {
            b.setProgress(max, value.coerceAtMost(max), indeterminate)
        }
    }

    /**
     * Posts or updates one notification. [whenMs] > 0 turns on a counting
     * chronometer (down when [countDown]); [timeoutMs] is a safety net so a
     * killed app cannot leave it behind.
     */
    fun post(
        ctx: Context,
        id: Int,
        title: String,
        text: String,
        value: Int,
        max: Int,
        indeterminate: Boolean,
        chip: String?,
        whenMs: Long,
        countDown: Boolean,
        timeoutMs: Long,
    ): Boolean {
        ensureChannel(ctx)
        if (!AppNotifications.canPost(ctx, CHANNEL)) return false
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, CHANNEL) else Notification.Builder(ctx)
        b.setSmallIcon(R.drawable.navi_play)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp(ctx, id))
        if (max > 0 || indeterminate) {
            decorate(b, value, max, indeterminate, chip)
        } else if (Build.VERSION.SDK_INT >= 36) {
            b.setRequestPromotedOngoing(true)
            if (!chip.isNullOrEmpty()) b.setShortCriticalText(chip)
        }
        if (whenMs > 0) {
            b.setWhen(whenMs).setShowWhen(true).setUsesChronometer(true)
            if (Build.VERSION.SDK_INT >= 24) b.setChronometerCountDown(countDown)
        }
        if (timeoutMs > 0 && Build.VERSION.SDK_INT >= 26) b.setTimeoutAfter(timeoutMs)
        ctx.getSystemService(NotificationManager::class.java).notify(id, b.build())
        return true
    }

    fun end(ctx: Context, id: Int) {
        ctx.getSystemService(NotificationManager::class.java).cancel(id)
    }

    /** A finished-work notice whose tap plays [playIds] (comma separated song ids). */
    fun postPlayable(ctx: Context, id: Int, title: String, text: String, playIds: String): Boolean {
        ensureChannel(ctx)
        AppNotifications.ensureChannels(ctx)
        val channel = "navivibe_downloads"
        if (!AppNotifications.canPost(ctx, channel)) return false
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channel) else Notification.Builder(ctx)
        b.setSmallIcon(R.drawable.navi_play)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(openApp(ctx, id, playIds))
        ctx.getSystemService(NotificationManager::class.java).notify(id, b.build())
        return true
    }
}
