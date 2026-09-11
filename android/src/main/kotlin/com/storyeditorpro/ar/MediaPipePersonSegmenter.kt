package com.storyeditorpro.ar

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt

/** One inference in flight on a dedicated worker; camera frames never wait for it. */
internal class MediaPipePersonSegmenter(
    context: Context,
    modelAssetPath: String,
    sceneAssetPaths: Map<Int, String>,
    private val executor: ExecutorService,
    private val customSource: CustomBackgroundSource,
    private val onResult: (SegmentedBackground) -> Unit,
    private val onError: (Throwable) -> Unit,
) : AutoCloseable {
    private val scenes = sceneAssetPaths.mapValues { (_, path) ->
        context.assets.open(path).use { android.graphics.BitmapFactory.decodeStream(it)
            ?: error("Could not decode background scene") }
    }
    private val busy = AtomicBoolean(false)
    @Volatile private var closed = false
    private var lastTimestampMs = 0L
    private val modelBuffer = context.assets.open(modelAssetPath).use { it.readBytes() }.let { bytes ->
        ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).apply { put(bytes); rewind() }
    }
    private val task = ImageSegmenter.createFromOptions(context,
        ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(modelBuffer).setDelegate(Delegate.CPU).build())
            .setRunningMode(RunningMode.VIDEO)
            .setOutputCategoryMask(false)
            .setOutputConfidenceMasks(true)
            .build())

    /** Borrows ImageProxy only during this call; its owner still closes it. */
    fun submit(image: ImageProxy, style: Int, epoch: Int) {
        if (closed || !busy.compareAndSet(false, true)) return
        val capturedMs = SystemClock.elapsedRealtime()
        var prepared: Bitmap? = null
        try {
            val rotation = ((image.imageInfo.rotationDegrees % 360) + 360) % 360
            val transform = FloatArray(9).also { image.imageInfo.sensorToBufferTransformMatrix.getValues(it) }
            val geometry = FaceFrameGeometry(image.width, image.height, rotation, transform)
            val source = image.toBitmap()
            val scale = (384f / max(source.width, source.height)).coerceAtMost(1f)
            val matrix = Matrix().apply { postScale(scale, scale); postRotate(rotation.toFloat()) }
            prepared = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            if (prepared !== source) source.recycle()
            val bitmap = requireNotNull(prepared)
            executor.execute {
                try {
                    if (!closed) segment(bitmap, geometry, capturedMs, style, epoch)
                } catch (error: Throwable) { if (!closed) onError(error) }
                finally { if (!bitmap.isRecycled) bitmap.recycle(); busy.set(false) }
            }
        } catch (error: Throwable) {
            prepared?.takeUnless { it.isRecycled }?.recycle()
            busy.set(false)
            if (!closed) onError(error)
        }
    }

    private fun segment(bitmap: Bitmap, geometry: FaceFrameGeometry, capturedMs: Long, style: Int, epoch: Int) {
        val input = BitmapImageBuilder(bitmap).build()
        try {
            lastTimestampMs = max(lastTimestampMs + 1L, capturedMs)
            val result = task.segmentForVideo(input, lastTimestampMs)
            val masks = result.confidenceMasks().orElse(emptyList())
            try {
                // The bundled model has exactly one float32 output channel,
                // labelled "selfie": its values are person confidence.
                val mask = masks.singleOrNull() ?: error("Unexpected selfie mask channels")
                val width = mask.width
                val height = mask.height
                val confidence = ByteBufferExtractor.extract(mask).order(ByteOrder.nativeOrder()).asFloatBuffer()
                val pixels = if (style == 4) blurredBackground(bitmap, width, height) else IntArray(width * height)
                for (y in 0 until height) for (x in 0 until width) {
                    val i = y * width + x
                    val alpha = BackgroundMaskPolicy.backgroundAlpha(confidence.get(i))
                    val rgb = if (style == 4) pixels[i] and 0xFFFFFF else
                        BackgroundMaskPolicy.color(style, x.toFloat() / max(1, width - 1), y.toFloat() / max(1, height - 1))
                    pixels[i] = (alpha shl 24) or rgb
                }
                // There is only one request in flight. A completed slow request
                // is still our newest matte; discarding it made scenes vanish
                // whenever inference exceeded the old 250 ms display deadline.
                if (!closed) {
                    onResult(SegmentedBackground(Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888),
                        geometry, capturedMs, style, epoch, if (style == 5) requireNotNull(customSource.frame()) else scenes[style]))
                }
            } finally { masks.forEach { it.close() } }
        } finally { input.close() }
    }

    /** Downsample, box-filter and reconstruct actual captured background colors. */
    private fun blurredBackground(source: Bitmap, width: Int, height: Int): IntArray {
        val smallWidth = max(12, (width / 12f).roundToInt())
        val smallHeight = max(12, (height / 12f).roundToInt())
        val small = Bitmap.createScaledBitmap(source, smallWidth, smallHeight, true)
        val pixels = IntArray(smallWidth * smallHeight)
        small.getPixels(pixels, 0, smallWidth, 0, 0, smallWidth, smallHeight)
        val softened = IntArray(pixels.size)
        for (y in 0 until smallHeight) for (x in 0 until smallWidth) {
            var r = 0; var g = 0; var b = 0; var count = 0
            for (dy in -2..2) for (dx in -2..2) {
                val color = pixels[(y + dy).coerceIn(0, smallHeight - 1) * smallWidth + (x + dx).coerceIn(0, smallWidth - 1)]
                r += (color shr 16) and 255; g += (color shr 8) and 255; b += color and 255; count++
            }
            softened[y * smallWidth + x] = (255 shl 24) or ((r / count) shl 16) or ((g / count) shl 8) or (b / count)
        }
        small.setPixels(softened, 0, smallWidth, 0, 0, smallWidth, smallHeight)
        val blurred = Bitmap.createScaledBitmap(small, width, height, true)
        val result = IntArray(width * height)
        blurred.getPixels(result, 0, width, 0, 0, width, height)
        if (blurred !== small) blurred.recycle()
        if (small !== source) small.recycle()
        return result
    }

    /** Called on the same worker as inference. */
    override fun close() { closed = true; task.close(); customSource.close() }
}
