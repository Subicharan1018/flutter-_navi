package com.navivibe.navivibe

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the process (and so the Dart download queue) running while songs are
 * downloading with the app in the background or the screen off.
 *
 * It does no downloading itself: the queue lives in Dart. A foreground service
 * stops Android from freezing or killing the process as a cached app, and the
 * wake and Wi-Fi locks keep the CPU and radio awake with the screen off. It only
 * exists while the queue has work: Dart stops it the moment the queue is empty,
 * and it never restarts itself (NOT_STICKY): after a kill the app resumes the
 * saved queue the next time it opens.
 */
class DownloadService : Service() {
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // The "Stop" button on the notification: Dart cancels the queue.
            onStopRequested?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra("title") ?: "Downloading"
        val text = intent?.getStringExtra("text") ?: ""
        val done = intent?.getIntExtra("done", 0) ?: 0
        val total = intent?.getIntExtra("total", 0) ?: 0
        val live = intent?.getBooleanExtra("live", true) ?: true
        val note = build(this, title, text, done, total, live)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, note)
        }
        acquireLocks()
        return START_NOT_STICKY
    }

    /** Android 15 caps data-sync services (about 6 hours a day): stop cleanly. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wake == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            // A safety timeout: a lock must never outlive a stuck queue.
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "navivibe:downloads").apply {
                setReferenceCounted(false)
                acquire(WAKE_LIMIT_MS)
            }
        }
        if (wifi == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifi = wm?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "navivibe:downloads")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        try { wake?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
        try { wifi?.takeIf { it.isHeld }?.release() } catch (_: Exception) {}
        wake = null
        wifi = null
    }

    companion object {
        const val NOTIFICATION_ID = 9
        const val ACTION_STOP = "com.navivibe.navivibe.DOWNLOAD_STOP"
        private const val WAKE_LIMIT_MS = 6L * 60 * 60 * 1000

        /** Set by MainActivity: the Stop button was pressed. */
        @Volatile
        var onStopRequested: (() -> Unit)? = null

        private fun build(ctx: Context, title: String, text: String, done: Int, total: Int, live: Boolean): Notification {
            AppNotifications.ensureChannels(ctx)
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
                PendingIntent.getActivity(ctx, NOTIFICATION_ID, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            val stop = PendingIntent.getService(
                ctx,
                NOTIFICATION_ID,
                Intent(ctx, DownloadService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, "navivibe_downloads") else Notification.Builder(ctx)
            b.setSmallIcon(R.drawable.navi_play)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .addAction(Notification.Action.Builder(null as android.graphics.drawable.Icon?, "Stop", stop).build())
            if (live) {
                LiveUpdates.decorate(b, done.coerceAtMost(total), total, total <= 0, if (total > 0) "$done/$total" else null)
            } else {
                b.setProgress(total, done.coerceAtMost(total), total <= 0)
            }
            if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            return b.build()
        }

        /** Starts or updates the service. False when Android refuses (app in the background without the right to start it). */
        fun start(ctx: Context, title: String, text: String, done: Int, total: Int, live: Boolean = true): Boolean {
            return try {
                val i = Intent(ctx, DownloadService::class.java)
                    .putExtra("title", title).putExtra("text", text)
                    .putExtra("done", done).putExtra("total", total).putExtra("live", live)
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
                true
            } catch (e: Exception) {
                false
            }
        }

        fun stop(ctx: Context) {
            try { ctx.stopService(Intent(ctx, DownloadService::class.java)) } catch (_: Exception) {}
        }
    }
}
