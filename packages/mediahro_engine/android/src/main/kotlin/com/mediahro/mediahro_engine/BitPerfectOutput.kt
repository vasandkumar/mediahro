package com.mediahro.mediahro_engine

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build

/**
 * Bit-perfect USB output on Android 14+ (AUD-040): asks the platform mixer
 * to pass the stream through untouched at the source rate on the routed USB
 * device (`MIXER_BEHAVIOR_BIT_PERFECT`). Reports what was applied so the
 * engine's output indicator stays truthful (AUD-006).
 */
internal class BitPerfectOutput(
    context: Context,
) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val media =
        AudioAttributes
            .Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
    private var applied: AudioDeviceInfo? = null

    fun prefer(
        bitPerfect: Boolean,
        sampleRate: Int?,
        channels: Int?,
        bitDepth: Int?,
    ): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return mapOf("applied" to false, "reason" to "api<34")
        }
        if (!bitPerfect) {
            release()
            return mapOf("applied" to true, "bitPerfect" to false)
        }
        val device =
            audio
                .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        it.type == AudioDeviceInfo.TYPE_USB_HEADSET
                } ?: return mapOf("applied" to false, "reason" to "no USB output")
        val supported = audio.getSupportedMixerAttributes(device)
        val wantedEncoding =
            when (bitDepth) {
                null, 16 -> AudioFormat.ENCODING_PCM_16BIT
                24 -> AudioFormat.ENCODING_PCM_24BIT_PACKED
                32 -> AudioFormat.ENCODING_PCM_32BIT
                else -> AudioFormat.ENCODING_PCM_FLOAT
            }
        val wantedChannels = channels ?: 2
        val match =
            supported
                .filter { it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT }
                .sortedWith(
                    compareBy(
                        { if (sampleRate == null || it.format.sampleRate == sampleRate) 0 else 1 },
                        { if (it.format.encoding == wantedEncoding) 0 else 1 },
                        { if (it.format.channelCount == wantedChannels) 0 else 1 },
                    ),
                ).firstOrNull()
                ?: return mapOf("applied" to false, "reason" to "device has no bit-perfect mode")
        val ok = audio.setPreferredMixerAttributes(media, device, match)
        if (ok) applied = device
        return mapOf(
            "applied" to ok,
            "bitPerfect" to (ok && match.format.sampleRate == (sampleRate ?: match.format.sampleRate)),
            "sampleRate" to match.format.sampleRate,
            "device" to device.productName?.toString(),
        )
    }

    fun release() {
        val device = applied ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            audio.clearPreferredMixerAttributes(media, device)
        }
        applied = null
    }
}
