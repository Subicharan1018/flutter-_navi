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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        saf = SafChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        UpdateChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.navivibe/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
