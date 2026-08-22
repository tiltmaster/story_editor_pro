package com.storyeditorpro.ar

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.atan
import kotlin.math.hypot

internal class MediaPipeFaceTracker private constructor(
    context: Context,
    modelAssetPath: String,
    private val onResult: (timestampNs: Long, pose: FacePose?) -> Unit,
    private val onError: (Throwable) -> Unit,
) : AutoCloseable {
    private val timestamps = TimestampLedger()
    private val modelBuffer: ByteBuffer
    private val landmarker: FaceLandmarker
    val delegateName: String

    init {
        val bytes = context.assets.open(modelAssetPath).use { it.readBytes() }
        modelBuffer = ByteBuffer.allocateDirect(bytes.size)
            .order(ByteOrder.nativeOrder())
            .apply {
                put(bytes)
                rewind()
            }
        var chosen = "gpu"
        landmarker = try {
            createLandmarker(context, Delegate.GPU)
        } catch (_: RuntimeException) {
            chosen = "cpu"
            modelBuffer.rewind()
            createLandmarker(context, Delegate.CPU)
        }
        delegateName = chosen
    }

    private fun createLandmarker(context: Context, delegate: Delegate): FaceLandmarker {
        val base = BaseOptions.builder()
            .setModelAssetBuffer(modelBuffer)
            .setDelegate(delegate)
            .build()
        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setOutputFaceBlendshapes(false)
            .setOutputFacialTransformationMatrixes(false)
            .setResultListener { result, input -> handleResult(result, input) }
            .setErrorListener { error -> handleError(error) }
            .build()
        return FaceLandmarker.createFromOptions(context, options)
    }

    /** Called by the same serial executor that creates the GPU delegate. */
    fun detect(image: ImageProxy) {
        val timestampNs = image.imageInfo.timestamp
        val rotation = ((image.imageInfo.rotationDegrees % 360) + 360) % 360
        val timestampMs = timestamps.record(timestampNs, rotation)
        val source = try {
            image.toBitmap()
        } finally {
            image.close()
        }
        var oriented: Bitmap? = null
        var mpImage: MPImage? = null
        try {
            val matrix = Matrix().apply {
                postRotate(rotation.toFloat())
            }
            oriented = if (rotation == 0) {
                source
            } else {
                Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            }
            if (oriented !== source) source.recycle()
            mpImage = BitmapImageBuilder(oriented).build()
            landmarker.detectAsync(mpImage, timestampMs)
            // The MPImage reference is released in the MediaPipe result callback.
        } catch (error: Throwable) {
            timestamps.take(timestampMs)
            mpImage?.close()
            if (oriented != null && oriented !== source && !oriented.isRecycled) oriented.recycle()
            if (!source.isRecycled) source.recycle()
            onError(error)
        }
    }

    private fun handleResult(result: FaceLandmarkerResult, input: MPImage) {
        try {
            val frame = timestamps.take(result.timestampMs()) ?: return
            val landmarks = result.faceLandmarks().firstOrNull()
            onResult(
                frame.timestampNs,
                landmarks?.let { poseFrom(it, frame.rotation) },
            )
        } catch (error: Throwable) {
            onError(error)
        } finally {
            input.close()
        }
    }

    private fun handleError(error: RuntimeException) {
        timestamps.clear()
        onError(error)
    }

    private fun poseFrom(
        points: List<NormalizedLandmark>,
        rotation: Int,
    ): FacePose {
        require(points.size > 362) { "Face landmark result is incomplete" }
        fun raw(index: Int): Point3f {
            val point = points[index]
            val x = point.x()
            val y = point.y()
            // Invert the detector-only rotation exactly once so the result returns to
            // camera buffer coordinates. CameraX mirrors/rotates camera pixels and overlay
            // together after composition, including for the front camera.
            return FaceCoordinateTransform.detectorToBuffer(Point3f(x, y, point.z()), rotation)
        }
        fun average(a: Point3f, b: Point3f) = Point3f(
            (a.x + b.x) * 0.5f,
            (a.y + b.y) * 0.5f,
            (a.z + b.z) * 0.5f,
        )
        val left = average(raw(33), raw(133))
        val right = average(raw(362), raw(263))
        val nose = raw(1)
        val dx = right.x - left.x
        val dy = right.y - left.y
        val eyeDistance = hypot(dx, dy).coerceAtLeast(0.0001f)
        val midX = (left.x + right.x) * 0.5f
        val midY = (left.y + right.y) * 0.5f
        val alongEyeAxis = ((nose.x - midX) * dx + (nose.y - midY) * dy) /
            (eyeDistance * eyeDistance)
        val yaw = atan((alongEyeAxis * 2.2f).toDouble()).toFloat().coerceIn(-0.85f, 0.85f)
        return FacePose(left, right, yaw)
    }

    override fun close() {
        timestamps.clear()
        landmarker.close()
    }

    companion object {
        fun create(
            context: Context,
            modelAssetPath: String,
            onResult: (Long, FacePose?) -> Unit,
            onError: (Throwable) -> Unit,
        ) = MediaPipeFaceTracker(context, modelAssetPath, onResult, onError)
    }
}
