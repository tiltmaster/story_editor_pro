package com.storyeditorpro.ar

import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.os.SystemClock
import androidx.camera.effects.Frame

internal data class SegmentedBackground(
    val bitmap: Bitmap,
    val geometry: FaceFrameGeometry,
    val capturedMs: Long,
    val style: Int,
    val epoch: Int,
    val scene: Bitmap? = null,
)

/** Native composition is shared by preview, JPEG capture and recorded video. */
internal class PersonBackgroundRenderer {
    private val latest = BackgroundMaskCache<SegmentedBackground>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val maskPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
    }

    fun update(background: SegmentedBackground) {
        latest.update(background, background.capturedMs, background.style, background.epoch)
    }
    fun clear() { latest.clear() }

    fun current(style: Int, epoch: Int): SegmentedBackground? = latest.current(style, epoch)

    fun isReady(style: Int, epoch: Int): Boolean =
        latest.isReady(style, epoch, SystemClock.elapsedRealtime())

    fun draw(frame: Frame, background: SegmentedBackground, mirrorScene: Boolean = false) {
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
        val scene = background.scene
        if (scene == null) {
            frame.overlayCanvas.drawBitmap(bitmap, transform, paint)
            return
        }
        // Keep the photographic scene at its original resolution. Only the
        // segmentation alpha is low-resolution; Canvas scales it on the GPU.
        val canvas = frame.overlayCanvas
        val saved = canvas.save()
        try {
            canvas.concat(transform)
            val bounds = RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
            val layer = canvas.saveLayer(bounds, null)
            // The model's square mask is stretched back onto a portrait camera
            // frame. Fit the scene in camera space before that transform so
            // buildings and horizons keep their photographic proportions.
            val rotated = source.rotationDegrees % 180 != 0
            val sourceWidth = (if (rotated) source.height else source.width).toFloat()
            val sourceHeight = (if (rotated) source.width else source.height).toFloat()
            val scale = maxOf(sourceWidth / scene.width, sourceHeight / scene.height)
            val width = scene.width * scale / sourceWidth * bounds.width()
            val height = scene.height * scale / sourceHeight * bounds.height()
            val sceneSave = canvas.save()
            if (mirrorScene) canvas.scale(-1f, 1f, bounds.centerX(), bounds.centerY())
            canvas.drawBitmap(scene, null, RectF((bounds.width()-width)/2, (bounds.height()-height)/2,
                (bounds.width()+width)/2, (bounds.height()+height)/2), paint)
            canvas.restoreToCount(sceneSave)
            canvas.drawBitmap(bitmap, 0f, 0f, maskPaint)
            canvas.restoreToCount(layer)
        } finally { canvas.restoreToCount(saved) }
    }
}
