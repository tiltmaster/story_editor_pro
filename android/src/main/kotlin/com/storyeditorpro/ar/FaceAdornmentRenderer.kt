package com.storyeditorpro.ar

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.LinearGradient
import android.graphics.Shader
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
        val eyes = OverlayFrameCoordinates.uprightEyes(frame, pose) ?: return
        val a = eyes.first.x to eyes.first.y; val b = eyes.second.x to eyes.second.y
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
            val time = (frame.timestampNanos % 12_000_000_000L) / 1_000_000_000f
            val alpha = intensity * (1f - ((age - 100).coerceAtLeast(0) / 80f))
            if (lensId == "face_neon") {
                val contour = OverlayFrameCoordinates.uprightPoints(frame, pose, pose.contour)
                if (contour != null && contour.size >= 12) drawNeon(canvas, contour, distance, time, alpha)
                return
            }
            canvas.translate((left.first + right.first) / 2, (left.second + right.second) / 2)
            canvas.rotate(Math.toDegrees(atan2((right.second-left.second).toDouble(), (right.first-left.first).toDouble())).toFloat())
            canvas.scale(distance, distance)
            if (lensId == "face_butterflies") {
                for (i in 0 until 5) {
                    val x = (i - 2) * .49f
                    val y = -.86f - .24f * (1 - abs(i - 2) / 2f) + sin(time * 1.5f + i) * .055f
                    butterfly(canvas, x, y, .20f + .025f * (i % 2), time * 4f + i, alpha)
                }
            } else if (lensId == "face_freckles") {
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

    private fun drawNeon(canvas: Canvas, contour: List<Point3f>, distance: Float, time: Float, alpha: Float) {
        path.reset()
        contour.forEachIndexed { index, point ->
            if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y)
        }
        path.close()
        val left = contour.minOf { it.x }; val right = contour.maxOf { it.x }
        val top = contour.minOf { it.y }; val bottom = contour.maxOf { it.y }
        paint.shader = LinearGradient(left, top, right, bottom,
            intArrayOf(Color.rgb(97, 250, 243), Color.rgb(162, 126, 255), Color.rgb(255, 121, 197)),
            null, Shader.TileMode.CLAMP)
        paint.style = Paint.Style.STROKE
        paint.strokeJoin = Paint.Join.ROUND
        for ((width, opacity) in listOf(.075f to 24, .035f to 65, .009f to 230)) {
            paint.strokeWidth = distance * width
            paint.alpha = (opacity * alpha * (.88f + .12f * sin(time * 1.7f))).toInt().coerceIn(0, 255)
            canvas.drawPath(path, paint)
        }
        paint.shader = null; paint.style = Paint.Style.FILL; paint.alpha = 255
    }

    private fun butterfly(canvas: Canvas, x: Float, y: Float, radius: Float, phase: Float, alpha: Float) {
        val save = canvas.save()
        canvas.translate(x, y)
        canvas.rotate(sin(phase * .3f) * 12f)
        canvas.scale(radius * (.55f + abs(cos(phase)) * .45f), radius)
        for (side in intArrayOf(-1, 1)) {
            val wingSave = canvas.save(); canvas.scale(side.toFloat(), 1f)
            path.reset(); path.moveTo(0f, 0f)
            path.cubicTo(.8f, -1.6f, 1.65f, -1.15f, 1.3f, -.25f)
            path.cubicTo(1.7f, .55f, .75f, 1.4f, .1f, .35f); path.close()
            paint.shader = LinearGradient(0f, -1f, 1.1f, .8f,
                Color.argb((235 * alpha).toInt().coerceIn(0, 255), 151, 155, 255),
                Color.argb((220 * alpha).toInt().coerceIn(0, 255), 255, 170, 209), Shader.TileMode.CLAMP)
            canvas.drawPath(path, paint); paint.shader = null
            paint.color = Color.argb((185 * alpha).toInt().coerceIn(0, 255), 251, 241, 255)
            paint.strokeWidth = .045f; paint.style = Paint.Style.STROKE
            canvas.drawPath(path, paint); paint.style = Paint.Style.FILL
            canvas.drawCircle(.85f, -.5f, .13f, paint)
            canvas.restoreToCount(wingSave)
        }
        paint.color = Color.argb((240 * alpha).toInt().coerceIn(0, 255), 243, 228, 255)
        canvas.drawRoundRect(-.065f, -.40f, .065f, .64f, .065f, .065f, paint)
        paint.strokeWidth = .035f
        canvas.drawLine(0f, -.35f, -.22f, -.7f, paint); canvas.drawLine(0f, -.35f, .22f, -.7f, paint)
        canvas.restoreToCount(save)
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
