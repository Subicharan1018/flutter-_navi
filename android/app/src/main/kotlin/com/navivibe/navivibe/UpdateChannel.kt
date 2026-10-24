package com.navivibe.navivibe

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridge for in-app updates (lib/features/updates).
 *
 * `installedApp` tells Dart where the installed base APK is, so it can apply a
 * binary patch to it, and which ABIs the phone runs. `install` hands the
 * finished APK to the system package installer through a FileProvider URI;
 * the installer checks that its signature matches the installed app.
 */
class UpdateChannel(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "com.navivibe/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "installedApp" -> {
                    val info = activity.applicationInfo
                    val code = activity.packageManager.getPackageInfo(activity.packageName, 0).let {
                        if (Build.VERSION.SDK_INT >= 28) it.longVersionCode else @Suppress("DEPRECATION") it.versionCode.toLong()
                    }
                    result.success(
                        mapOf(
                            "baseApk" to info.sourceDir,
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "versionCode" to code,
                        ),
                    )
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad_args", "path missing", null)
                    } else {
                        result.success(install(File(path)))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** False when the user first has to allow installs from this app. */
    private fun install(apk: File): Boolean {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
            )
            return false
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return true
    }
}
