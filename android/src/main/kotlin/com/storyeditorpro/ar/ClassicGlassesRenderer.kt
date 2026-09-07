package com.storyeditorpro.ar

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.SystemClock
import androidx.camera.effects.Frame
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin

internal class ClassicGlassesRenderer {
    @Volatile
    var mesh: RuntimeMesh? = null

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val path = Path()
    private var projectedX = FloatArray(0)
    private var projectedY = FloatArray(0)

    fun draw(frame: Frame, pose: FacePose, intensity: Float) {
        if (SystemClock.elapsedRealtime() - pose.receivedAtElapsedMs > 160L) return
        val localMesh = mesh ?: return
        val crop = frame.cropRect
        if (crop.isEmpty) return
        if (projectedX.size != localMesh.vertices.size) {
            projectedX = FloatArray(localMesh.vertices.size)
            projectedY = FloatArray(localMesh.vertices.size)
        }

        fun screenX(x: Float) = crop.left + x * crop.width()
        fun screenY(y: Float) = crop.top + y * crop.height()
        val leftX = screenX(pose.leftEye.x)
        val leftY = screenY(pose.leftEye.y)
        val rightX = screenX(pose.rightEye.x)
        val rightY = screenY(pose.rightEye.y)
        val scale = hypot(rightX - leftX, rightY - leftY).coerceAtLeast(1f)
        val centerX = (leftX + rightX) * 0.5f
        val centerY = (leftY + rightY) * 0.5f + scale * 0.035f
        val roll = atan2(rightY - leftY, rightX - leftX)
        val cosRoll = cos(roll)
        val sinRoll = sin(roll)

        for (index in localMesh.vertices.indices) {
            val vertex = localMesh.vertices[index]
            val rotated = GlassesYawProjection.rotate(vertex, pose.yawRadians)
            val perspective = 3.8f / (3.8f - rotated.z * 0.34f).coerceAtLeast(1.25f)
            val x = rotated.x * scale * perspective
            val y = -vertex.y * scale * perspective
            projectedX[index] = centerX + x * cosRoll - y * sinRoll
            projectedY[index] = centerY + x * sinRoll + y * cosRoll
        }

        val canvas = frame.overlayCanvas
        canvas.save()
        canvas.clipRect(crop)
        // Draw translucent authored lenses before the opaque authored frame.
        for (materialPass in intArrayOf(1, 0)) {
            for (triangle in localMesh.triangles) {
                if (triangle.materialId != materialPass) continue
                val base = localMesh.materialColors[triangle.materialId] ?: Color.BLACK
                val alpha = (Color.alpha(base) * intensity.coerceIn(0f, 1f))
                    .roundToInt()
                    .coerceIn(0, 255)
                paint.color = (base and 0x00ffffff) or (alpha shl 24)
                path.reset()
                path.moveTo(projectedX[triangle.a], projectedY[triangle.a])
                path.lineTo(projectedX[triangle.b], projectedY[triangle.b])
                path.lineTo(projectedX[triangle.c], projectedY[triangle.c])
                path.close()
                canvas.drawPath(path, paint)
            }
        }
        canvas.restore()
    }
}
