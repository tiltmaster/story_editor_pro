package com.storyeditorpro

import com.storyeditorpro.ar.OverlayGeometry
import kotlin.math.abs
import kotlin.math.roundToInt

internal data class CameraSensorBounds(val left: Float, val top: Float, val width: Float, val height: Float)
internal data class CameraMeteringFrame(val geometry: OverlayGeometry, val sensorToBuffer: FloatArray)

internal object CameraControlPolicy {
    fun zoom(value: Double, minimum: Float, maximum: Float): Float {
        require(value.isFinite() && minimum > 0f && maximum >= minimum)
        return value.coerceIn(minimum.toDouble(), maximum.toDouble()).toFloat()
    }

    fun exposureIndex(value: Double, step: Double, minimum: Int, maximum: Int): Int {
        require(value.isFinite() && step.isFinite() && step > 0.0 && maximum >= minimum)
        return (value / step).coerceIn(minimum.toDouble(), maximum.toDouble()).roundToInt()
    }

    /** Inverse effect transform, independent of display mirroring and current zoom. */
    fun focusPoint(x: Double, y: Double, frame: CameraMeteringFrame, sensor: CameraSensorBounds): Pair<Float, Float> {
        require(x.isFinite() && y.isFinite() && sensor.width > 0f && sensor.height > 0f)
        val buffer = frame.geometry.uprightToBuffer(
            x.coerceIn(0.0, 1.0).toFloat() * frame.geometry.width,
            y.coerceIn(0.0, 1.0).toFloat() * frame.geometry.height,
        )
        val m = frame.sensorToBuffer
        require(m.size == 9 && m.all { it.isFinite() })
        // CameraX's sensor-to-buffer matrix is affine. Inverting its scale,
        // rotation, reflection and translation also removes stream-sharing
        // transforms before CameraControl applies the current sensor zoom crop.
        val determinant = m[0] * m[4] - m[1] * m[3]
        require(abs(determinant) > .0000001f)
        val bx = buffer.x - m[2]
        val by = buffer.y - m[5]
        val sx = (m[4] * bx - m[1] * by) / determinant
        val sy = (-m[3] * bx + m[0] * by) / determinant
        return ((sx - sensor.left) / sensor.width).coerceIn(0f, 1f) to
            ((sy - sensor.top) / sensor.height).coerceIn(0f, 1f)
    }
}
