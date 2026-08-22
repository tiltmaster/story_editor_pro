package com.storyeditorpro.ar

import android.os.SystemClock

internal data class Point3f(val x: Float, val y: Float, val z: Float)

internal data class FacePose(
    val leftEye: Point3f,
    val rightEye: Point3f,
    val yawRadians: Float,
    val receivedAtElapsedMs: Long = SystemClock.elapsedRealtime(),
)

/** Inverts the detector-only bitmap rotation back into CameraX buffer coordinates. */
internal object FaceCoordinateTransform {
    fun detectorToBuffer(point: Point3f, rotationDegrees: Int): Point3f =
        when (((rotationDegrees % 360) + 360) % 360) {
            90 -> Point3f(point.y, 1f - point.x, point.z)
            180 -> Point3f(1f - point.x, 1f - point.y, point.z)
            270 -> Point3f(1f - point.y, point.x, point.z)
            else -> point
        }
}

internal class FacePoseSmoother(private val alpha: Float = 0.58f) {
    private var previous: FacePose? = null

    @Synchronized
    fun update(next: FacePose?): FacePose? {
        if (next == null) {
            previous = null
            return null
        }
        val old = previous ?: return next.also { previous = it }
        fun value(a: Float, b: Float) = a + (b - a) * alpha
        fun point(a: Point3f, b: Point3f) = Point3f(
            value(a.x, b.x),
            value(a.y, b.y),
            value(a.z, b.z),
        )
        return FacePose(
            point(old.leftEye, next.leftEye),
            point(old.rightEye, next.rightEye),
            value(old.yawRadians, next.yawRadians),
            next.receivedAtElapsedMs,
        ).also { previous = it }
    }

    @Synchronized
    fun clear() {
        previous = null
    }
}
