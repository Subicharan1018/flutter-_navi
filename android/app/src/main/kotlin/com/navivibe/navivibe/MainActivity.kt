package com.navivibe.navivibe

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    else -> result.notImplemented()
                }
            }
    }
}
