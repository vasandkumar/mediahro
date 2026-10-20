package com.mediahro.mediahro.platform.media

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.mediahro.mediahro.pigeon.AudioDeviceChangesStreamHandler
import com.mediahro.mediahro.pigeon.AudioDeviceKindMsg
import com.mediahro.mediahro.pigeon.AudioDeviceListMsg
import com.mediahro.mediahro.pigeon.AudioDeviceMsg
import com.mediahro.mediahro.pigeon.AudioInterruptionKindMsg
import com.mediahro.mediahro.pigeon.AudioInterruptionMsg
import com.mediahro.mediahro.pigeon.AudioInterruptionsStreamHandler
import com.mediahro.mediahro.pigeon.AudioOutputHostApi
import com.mediahro.mediahro.pigeon.AudioPathGrantMsg
import com.mediahro.mediahro.pigeon.FlutterError
import com.mediahro.mediahro.pigeon.PigeonEventSink

/**
 * AudioOutputFacade on Android (AUD-040, AUD-043, AUD-044, AUD-045):
 * output devices with their rates, passthrough encodings and LE Audio
 * codec; the Android 14 bit-perfect mixer (`setPreferredMixerAttributes`)
 * for USB DACs; audio focus with app-side ducking; headphone unplug.
 */
class AudioOutputModule(private val context: Context) : AudioOutputHostApi {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    private val mediaAttributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    // ---- Devices (AUD-044 codec shown, VID-004 passthrough formats).

    override fun devices(): List<AudioDeviceMsg> =
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { it.isSink && it.type != AudioDeviceInfo.TYPE_TELEPHONY && it.type != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }
            .map(::describe)

    private fun describe(d: AudioDeviceInfo): AudioDeviceMsg {
        val kind = kindOf(d.type)
        return AudioDeviceMsg(
            id = d.id.toString(),
            name = d.productName?.toString()?.takeIf { it.isNotBlank() } ?: kind.name,
            kind = kind,
            sampleRates = d.sampleRates.map(Int::toLong).sorted(),
            supportsExclusive = bitPerfectFormats(d).isNotEmpty(),
            encodedFormats = d.encodings.toList().mapNotNull(::passthroughName).distinct(),
            bluetoothCodec = codecOf(d.type),
        )
    }

    private fun kindOf(type: Int): AudioDeviceKindMsg = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE ->
            AudioDeviceKindMsg.BUILT_IN
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_AUX_LINE, AudioDeviceInfo.TYPE_DOCK, AudioDeviceInfo.TYPE_DOCK_ANALOG ->
            AudioDeviceKindMsg.WIRED
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY ->
            AudioDeviceKindMsg.USB
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET,
        AudioDeviceInfo.TYPE_BLE_SPEAKER, AudioDeviceInfo.TYPE_BLE_BROADCAST, AudioDeviceInfo.TYPE_HEARING_AID ->
            AudioDeviceKindMsg.BLUETOOTH
        AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC, AudioDeviceInfo.TYPE_HDMI_EARC ->
            AudioDeviceKindMsg.HDMI
        AudioDeviceInfo.TYPE_LINE_DIGITAL -> AudioDeviceKindMsg.SPDIF
        AudioDeviceInfo.TYPE_REMOTE_SUBMIX -> AudioDeviceKindMsg.CAST
        else -> AudioDeviceKindMsg.OTHER
    }

    private fun passthroughName(encoding: Int): String? = when (encoding) {
        AudioFormat.ENCODING_AC3 -> "ac3"
        AudioFormat.ENCODING_E_AC3, AudioFormat.ENCODING_E_AC3_JOC -> "eac3"
        AudioFormat.ENCODING_DTS -> "dts"
        AudioFormat.ENCODING_DTS_HD, AudioFormat.ENCODING_DTS_UHD_P1, AudioFormat.ENCODING_DTS_UHD_P2 -> "dtshd"
        AudioFormat.ENCODING_DOLBY_TRUEHD -> "truehd"
        else -> null
    }

    /**
     * The codec shown in the output picker (AUD-044). LE Audio always runs
     * LC3. Android has no public API for the active A2DP codec
     * (`BluetoothA2dp.getCodecStatus` is hidden), so A2DP reports none.
     */
    private fun codecOf(type: Int): String? = when (type) {
        AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER, AudioDeviceInfo.TYPE_BLE_BROADCAST -> "LC3"
        else -> null
    }

    private var deviceSink: PigeonEventSink<AudioDeviceListMsg>? = null
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = publishDevices()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = publishDevices()
    }

    private fun publishDevices() {
        deviceSink?.success(AudioDeviceListMsg(devices()))
    }

    val devicesHandler = object : AudioDeviceChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<AudioDeviceListMsg>) {
            deviceSink = sink
            audio.registerAudioDeviceCallback(deviceCallback, main)
        }

        override fun onCancel(p0: Any?) {
            audio.unregisterAudioDeviceCallback(deviceCallback)
            deviceSink = null
        }
    }

    // ---- Bit-perfect USB path (AUD-040, ADR-023 DoP rides on it).

    private fun bitPerfectFormats(d: AudioDeviceInfo): List<AudioMixerAttributes> {
        if (Build.VERSION.SDK_INT < 34) return emptyList()
        return try {
            audio.getSupportedMixerAttributes(d).filter {
                it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT
            }
        } catch (e: IllegalArgumentException) {
            emptyList()
        }
    }

    private var bitPerfectDevice: AudioDeviceInfo? = null

    override fun requestBitPerfect(deviceId: String, sampleRate: Long, bitDepth: Long?): AudioPathGrantMsg {
        val device = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.id.toString() == deviceId }
            ?: throw FlutterError("notFound", "No output device $deviceId")
        val candidates = bitPerfectFormats(device)
        if (Build.VERSION.SDK_INT < 34 || candidates.isEmpty()) return AudioPathGrantMsg(false, null, null)
        val wanted = bitDepth?.let(::encodingFor)
        val pick = candidates
            .filter { it.format.sampleRate == sampleRate.toInt() }
            .sortedByDescending { depthOf(it.format.encoding) }
            .firstOrNull { wanted == null || it.format.encoding == wanted }
            ?: candidates.filter { it.format.sampleRate == sampleRate.toInt() }
                .maxByOrNull { depthOf(it.format.encoding) }
            ?: return AudioPathGrantMsg(false, null, null)
        if (!audio.setPreferredMixerAttributes(mediaAttributes, device, pick)) {
            return AudioPathGrantMsg(false, null, null)
        }
        bitPerfectDevice = device
        return AudioPathGrantMsg(true, pick.format.sampleRate.toLong(), depthOf(pick.format.encoding).toLong())
    }

    override fun releaseBitPerfect() {
        val device = bitPerfectDevice ?: return
        if (Build.VERSION.SDK_INT >= 34) audio.clearPreferredMixerAttributes(mediaAttributes, device)
        bitPerfectDevice = null
    }

    private fun encodingFor(bits: Long): Int? = when (bits) {
        16L -> AudioFormat.ENCODING_PCM_16BIT
        24L -> AudioFormat.ENCODING_PCM_24BIT_PACKED
        32L -> AudioFormat.ENCODING_PCM_32BIT
        else -> null
    }

    private fun depthOf(encoding: Int): Int = when (encoding) {
        AudioFormat.ENCODING_PCM_8BIT -> 8
        AudioFormat.ENCODING_PCM_16BIT -> 16
        AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
        AudioFormat.ENCODING_PCM_32BIT, AudioFormat.ENCODING_PCM_FLOAT -> 32
        else -> 0
    }

    // ---- Focus and interruptions (AUD-045).

    private var interruptionSink: PigeonEventSink<AudioInterruptionMsg>? = null
    private var focusRequest: AudioFocusRequest? = null
    private var ducked = false
    private var transientLoss = false

    val interruptionsHandler = object : AudioInterruptionsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<AudioInterruptionMsg>) {
            interruptionSink = sink
        }

        override fun onCancel(p0: Any?) {
            interruptionSink = null
        }
    }

    private fun emit(kind: AudioInterruptionKindMsg) {
        interruptionSink?.success(AudioInterruptionMsg(kind))
    }

    /** Package-visible for the debug hooks' focus tests. */
    internal val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Another app took over for good (it started playing music):
                // pause and do not resume on our own.
                emit(AudioInterruptionKindMsg.BEGAN)
                emit(AudioInterruptionKindMsg.ENDED_NO_RESUME)
                transientLoss = false
                ducked = false
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                transientLoss = true
                emit(AudioInterruptionKindMsg.BEGAN)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                ducked = true
                emit(AudioInterruptionKindMsg.DUCK)
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (ducked) emit(AudioInterruptionKindMsg.UNDUCK)
                if (transientLoss) emit(AudioInterruptionKindMsg.ENDED_SHOULD_RESUME)
                ducked = false
                transientLoss = false
            }
        }
    }

    internal val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                emit(AudioInterruptionKindMsg.BECOMING_NOISY)
            }
        }
    }
    private var noisyRegistered = false

    override fun requestFocus(duckOthers: Boolean): Boolean {
        focusRequest?.let(audio::abandonAudioFocusRequest)
        // duckOthers: a short sound over other apps; otherwise full media focus.
        val request = AudioFocusRequest.Builder(
            if (duckOthers) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK else AudioManager.AUDIOFOCUS_GAIN,
        )
            .setAudioAttributes(mediaAttributes)
            // Ducking is done by the app (AUD-045 resume rules are user
            // settings), so the system reports it instead of ducking for us.
            .setWillPauseWhenDucked(true)
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener(focusListener, main)
            .build()
        val granted = audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (granted) {
            focusRequest = request
            ducked = false
            transientLoss = false
            if (!noisyRegistered) {
                ContextCompat.registerReceiver(
                    context,
                    noisyReceiver,
                    IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                    // System broadcasts still arrive at a non-exported receiver.
                    ContextCompat.RECEIVER_NOT_EXPORTED,
                )
                noisyRegistered = true
            }
        }
        return granted
    }

    override fun abandonFocus() {
        focusRequest?.let(audio::abandonAudioFocusRequest)
        focusRequest = null
        if (noisyRegistered) {
            context.unregisterReceiver(noisyReceiver)
            noisyRegistered = false
        }
    }

    fun dispose() {
        abandonFocus()
        releaseBitPerfect()
        audio.unregisterAudioDeviceCallback(deviceCallback)
    }
}
