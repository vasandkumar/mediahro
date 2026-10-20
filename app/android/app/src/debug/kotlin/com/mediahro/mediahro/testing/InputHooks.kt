package com.mediahro.mediahro.testing

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import com.mediahro.mediahro.platform.PlatformModules
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Debug-only hook for the gamepad test (lane C4a): `mediahro.test/gamepad`
 * takes `[deviceId, axisCode, value, axisCode, value, ...]` and feeds the
 * gamepad module a joystick `MotionEvent` with those axes, the way
 * `MainActivity.dispatchGenericMotionEvent` does for a real controller.
 * Replies whether the module took the event.
 */
internal object InputHooks {
    fun install(messenger: BinaryMessenger) {
        BasicMessageChannel(messenger, "mediahro.test/gamepad", StandardMessageCodec.INSTANCE)
            .setMessageHandler { message, reply ->
                val args = message as List<*>
                val deviceId = (args[0] as Number).toInt()
                val axes = args.drop(1).chunked(2).map { (it[0] as Number).toInt() to (it[1] as Number).toFloat() }
                val props = arrayOf(MotionEvent.PointerProperties().apply { id = 0 })
                val coords = arrayOf(
                    MotionEvent.PointerCoords().apply { axes.forEach { (axis, value) -> setAxisValue(axis, value) } },
                )
                val now = SystemClock.uptimeMillis()
                val ev = MotionEvent.obtain(
                    now, now, MotionEvent.ACTION_MOVE, 1, props, coords, 0, 0, 1f, 1f, deviceId, 0,
                    InputDevice.SOURCE_JOYSTICK, 0,
                )
                reply.reply(PlatformModules.gamepadModule?.onMotion(ev) == true)
                ev.recycle()
            }
    }
}
