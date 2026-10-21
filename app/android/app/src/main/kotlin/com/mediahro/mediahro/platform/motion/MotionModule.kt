package com.mediahro.mediahro.platform.motion

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.Surface
import com.mediahro.mediahro.pigeon.AttitudeStreamHandler
import com.mediahro.mediahro.pigeon.MotionAttitudeMsg
import com.mediahro.mediahro.pigeon.MotionHostApi
import com.mediahro.mediahro.pigeon.PigeonEventSink
import com.mediahro.mediahro.platform.ActivityHost

/**
 * MotionFacade on Android (IMG-001, ADR-042): `TYPE_GAME_ROTATION_VECTOR` (no
 * magnetometer, so no absolute heading and nothing that reveals where the
 * device is; no permission). The sensor is registered only while the stream
 * has a listener, at `SENSOR_DELAY_GAME`, and unregistered on cancel and when
 * the engine goes away.
 */
class MotionModule(private val context: Context, private val host: ActivityHost) : MotionHostApi {
    private val sensors = context.getSystemService(SensorManager::class.java)
    private val sensor: Sensor? = sensors.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
    private var listener: SensorEventListener? = null

    override fun available(): Boolean = sensor != null

    val attitudeHandler = object : AttitudeStreamHandler() {
        override fun onListen(p0: Any?, sink: PigeonEventSink<MotionAttitudeMsg>) {
            start(sink)
        }

        override fun onCancel(p0: Any?) {
            stop()
        }
    }

    private fun start(sink: PigeonEventSink<MotionAttitudeMsg>) {
        stop()
        val sensor = sensor ?: return
        val tracker = MotionMath.Tracker()
        var last: Pair<Double, Double>? = null
        val vector = FloatArray(9)
        val remapped = FloatArray(9)
        val l = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(vector, event.values)
                val (x, y) = axesFor(displayRotation())
                val matrix = if (SensorManager.remapCoordinateSystem(vector, x, y, remapped)) remapped else vector
                val now = tracker.update(MotionMath.aim(matrix))
                if (MotionMath.same(last, now)) return
                last = now
                sink.success(MotionAttitudeMsg(now.first, now.second))
            }

            override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
        }
        listener = l
        sensors.registerListener(l, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    private fun stop() {
        listener?.let(sensors::unregisterListener)
        listener = null
    }

    @Suppress("DEPRECATION")
    private fun displayRotation(): Int {
        val display: Display? = host.activity?.display
            ?: (context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager).getDisplay(Display.DEFAULT_DISPLAY)
        return display?.rotation ?: Surface.ROTATION_0
    }

    /** The new device axes for the screen rotation (the standard `remapCoordinateSystem` table). */
    private fun axesFor(rotation: Int): Pair<Int, Int> = when (rotation) {
        Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
        Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
        Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
        else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
    }

    fun dispose() = stop()
}
