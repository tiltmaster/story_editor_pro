package com.storyeditorpro.ar

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PorterDuff
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Size
import androidx.camera.core.CameraEffect
import androidx.camera.core.ImageAnalysis
import androidx.camera.effects.OverlayEffect
import androidx.camera.effects.Frame
import com.storyeditorpro.CameraMeteringFrame
import androidx.core.util.Consumer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

internal class FaceArController(
    private val context: Context,
    private val modelAssetPath: String,
    private val segmentationAssetPath: String,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, AutoCloseable {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val trackerExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "story-ar-tracker").apply { priority = Thread.NORM_PRIORITY }
    }
    private val segmentationExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "story-person-segmentation").apply { priority = Thread.NORM_PRIORITY }
    }
    private val segmentationInitializing = AtomicBoolean(false)
    private val backgroundEpoch = AtomicInteger()
    private val backgroundRenderer = PersonBackgroundRenderer()
    private val supported =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
    private val faceTrackingSupported =
        supported && assetExists(modelAssetPath)
    private val machine = FaceArStateMachine(supported)
    private val pose = AtomicReference<FacePose?>(null)
    private val smoother = FacePoseSmoother()
    private val creativeRenderer = CreativeLensRenderer(context)
    private val adornmentRenderer = FaceAdornmentRenderer()
    private val effectLock = Any()
    private val generation = AtomicInteger()
    @Volatile private var analysis: ImageAnalysis? = null
    private var overlayHadArtwork = false

    @Volatile private var settings = FaceArSettings(FaceArContract.LENS_NONE, 1f)
    @Volatile private var beautyEyes = 0f
    @Volatile private var beautySlim = 0f
    @Volatile private var backgroundStyle = 0
    @Volatile private var segmenter: MediaPipePersonSegmenter? = null
    private var lastBackgroundReady: Boolean? = null
    @Volatile private var creativeContext = CreativeLensContext()
    @Volatile private var tracker: MediaPipeFaceTracker? = null
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var overlayEffect: OverlayEffect? = null
    @Volatile private var glThread: HandlerThread? = null
    @Volatile private var lastTracked: Boolean? = null
    @Volatile private var closed = false
    private var lastPoseEventMs = 0L
    private var lastPoseEventTracked = false
    @Volatile var meteringFrame: CameraMeteringFrame? = null
        private set

    private fun needsFaceTracking(): Boolean = settings.lensId in FaceArContract.faceLensIds ||
        beautyEyes > 0f || beautySlim > 0f

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(
                mapOf(
                    "supported" to supported,
                    "backend" to FaceArContract.BACKEND,
                    "maxFaces" to 1,
                    "supports3D" to false,
                    "supportsRecording" to supported,
                    "faceTracking" to faceTrackingSupported,
                    "backgrounds" to (supported && assetExists(segmentationAssetPath)),
                    "preview" to supported,
                    "recording" to supported,
                    "lensIds" to if (supported) {
                        (FaceArContract.composedLensIds +
                            if (faceTrackingSupported) FaceArContract.faceLensIds else emptySet<String>()).toList()
                    } else emptyList<String>(),
                ),
            )
            "prepare" -> {
                val decision = machine.beginPrepare()
                emitState(decision.state)
                if (decision.startWork) {
                    if (needsFaceTracking()) initializeAsync() else emitState(machine.markReady())
                    if (backgroundStyle > 0) initializeBackgroundAsync()
                }
                result.success(mapOf("accepted" to decision.accepted))
            }
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")
                if (enabled == null) {
                    result.error("INVALID_ARGS", "enabled is required", null)
                } else {
                    val decision = machine.setEnabled(enabled)
                    if (!enabled) { clearTracking(); clearBackground() }
                    emitState(decision.state)
                    if (decision.startWork) {
                        if (needsFaceTracking()) initializeAsync()
                        else emitState(machine.markReady())
                    }
                    if (enabled && backgroundStyle > 0) initializeBackgroundAsync()
                    refreshAnalysis()
                    result.success(mapOf("state" to machine.state.wire, "faceReady" to (tracker != null)))
                }
            }
            "setLens" -> {
                val lensId = call.argument<String>("lensId")
                val intensity = call.argument<Number>("intensity")
                if (lensId == null || intensity == null) {
                    result.error("INVALID_ARGS", "lensId and intensity are required", null)
                } else {
                    try {
                        val nextSettings = FaceArSettings.validated(lensId, intensity)
                        fun beautyArgument(name: String): Float =
                            (call.argument<Number>(name)?.toFloat() ?: 0f).also {
                                require(it.isFinite())
                            }.coerceIn(0f, 1f)
                        val nextBeautyEyes = beautyArgument("beautyEyes")
                        val nextBeautySlim = beautyArgument("beautySlim")
                        val nextBackgroundStyle = (call.argument<Number>("backgroundStyle")?.toInt() ?: 0).also {
                            require(it in 0..4)
                        }
                        val nextContext = CreativeLensContext(
                            languageCode = call.argument<String>("languageCode")
                                ?.take(8)
                                ?.lowercase()
                                ?: "en",
                            countryCode = call.argument<String>("countryCode")
                                ?.take(3)
                                ?.uppercase()
                                ?: "",
                            mirrorOutput = call.argument<Boolean>("mirrorOutput") ?: false,
                            compositionId = (call.argument<String>("compositionId") ?: "none").also {
                                require(it == "none" || it in FaceArContract.composedLensIds)
                            },
                            placeStyle = (call.argument<String>("placeStyle") ?: "none").also {
                                require(it in FaceArContract.placeStyles)
                            },
                            placeName = call.argument<String>("placeName")?.trim()?.take(128) ?: "",

                        )
                        settings = nextSettings
                        beautyEyes = nextBeautyEyes
                        beautySlim = nextBeautySlim
                        if (backgroundStyle != nextBackgroundStyle) {
                            backgroundStyle = nextBackgroundStyle
                            clearBackground()
                        }
                        creativeContext = nextContext
                        if (!needsFaceTracking()) clearTracking()
                        if (needsFaceTracking() && tracker == null) initializeAsync()
                        if (backgroundStyle > 0 && segmenter == null) initializeBackgroundAsync()
                        if (settings.lensId in FaceArContract.composedLensIds || creativeContext.hasOverlay || backgroundStyle > 0) {
                            // Static authored lenses never wait for MediaPipe.
                            // They become available as soon as CameraX has an
                            // OverlayEffect surface, while face preparation can
                            // continue independently in the background.
                            emitState(machine.markReady())
                        }
                        refreshAnalysis()
                        result.success(null)
                    } catch (_: IllegalArgumentException) {
                        result.error("INVALID_ARGS", "Unsupported lens or invalid intensity", null)
                    }
                }
            }
            "dispose" -> {
                resetSession()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        emitState(machine.state)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun createImageAnalysis(targetRotation: Int): ImageAnalysis? {
        if (!supported || closed) return null
        analysis?.clearAnalyzer()
        return ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setTargetResolution(Size(480, 854))
            .setTargetRotation(targetRotation)
            .build()
            .also { analysis = it; refreshAnalysis() }
    }

    private fun refreshAnalysis() {
        val localAnalysis = analysis ?: return
        if (!machine.isActive() ||
            ((!needsFaceTracking() || tracker == null) && (backgroundStyle == 0 || segmenter == null))) {
            // Normal and text/place effects do not need a YUV stream or ML
            // callback. OverlayEffect now renders directly from camera frames.
            localAnalysis.clearAnalyzer()
            return
        }
        localAnalysis.setAnalyzer(trackerExecutor) { image ->
            val localTracker = tracker
            if (!machine.isActive()) {
                image.close()
            } else {
                if (backgroundStyle > 0) segmenter?.submit(image, backgroundStyle, backgroundEpoch.get())
                if (needsFaceTracking() && localTracker != null) localTracker.detect(image) else image.close()
            }
        }
    }

    fun cameraEffectOrNull(): CameraEffect? {
        if (!supported || closed) return null
        overlayEffect?.let { return it }
        synchronized(effectLock) {
            overlayEffect?.let { return it }
            val thread = HandlerThread(
                "story-ar-overlay",
                Process.THREAD_PRIORITY_DISPLAY,
            ).apply { start() }
            val effect = try {
                OverlayEffect(
                    EFFECT_TARGETS,
                    OVERLAY_QUEUE_DEPTH,
                    Handler(thread.looper),
                    Consumer { error: Throwable -> handleOverlayError(error) },
                )
            } catch (error: Throwable) {
                thread.quitSafely()
                throw error
            }
            try {
                effect.setOnDrawListener { frame ->
                    val currentGeometry = OverlayFrameCoordinates.geometry(frame)
                    val sensorTransform = FloatArray(9).also { frame.sensorToBufferTransform.getValues(it) }
                    meteringFrame = CameraMeteringFrame(currentGeometry, sensorTransform)
                    val localPose = pose.get()
                    val localSettings = settings
                    val localContext = creativeContext
                    if (machine.isActive() && needsFaceTracking()) emitPoseForFrame(frame, localPose)
                    val drawCreative = machine.isActive() &&
                        (localSettings.lensId in FaceArContract.composedLensIds || localContext.hasOverlay)
                    val drawFace = machine.isActive() && localPose != null &&
                        localSettings.lensId in FaceArContract.adornmentLensIds
                    val background = if (machine.isActive() && backgroundStyle > 0)
                        backgroundRenderer.current(backgroundStyle, backgroundEpoch.get()) else null
                    // getOverlayCanvas synchronizes a SurfaceTexture. Calling
                    // it on every unfiltered frame stalled startup unnecessarily.
                    // Clear once after removing artwork; then pass through.
                    if (drawCreative || drawFace || background != null || overlayHadArtwork) {
                        frame.overlayCanvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                        if (background != null) backgroundRenderer.draw(frame, background)
                        if (drawCreative) creativeRenderer.draw(
                            frame, localSettings.lensId, localSettings.intensity, localContext,
                        )
                        if (drawFace) adornmentRenderer.draw(
                            frame, requireNotNull(localPose), localSettings.lensId, localSettings.intensity,
                        )
                        overlayHadArtwork = drawCreative || drawFace || background != null
                    }
                    if (backgroundStyle > 0) emitBackground(background != null)
                    true
                }
            } catch (error: Throwable) {
                effect.close()
                thread.quitSafely()
                throw error
            }
            glThread = thread
            overlayEffect = effect
            return effect
        }
    }

    private fun initializeAsync() {
        val expectedGeneration = generation.get()
        trackerExecutor.execute {
            if (closed || generation.get() != expectedGeneration || tracker != null) {
                return@execute
            }
            if (!faceTrackingSupported) {
                emitState(machine.markReady())
                return@execute
            }
            try {
                val localTracker = MediaPipeFaceTracker.create(
                    context,
                    modelAssetPath,
                    onResult = { timestampNs, nextPose ->
                        if (!closed && generation.get() == expectedGeneration) {
                            onTrackingResult(timestampNs, nextPose)
                        }
                    },
                    onError = { error -> emitError("TRACKER_RUNTIME", error) },
                )
                if (closed || generation.get() != expectedGeneration) {
                    localTracker.close()
                    return@execute
                }
                tracker = localTracker
                emitState(machine.markReady())
                refreshAnalysis()
            } catch (error: Throwable) {
                val next = if (settings.lensId in FaceArContract.composedLensIds || creativeContext.hasOverlay) {
                    // Authored static lenses do not depend on face tracking.
                    machine.markReady()
                } else {
                    machine.markUnavailable()
                }
                emitState(next)
                emitError("PREPARE_FAILED", error)
            }
        }
    }

    private fun onTrackingResult(@Suppress("UNUSED_PARAMETER") timestampNs: Long, next: FacePose?) {
        val smoothPose = smoother.update(next)
        if (smoothPose == null) adornmentRenderer.clearExpressions()
        pose.set(smoothPose)
        emitTracking(smoothPose != null)
        // A zero-depth OverlayEffect consumes the freshest pose at render
        // time. Camera delivery is never held behind inference or model setup.
    }

    private fun initializeBackgroundAsync() {
        if (closed || segmenter != null || !segmentationInitializing.compareAndSet(false, true)) return
        val expectedGeneration = generation.get()
        segmentationExecutor.execute {
            try {
                if (closed || expectedGeneration != generation.get() || backgroundStyle == 0) return@execute
                val local = MediaPipePersonSegmenter(context, segmentationAssetPath, segmentationExecutor,
                    onResult = { background ->
                        if (!closed && expectedGeneration == generation.get() && machine.isActive() &&
                            background.epoch == backgroundEpoch.get() && background.style == backgroundStyle) {
                            backgroundRenderer.update(background)
                        }
                    },
                    onError = {
                        backgroundRenderer.clear()
                        emitBackground(false, "BACKGROUND_FAILED")
                    })
                if (closed || expectedGeneration != generation.get()) { local.close(); return@execute }
                segmenter = local
                emitState(machine.markReady())
                refreshAnalysis()
            } catch (_: Throwable) { emitBackground(false, "BACKGROUND_PREPARE_FAILED") }
            finally { segmentationInitializing.set(false) }
        }
    }

    private fun clearBackground() {
        backgroundEpoch.incrementAndGet()
        backgroundRenderer.clear()
        emitBackground(false, force = true)
    }

    @Synchronized private fun emitBackground(ready: Boolean, code: String? = null, force: Boolean = false) {
        if (!force && code == null && ready == lastBackgroundReady) return
        lastBackgroundReady = ready
        val event = mutableMapOf<String, Any>("type" to "background", "backgroundReady" to ready)
        if (code != null) {
            event["code"] = code
            event["message"] = "Background processing is unavailable"
        }
        emit(event)
    }

    private fun clearTracking() {
        adornmentRenderer.clearExpressions()
        smoother.clear()
        pose.set(null)
        emitTracking(false)
        if (lastPoseEventTracked) {
            lastPoseEventTracked = false
            emit(mapOf("type" to "pose", "faceTracked" to false, "timestampMs" to SystemClock.elapsedRealtime()))
        }
    }

    fun onCameraRebound() {
        // A previous camera's sensor transform cannot be reused for the next
        // camera, even though its face tracker instance can be kept warm.
        clearTracking()
        clearBackground()
        meteringFrame = null
        tracker?.discardPendingFrames()
    }

    fun onRecordingStarted(timestampMs: Long) {
        emit(mapOf("type" to "recordingStarted", "timestampMs" to timestampMs))
    }

    private fun emitPoseForFrame(frame: Frame, currentPose: FacePose?) {
        val now = SystemClock.elapsedRealtime()
        val fresh = currentPose?.takeIf { now - it.receivedAtElapsedMs <= 180L }
        if (fresh == null) {
            if (lastPoseEventTracked) {
                lastPoseEventTracked = false
                emit(mapOf("type" to "pose", "faceTracked" to false, "timestampMs" to now))
            }
            return
        }
        if (now - lastPoseEventMs < 67L) return
        val eyes = OverlayFrameCoordinates.uprightEyes(frame, fresh) ?: return
        val geometry = OverlayFrameCoordinates.geometry(frame)
        if (geometry.width <= 0f || geometry.height <= 0f) return
        val (left, right) = if (eyes.first.x <= eyes.second.x) eyes else eyes.second to eyes.first
        lastPoseEventMs = now
        lastPoseEventTracked = true
        emit(mapOf(
            "type" to "pose",
            "faceTracked" to true,
            "timestampMs" to now,
            "facePose" to mapOf(
                "leftX" to left.x / geometry.width, "leftY" to left.y / geometry.height,
                "rightX" to right.x / geometry.width, "rightY" to right.y / geometry.height,
            ),
        ))
    }

    private fun handleOverlayError(error: Throwable) {
        clearTracking()
        emitState(machine.markUnavailable())
        emitError("OVERLAY_ERROR", error)
    }

    /** Resets the current Flutter camera session without destroying reusable native resources. */
    private fun resetSession() {
        if (closed) return
        generation.incrementAndGet()
        emitState(machine.reset())
        clearTracking()
        clearBackground()
        analysis?.clearAnalyzer()
        val staleTracker = tracker
        tracker = null
        if (staleTracker != null) {
            trackerExecutor.execute { staleTracker.close() }
        }
        val staleSegmenter = segmenter
        segmenter = null
        if (staleSegmenter != null) segmentationExecutor.execute { staleSegmenter.close() }
    }

    private fun emitState(state: FaceArState) {
        emit(mapOf("type" to "state", "state" to state.wire, "faceReady" to (tracker != null)))
    }

    private fun emitTracking(tracked: Boolean) {
        if (lastTracked == tracked) return
        lastTracked = tracked
        emit(
            mapOf(
                "type" to "tracking",
                "state" to machine.state.wire,
                "faceTracked" to tracked,
            ),
        )
    }

    private fun emitError(code: String, cause: Throwable) {
        // Do not send native exception text: it may contain an APK asset or filesystem path.
        val safeMessage = when (code) {
            "PREPARE_FAILED" -> "AR preparation failed"
            "OVERLAY_ERROR" -> "AR overlay processing failed"
            else -> "AR face tracking failed"
        }
        emit(
            mapOf(
                "type" to "error",
                "state" to machine.state.wire,
                "code" to code,
                "message" to safeMessage,
            ),
        )
    }

    private fun emit(value: Map<String, Any>) {
        mainHandler.post {
            if (!closed) eventSink?.success(value)
        }
    }

    private fun assetExists(path: String): Boolean = try {
        context.assets.open(path).use { true }
    } catch (_: Exception) {
        false
    }

    override fun close() {
        if (closed) return
        closed = true
        generation.incrementAndGet()
        eventSink = null
        machine.dispose()
        pose.set(null)
        backgroundRenderer.clear()
        analysis?.clearAnalyzer()
        overlayEffect?.clearOnDrawListener()
        overlayEffect?.close()
        overlayEffect = null
        glThread?.quitSafely()
        glThread = null
        val staleTracker = tracker
        tracker = null
        if (staleTracker != null) trackerExecutor.execute { staleTracker.close() }
        trackerExecutor.shutdown()
        val staleSegmenter = segmenter
        segmenter = null
        if (staleSegmenter != null) segmentationExecutor.execute { staleSegmenter.close() }
        segmentationExecutor.shutdown()
    }

    companion object {
        internal const val OVERLAY_QUEUE_DEPTH = 0
        internal const val EFFECT_TARGETS =
            CameraEffect.PREVIEW or CameraEffect.VIDEO_CAPTURE or CameraEffect.IMAGE_CAPTURE
    }
}
