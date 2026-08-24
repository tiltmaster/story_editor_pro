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

internal data class YawProjectedVertex(val x: Float, val z: Float)

/** Bounded 2.5D projection calibrated for the authored glasses mesh. */
internal object GlassesYawProjection {
    // The mesh's temple depth is ~1.6x its half-width. Feeding that depth into
    // yaw at 1:1 scale creates the long diagonal spike visible during turns.
    const val DEPTH_SCALE = 0.38f

    fun rotate(vertex: MeshVertex, yawRadians: Float): YawProjectedVertex {
        val cosYaw = kotlin.math.cos(yawRadians)
        val sinYaw = kotlin.math.sin(yawRadians)
        val depth = vertex.z * DEPTH_SCALE
        return YawProjectedVertex(
            x = vertex.x * cosYaw + depth * sinYaw,
            z = -vertex.x * sinYaw + depth * cosYaw,
        )
    }
}

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
