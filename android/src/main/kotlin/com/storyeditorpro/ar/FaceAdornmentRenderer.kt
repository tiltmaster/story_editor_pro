package com.storyeditorpro.ar

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.SystemClock
import androidx.camera.effects.Frame
import kotlin.math.*

/** Vector artwork anchored to the tracked eye axis, animated by capture time. */
internal class FaceAdornmentRenderer {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()

    fun draw(frame: Frame, pose: FacePose, lensId: String, intensity: Float) {
        val age = SystemClock.elapsedRealtime() - pose.receivedAtElapsedMs
        if (age > 180) return
        val crop = frame.cropRect
        val rotated = frame.rotationDegrees % 180 != 0
        val width = (if (rotated) crop.height() else crop.width()).toFloat()
        val height = (if (rotated) crop.width() else crop.height()).toFloat()
        fun upright(p: Point3f): Pair<Float, Float> {
            val point = FaceCoordinateTransform.bufferToDetector(p, frame.rotationDegrees)
            return point.x * width to point.y * height
        }
        val a = upright(pose.leftEye); val b = upright(pose.rightEye)
        val (left, right) = if (a.first <= b.first) a to b else b to a
        val distance = hypot(right.first - left.first, right.second - left.second)
        if (distance < 8) return
        val canvas = frame.overlayCanvas
        val save = canvas.save()
        try {
            canvas.clipRect(crop)
            canvas.translate(crop.exactCenterX(), crop.exactCenterY())
            canvas.rotate(-frame.rotationDegrees.toFloat())
            canvas.translate(-width / 2, -height / 2)
            canvas.translate((left.first + right.first) / 2, (left.second + right.second) / 2)
            canvas.rotate(Math.toDegrees(atan2((right.second-left.second).toDouble(), (right.first-left.first).toDouble())).toFloat())
            canvas.scale(distance, distance)
            val time = (frame.timestampNanos % 12_000_000_000L) / 1_000_000_000f
            val alpha = intensity * (1f - ((age - 100).coerceAtLeast(0) / 80f))
            if (lensId == "face_freckles") {
                for (side in intArrayOf(-1, 1)) for (i in 0 until 18) {
                    val x = side * (0.26f + ((i * 37) % 100) / 160f)
                    val y = 0.26f + ((i * 23) % 100) / 360f
                    paint.color = Color.argb((110 * alpha).toInt().coerceIn(0, 255), 112, 60, 40)
                    canvas.drawCircle(x, y, 0.009f + (i % 3) * 0.003f, paint)
                }
            } else {
                for (i in 0 until 7) {
                    val x = (i - 3) * 0.36f
                    val y = -0.72f - 0.32f * (1 - abs(i - 3) / 3f) + sin(time * 1.8f + i) * 0.045f
                    val radius = (0.09f + (i % 3) * 0.025f) * (1f + sin(time * 2.2f + i) * 0.12f)
                    paint.color = if (lensId == "face_hearts")
                        Color.argb((230 * alpha).toInt().coerceIn(0,255), 255, 126 + i*8, 173 + i*7)
                    else Color.argb((235 * alpha).toInt().coerceIn(0,255), 255, 224 + i*3, 155 + i*9)
                    if (lensId == "face_hearts") heart(canvas, x, y, radius)
                    else star(canvas, x, y, radius, time * 0.16f + i)
                }
                if (lensId == "face_celestial") {
                    for (side in intArrayOf(-1, 1)) for (i in 0 until 3) {
                        paint.color = Color.argb((200 * alpha).toInt().coerceIn(0,255), 255, 236, 195)
                        star(canvas, side * (0.45f + i * 0.17f), 0.3f + i * 0.025f,
                            0.038f + 0.012f * sin(time * 2 + i), 0f)
                    }
                }
            }
        } finally { canvas.restoreToCount(save) }
    }

    private fun star(canvas: Canvas, x: Float, y: Float, r: Float, angle: Float) {
        path.reset()
        for (i in 0 until 8) {
            val a = angle + i * PI.toFloat() / 4
            val radius = if (i % 2 == 0) r else r * 0.25f
            val px = x + cos(a)*radius; val py = y + sin(a)*radius
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        path.close(); canvas.drawPath(path, paint)
    }

    private fun heart(canvas: Canvas, x: Float, y: Float, r: Float) {
        path.reset(); path.moveTo(x, y + r)
        path.cubicTo(x-2*r, y-r*0.2f, x-r, y-1.6f*r, x, y-r*0.5f)
        path.cubicTo(x+r, y-1.6f*r, x+2*r, y-r*0.2f, x, y+r)
        path.close(); canvas.drawPath(path, paint)
    }
}
