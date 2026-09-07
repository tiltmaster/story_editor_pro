package com.storyeditorpro.ar

import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.Paint
import android.os.SystemClock
import androidx.camera.effects.Frame
import java.util.concurrent.atomic.AtomicReference

internal data class SegmentedBackground(
    val bitmap: Bitmap,
    val geometry: FaceFrameGeometry,
    val capturedMs: Long,
    val style: Int,
    val epoch: Int,
)

/** Native composition is shared by preview, JPEG capture and recorded video. */
internal class PersonBackgroundRenderer {
    private val latest = AtomicReference<SegmentedBackground?>(null)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    fun update(background: SegmentedBackground) { latest.set(background) }
    fun clear() { latest.set(null) }

    fun current(style: Int, epoch: Int): SegmentedBackground? = latest.get()?.takeIf {
        it.style == style && it.epoch == epoch && BackgroundMaskPolicy.isFresh(it.capturedMs, SystemClock.elapsedRealtime())
    }

    fun draw(frame: Frame, background: SegmentedBackground) {
        val source = background.geometry
        val inverseSensor = Matrix()
        if (!Matrix().apply { setValues(source.sensorToBuffer) }.invert(inverseSensor)) return
        val corners = listOf(Point3f(0f, 0f, 0f), Point3f(1f, 0f, 0f), Point3f(0f, 1f, 0f))
            .map { FaceCoordinateTransform.detectorToBuffer(it, source.rotationDegrees) }
        val target = FloatArray(6)
        corners.forEachIndexed { i, p -> target[i * 2] = p.x * source.width; target[i * 2 + 1] = p.y * source.height }
        inverseSensor.mapPoints(target)
        frame.sensorToBufferTransform.mapPoints(target)
        val bitmap = background.bitmap
        val transform = Matrix()
        if (!transform.setPolyToPoly(floatArrayOf(0f, 0f, bitmap.width.toFloat(), 0f, 0f, bitmap.height.toFloat()),
                0, target, 0, 3)) return
        // The frame subsequently applies crop/rotation/mirroring to camera and
        // matte together; adding a separate selfie mirror here would misalign it.
        frame.overlayCanvas.drawBitmap(bitmap, transform, paint)
    }
}
