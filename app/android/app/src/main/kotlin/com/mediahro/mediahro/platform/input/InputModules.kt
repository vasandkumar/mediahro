package com.mediahro.mediahro.platform.input

import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
import android.view.MotionEvent
import android.view.accessibility.AccessibilityManager
import com.mediahro.mediahro.pigeon.AccessibilityPrefsHostApi
import com.mediahro.mediahro.pigeon.AudioDescriptionChangesStreamHandler
import com.mediahro.mediahro.pigeon.GamepadAxesStreamHandler
import com.mediahro.mediahro.pigeon.GamepadAxisEventMsg
import com.mediahro.mediahro.pigeon.GamepadAxisMsg
import com.mediahro.mediahro.pigeon.GamepadChangeMsg
import com.mediahro.mediahro.pigeon.GamepadConnectionsStreamHandler
import com.mediahro.mediahro.pigeon.GamepadHostApi
import com.mediahro.mediahro.pigeon.GamepadInfoMsg
import com.mediahro.mediahro.pigeon.PigeonEventSink

/**
 * AccessibilityPrefsFacade on Android (SYS-008, ADR-038): the audio
 * description preference, `AccessibilityManager.isAudioDescriptionRequested`
 * on Android 13+ (API 33); false below.
 */
class AccessibilityPrefsModule(context: Context) : AccessibilityPrefsHostApi {
    private val manager = context.getSystemService(AccessibilityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var sink: PigeonEventSink<Boolean>? = null
    private var listener: Any? = null

    override fun audioDescriptionRequested(): Boolean =
        Build.VERSION.SDK_INT >= 33 && manager.isAudioDescriptionRequested

    val changesHandler = object : AudioDescriptionChangesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<Boolean>) {
            this@AccessibilityPrefsModule.sink = sink
            if (Build.VERSION.SDK_INT >= 33) {
                val l = AccessibilityManager.AudioDescriptionRequestedChangeListener { requested ->
                    sink.success(requested)
                }
                listener = l
                manager.addAudioDescriptionRequestedChangeListener({ main.post(it) }, l)
            }
        }

        override fun onCancel(p0: Any?) {
            stop()
        }
    }

    private fun stop() {
        if (Build.VERSION.SDK_INT >= 33) {
            (listener as? AccessibilityManager.AudioDescriptionRequestedChangeListener)?.let {
                manager.removeAudioDescriptionRequestedChangeListener(it)
            }
        }
        listener = null
        sink = null
    }

    fun dispose() = stop()
}

/**
 * GamepadFacade on Android (SYS-009, ADR-038): sticks, triggers and the hat
 * from `MotionEvent`s with SOURCE_JOYSTICK / SOURCE_GAMEPAD, which Flutter's
 * view ignores (`MainActivity.dispatchGenericMotionEvent` forwards them
 * here), and controller connect/disconnect from `InputManager`. Buttons stay
 * Flutter key events. The dead zone is applied here.
 */
class GamepadModule(context: Context) : GamepadHostApi, InputManager.InputDeviceListener {
    private val inputs = context.getSystemService(InputManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val changes = GamepadMath.Changes()
    private val known = HashMap<Int, GamepadInfoMsg>()
    private val layouts = HashMap<Int, GamepadMath.Layout>()
    private var axesSink: PigeonEventSink<GamepadAxisEventMsg>? = null
    private var connectionsSink: PigeonEventSink<GamepadChangeMsg>? = null

    init {
        inputs.registerInputDeviceListener(this, main)
        connected().forEach { known[it.id.toInt()] = it }
    }

    override fun connected(): List<GamepadInfoMsg> =
        inputs.inputDeviceIds.toList().mapNotNull { id -> inputs.getInputDevice(id)?.takeIf(::isGamepad)?.let(::info) }

    private fun isGamepad(d: InputDevice): Boolean {
        val s = d.sources
        return !d.isVirtual &&
            (s and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
                s and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK)
    }

    private fun info(d: InputDevice) = GamepadInfoMsg(
        d.id.toLong(),
        d.name,
        d.vendorId.takeIf { it != 0 }?.toLong(),
        d.productId.takeIf { it != 0 }?.toLong(),
    )

    override fun onInputDeviceAdded(deviceId: Int) {
        val d = inputs.getInputDevice(deviceId)?.takeIf(::isGamepad) ?: return
        val added = info(d)
        known[deviceId] = added
        connectionsSink?.success(GamepadChangeMsg(true, added))
    }

    override fun onInputDeviceChanged(deviceId: Int) {}

    override fun onInputDeviceRemoved(deviceId: Int) {
        layouts.remove(deviceId)
        changes.forget(deviceId)
        // The device is gone; report what we knew of it.
        val gone = known.remove(deviceId) ?: return
        connectionsSink?.success(GamepadChangeMsg(false, gone))
    }

    /** Called with every generic motion event; true when it was a controller's analog input. */
    fun onMotion(ev: MotionEvent): Boolean {
        val s = ev.source
        val joystick = s and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK ||
            s and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD
        if (!joystick || ev.action != MotionEvent.ACTION_MOVE) return false
        val sink = axesSink ?: return true
        val device = ev.device // null for injected events: the default layout applies
        val layout = layouts.getOrPut(ev.deviceId) {
            GamepadMath.layout { axis -> device?.getMotionRange(axis, s) != null }
        }
        fun send(axis: GamepadAxisMsg, value: Float) {
            if (changes.changed(ev.deviceId, axis, value)) {
                sink.success(GamepadAxisEventMsg(ev.deviceId.toLong(), axis, value.toDouble()))
            }
        }
        send(GamepadAxisMsg.LEFT_X, GamepadMath.deadZone(ev.getAxisValue(layout.leftX)))
        send(GamepadAxisMsg.LEFT_Y, GamepadMath.deadZone(ev.getAxisValue(layout.leftY)))
        send(GamepadAxisMsg.RIGHT_X, GamepadMath.deadZone(ev.getAxisValue(layout.rightX)))
        send(GamepadAxisMsg.RIGHT_Y, GamepadMath.deadZone(ev.getAxisValue(layout.rightY)))
        send(GamepadAxisMsg.LEFT_TRIGGER, GamepadMath.trigger(ev.getAxisValue(layout.leftTrigger)))
        send(GamepadAxisMsg.RIGHT_TRIGGER, GamepadMath.trigger(ev.getAxisValue(layout.rightTrigger)))
        send(GamepadAxisMsg.HAT_X, GamepadMath.hat(ev.getAxisValue(layout.hatX)))
        send(GamepadAxisMsg.HAT_Y, GamepadMath.hat(ev.getAxisValue(layout.hatY)))
        return true
    }

    val axesHandler = object : GamepadAxesStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<GamepadAxisEventMsg>) {
            axesSink = sink
        }

        override fun onCancel(p0: Any?) {
            axesSink = null
        }
    }

    val connectionsHandler = object : GamepadConnectionsStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<GamepadChangeMsg>) {
            connectionsSink = sink
        }

        override fun onCancel(p0: Any?) {
            connectionsSink = null
        }
    }

    fun dispose() {
        inputs.unregisterInputDeviceListener(this)
        axesSink = null
        connectionsSink = null
    }
}
