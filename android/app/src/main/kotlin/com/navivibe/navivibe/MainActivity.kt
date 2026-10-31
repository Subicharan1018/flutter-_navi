package com.navivibe.navivibe

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var saf: SafChannel? = null
    private var appChannel: MethodChannel? = null

    // The intent that opened the app, kept until Dart asks for it once.
    private var pendingIntent: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // A re-created activity (rotation) must not replay the same file.
        if (savedInstanceState == null) pendingIntent = IntentRouter.parse(this, intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val parsed = IntentRouter.parse(this, intent) ?: return
        val channel = appChannel
        if (channel != null) channel.invokeMethod("onIntent", parsed) else pendingIntent = parsed
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        saf = SafChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        UpdateChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        AppNotifications.ensureChannels(this)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.navivibe/android")
        appChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialIntent" -> {
                        result.success(pendingIntent)
                        pendingIntent = null
                    }
                    "notify" -> result.success(
                        AppNotifications.show(
                            this,
                            call.argument<String>("channel") ?: "navivibe_updates",
                            call.argument<Int>("id") ?: 1,
                            call.argument<String>("title") ?: "NaviVibe",
                            call.argument<String>("body") ?: "",
                        ),
                    )
                    "notificationsEnabled" -> result.success(AppNotifications.enabled(this))
                    "openNotificationSettings" -> {
                        AppNotifications.openSettings(this)
                        result.success(null)
                    }
                    "updateWidget" -> {
                        NaviWidget.save(
                            this,
                            call.argument<String>("title") ?: "NaviVibe",
                            call.argument<String>("artist") ?: "",
                            call.argument<Boolean>("playing") ?: false,
                            call.argument<Boolean>("active") ?: false,
                            call.argument<String>("art") ?: "",
                        )
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                        }
                        result.success(null)
                    }
                    "isTelevision" -> {
                        val ui = getSystemService(android.content.Context.UI_MODE_SERVICE) as android.app.UiModeManager
                        result.success(
                            ui.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
                                packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (saf?.onActivityResult(requestCode, resultCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
