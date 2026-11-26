package com.navivibe.navivibe

import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The equalizer on the player's audio session. An effect exists only while the
 * app asks for one: "release" removes it, so with the equalizer off nothing at
 * all sits in the audio path.
 *
 * An object, because the activity (and with it this channel) is re-created
 * while the audio session, and any effect on it, lives on.
 */
object EqChannel {
    private const val TAG = "NaviEqualizer"

    private var dynamics: DynamicsProcessing? = null
    private var legacy: Equalizer? = null
    private var session = 0
    private var bandCount = 0

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.navivibe/equalizer").setMethodCallHandler { call, result ->
            when (call.method) {
                "apply" -> try {
                    val id = call.argument<Int>("sessionId") ?: 0
                    val cutoffs = call.argument<List<Double>>("cutoffs")!!
                    val gains = call.argument<List<Double>>("gains")!!
                    val inputGain = call.argument<Double>("inputGain") ?: 0.0
                    require(id != 0 && cutoffs.size == gains.size && cutoffs.isNotEmpty())
                    result.success(apply(id, cutoffs, gains, inputGain))
                } catch (e: Exception) {
                    release()
                    result.error("equalizer", e.message, null)
                }
                "release" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun apply(id: Int, cutoffs: List<Double>, gains: List<Double>, inputGain: Double): String {
        if (id != session || cutoffs.size != bandCount) release()
        session = id
        bandCount = cutoffs.size
        return if (Build.VERSION.SDK_INT >= 28) {
            applyDynamics(id, cutoffs, gains, inputGain)
        } else {
            applyLegacy(id, cutoffs, gains, inputGain)
        }
    }

    @androidx.annotation.RequiresApi(28)
    private fun applyDynamics(id: Int, cutoffs: List<Double>, gains: List<Double>, inputGain: Double): String {
        val effect = dynamics ?: run {
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                2, // stereo
                true, cutoffs.size, // pre-EQ
                false, 0, // no multiband compressor
                false, 0, // no post-EQ
                false, // no limiter: headroom comes from the input gain
            )
                // About 40 ms blocks: fine enough in frequency to tell 60 Hz
                // from 150 Hz.
                .setPreferredFrameDuration(40f)
                .build()
            DynamicsProcessing(0, id, config).also { dynamics = it }
        }
        for (i in cutoffs.indices) {
            effect.setPreEqBandAllChannelsTo(
                i,
                DynamicsProcessing.EqBand(true, cutoffs[i].toFloat(), gains[i].toFloat()),
            )
        }
        effect.setInputGainAllChannelsTo(inputGain.toFloat())
        effect.enabled = true
        return "DynamicsProcessing, ${cutoffs.size} bands, headroom ${"%.1f".format(inputGain)} dB, " +
            "control=${effect.hasControl()}"
    }

    /** Android 8 and older: the phone's own bands, sampled from the same curve. */
    private fun applyLegacy(id: Int, cutoffs: List<Double>, gains: List<Double>, inputGain: Double): String {
        val effect = legacy ?: Equalizer(0, id).also { legacy = it }
        val range = effect.bandLevelRange
        for (band in 0 until effect.numberOfBands) {
            val centre = effect.getCenterFreq(band.toShort()) / 1000.0 // milliHertz
            var slice = cutoffs.indexOfFirst { centre <= it }
            if (slice < 0) slice = cutoffs.size - 1
            // No input gain here, so the headroom comes off every band.
            val millibels = ((gains[slice] + inputGain) * 100).toInt()
                .coerceIn(range[0].toInt(), range[1].toInt())
            effect.setBandLevel(band.toShort(), millibels.toShort())
        }
        effect.enabled = true
        return "Equalizer, ${effect.numberOfBands} device bands"
    }

    private fun release() {
        try {
            dynamics?.release()
            legacy?.release()
        } catch (e: Exception) {
            Log.w(TAG, "release failed", e)
        }
        dynamics = null
        legacy = null
        session = 0
        bandCount = 0
    }
}
