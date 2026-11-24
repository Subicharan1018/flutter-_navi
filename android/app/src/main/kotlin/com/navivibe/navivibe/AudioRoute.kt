package com.navivibe.navivibe

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper

/**
 * Where sound is going. Dart picks the preferred output from the raw list
 * (lib/services/notification_pills.dart) so the naming rules are unit-tested;
 * this only reports the connected outputs and tells Dart when they change.
 * The callback is event-driven: nothing runs while the route is steady.
 */
class AudioRoute(ctx: Context, private val onChanged: () -> Unit) {
    private val audio = ctx.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) = onChanged()
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) = onChanged()
    }

    fun start() = audio.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))

    fun stop() = audio.unregisterAudioDeviceCallback(callback)

    fun outputs(): List<Map<String, Any>> =
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map {
            mapOf("type" to it.type, "name" to (it.productName?.toString() ?: ""))
        }
}
