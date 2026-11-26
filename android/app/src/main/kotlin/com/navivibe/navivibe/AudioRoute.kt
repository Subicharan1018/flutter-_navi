package com.navivibe.navivibe

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRouter
import android.media.MediaRouter2
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings

/**
 * Where sound is going. Dart names the route from the raw list
 * (lib/services/output_route.dart) so the naming rules are unit-tested; this
 * only reports outputs, says when they change and opens the system's own
 * output switcher. The callbacks are event-driven: nothing polls.
 */
class AudioRoute(ctx: Context, private val onChanged: () -> Unit) {
    private val app = ctx.applicationContext
    private val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val router = app.getSystemService(Context.MEDIA_ROUTER_SERVICE) as MediaRouter

    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) = onChanged()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) = onChanged()
    }

    // The listener picking another output moves sound without adding a device.
    private val routes = object : MediaRouter.SimpleCallback() {
        override fun onRouteSelected(r: MediaRouter, type: Int, info: MediaRouter.RouteInfo) = onChanged()
        override fun onRouteChanged(r: MediaRouter, info: MediaRouter.RouteInfo) = onChanged()
    }

    fun start() {
        audio.registerAudioDeviceCallback(devices, Handler(Looper.getMainLooper()))
        router.addCallback(MediaRouter.ROUTE_TYPE_LIVE_AUDIO, routes)
    }

    fun stop() {
        audio.unregisterAudioDeviceCallback(devices)
        router.removeCallback(routes)
    }

    /** Android 13+: the outputs media plays on now. Older: everything connected. */
    fun outputs(): List<Map<String, Any>> {
        val list: List<AudioDeviceInfo> = if (Build.VERSION.SDK_INT >= 33) {
            val media = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build()
            audio.getAudioDevicesForAttributes(media)
                .mapNotNull { routed ->
                    // The routed entry has no product name; find it among the connected ones.
                    audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        .firstOrNull { it.type == routed.type && (routed.address.isEmpty() || it.address == routed.address) }
                }
        } else {
            audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        }
        return list.map { mapOf("type" to it.type, "name" to (it.productName?.toString() ?: "")) }
    }

    companion object {
        /**
         * The system's output picker: Android 14's switcher, the media output
         * panel on 11–13, else Bluetooth settings. False when none opened.
         */
        fun openSwitcher(activity: Activity): Boolean {
            if (Build.VERSION.SDK_INT >= 34) {
                try {
                    if (MediaRouter2.getInstance(activity).showSystemOutputSwitcher()) return true
                } catch (_: Exception) {
                    // Some builds refuse; try the older ways.
                }
            }
            val panel = Intent("com.android.settings.panel.action.MEDIA_OUTPUT")
                .putExtra("com.android.settings.panel.extra.PACKAGE_NAME", activity.packageName)
            for (intent in listOf(panel, Intent(Settings.ACTION_BLUETOOTH_SETTINGS))) {
                try {
                    activity.startActivity(intent)
                    return true
                } catch (_: Exception) {
                    // Not offered on this device.
                }
            }
            return false
        }
    }
}
