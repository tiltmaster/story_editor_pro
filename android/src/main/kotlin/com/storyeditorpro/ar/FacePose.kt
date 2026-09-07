package com.storyeditorpro.ar

import android.os.SystemClock
import kotlin.math.atan
import kotlin.math.hypot

internal data class Point3f(val x: Float, val y: Float, val z: Float)

internal data class FacePose(
    val leftEye: Point3f,
    val rightEye: Point3f,
    val yawRadians: Float,
    val receivedAtElapsedMs: Long = SystemClock.elapsedRealtime(),
    val frameGeometry: FaceFrameGeometry? = null,
    val contour: List<Point3f> = emptyList(),
    val expression: FaceExpression = FaceExpression(),
)

/** The analysis buffer can differ in crop, scale and rotation from the effect buffer. */
internal data class FaceFrameGeometry(
    val width: Int,
    val height: Int,
    val rotationDegrees: Int,
    val sensorToBuffer: FloatArray,
)

/**
 * Produces a screen-space pose with a stable left-to-right eye axis.
 *
 * MediaPipe labels anatomical eyes, so their X ordering reverses when the
 * input is mirrored or the head turns far enough. Renderers must not use that
 * semantic ordering as a screen-space axis: doing so changes roll by PI and
 * throws a temple across the face. The visual ordering below stays continuous
 * for both front/back cameras while retaining a signed yaw proxy.
 */
internal object FacePoseEstimator {
    fun estimate(
        firstEye: Point3f,
        secondEye: Point3f,
        nose: Point3f,
        receivedAtElapsedMs: Long,
    ): FacePose {
        val (left, right) = if (firstEye.x <= secondEye.x) {
            firstEye to secondEye
        } else {
            secondEye to firstEye
        }
        val dx = right.x - left.x
        val dy = right.y - left.y
        val eyeDistance = hypot(dx, dy).coerceAtLeast(0.0001f)
        val midX = (left.x + right.x) * 0.5f
        val midY = (left.y + right.y) * 0.5f
        val alongEyeAxis = ((nose.x - midX) * dx + (nose.y - midY) * dy) /
            (eyeDistance * eyeDistance)
        val yaw = atan((alongEyeAxis * 2.2f).toDouble())
            .toFloat()
            .coerceIn(-0.85f, 0.85f)
        return FacePose(left, right, yaw, receivedAtElapsedMs)
    }
}

/** Inverts the detector-only bitmap rotation back into CameraX buffer coordinates. */
internal object FaceCoordinateTransform {
    fun bufferToDetector(point: Point3f, rotationDegrees: Int): Point3f =
        when (((rotationDegrees % 360) + 360) % 360) {
            90 -> Point3f(1f - point.y, point.x, point.z)
            180 -> Point3f(1f - point.x, 1f - point.y, point.z)
            270 -> Point3f(point.y, 1f - point.x, point.z)
            else -> point
        }

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
            next.frameGeometry,
            if (old.contour.size == next.contour.size) old.contour.zip(next.contour, ::point) else next.contour,
            next.expression,
        ).also { previous = it }
    }

    @Synchronized
    fun clear() {
        previous = null
    }
}
