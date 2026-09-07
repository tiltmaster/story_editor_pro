package com.storyeditorpro.ar

import android.graphics.Matrix
import androidx.camera.effects.Frame

internal object OverlayFrameCoordinates {
    fun geometry(frame: Frame): OverlayGeometry = frame.cropRect.let {
        OverlayGeometry(it.left.toFloat(), it.top.toFloat(), it.width().toFloat(), it.height().toFloat(), frame.rotationDegrees)
    }

    /** Analysis pixels -> sensor -> actual effect buffer -> cropped upright image. */
    fun uprightEyes(frame: Frame, pose: FacePose): Pair<Point3f, Point3f>? {
        val points = uprightPoints(frame, pose, listOf(pose.leftEye, pose.rightEye)) ?: return null
        return points[0] to points[1]
    }

    fun uprightPoints(frame: Frame, pose: FacePose, sourcePoints: List<Point3f>): List<Point3f>? {
        val geometry = geometry(frame)
        val source = pose.frameGeometry ?: return null
        val toSensor = Matrix()
        if (!Matrix().apply { setValues(source.sensorToBuffer) }.invert(toSensor)) return null
        val points = FloatArray(sourcePoints.size * 2)
        sourcePoints.forEachIndexed { index, point ->
            points[index * 2] = point.x * source.width
            points[index * 2 + 1] = point.y * source.height
        }
        toSensor.mapPoints(points)
        frame.sensorToBufferTransform.mapPoints(points)
        return sourcePoints.indices.map { geometry.bufferToUpright(points[it * 2], points[it * 2 + 1]) }
    }
}
