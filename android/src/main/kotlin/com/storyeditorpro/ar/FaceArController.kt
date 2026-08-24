package com.storyeditorpro.ar

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PorterDuff
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.util.Size
import androidx.camera.core.CameraEffect
import androidx.camera.core.ImageAnalysis
import androidx.camera.effects.OverlayEffect
import androidx.core.util.Consumer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

internal class FaceArController(
    private val context: Context,
    private val modelAssetPath: String,
    private val meshAssetPaths: Map<String, String>,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, AutoCloseable {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val trackerExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "story-ar-tracker").apply { priority = Thread.NORM_PRIORITY }
    }
    private val supported =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) &&
            assetExists(modelAssetPath) &&
            FaceArContract.glassesLensIds.all { lensId ->
                meshAssetPaths[lensId]?.let(::assetExists) == true
            }
    private val machine = FaceArStateMachine(supported)
    private val pose = AtomicReference<FacePose?>(null)
    private val smoother = FacePoseSmoother()
    private val renderer = ClassicGlassesRenderer()
    private val effectLock = Any()
    private val generation = AtomicInteger()

    @Volatile private var settings = FaceArSettings(FaceArContract.LENS_NONE, 1f)
    @Volatile private var tracker: MediaPipeFaceTracker? = null
    @Volatile private var meshes: Map<String, RuntimeMesh> = emptyMap()
    @Volatile private var eventSink: EventChannel.EventSink? = null
    @Volatile private var overlayEffect: OverlayEffect? = null
    @Volatile private var glThread: HandlerThread? = null
    @Volatile private var lastTracked: Boolean? = null
    @Volatile private var closed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(
                mapOf(
                    "supported" to supported,
                    "backend" to FaceArContract.BACKEND,
                    "maxFaces" to 1,
                    "supports3D" to supported,
                    "supportsRecording" to supported,
                    "faceTracking" to supported,
                    "preview" to supported,
                    "recording" to supported,
                    "lensIds" to if (supported) FaceArContract.glassesLensIds.toList() else emptyList<String>(),
                ),
            )
            "prepare" -> {
                val decision = machine.beginPrepare()
                emitState(decision.state)
                if (decision.startWork) initializeAsync()
                result.success(mapOf("accepted" to decision.accepted))
            }
            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled")
                if (enabled == null) {
                    result.error("INVALID_ARGS", "enabled is required", null)
                } else {
                    val decision = machine.setEnabled(enabled)
                    if (!enabled) clearTracking()
                    emitState(decision.state)
                    if (decision.startWork) initializeAsync()
                    result.success(null)
                }
            }
            "setLens" -> {
                val lensId = call.argument<String>("lensId")
                val intensity = call.argument<Number>("intensity")
                if (lensId == null || intensity == null) {
                    result.error("INVALID_ARGS", "lensId and intensity are required", null)
                } else {
                    try {
                        settings = FaceArSettings.validated(lensId, intensity)
                        renderer.mesh = meshes[settings.lensId]
                        if (settings.lensId == FaceArContract.LENS_NONE) clearTracking()
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
        return ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .setTargetResolution(Size(480, 854))
            .setTargetRotation(targetRotation)
            .build()
            .also { analysis ->
                analysis.setAnalyzer(trackerExecutor) { image ->
                    val localTracker = tracker
                    if (
                        !machine.isActive() ||
                        settings.lensId == FaceArContract.LENS_NONE ||
                        localTracker == null
                    ) {
                        image.close()
                    } else {
                        localTracker.detect(image)
                    }
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
            val effect = OverlayEffect(
                EFFECT_TARGETS,
                3,
                Handler(thread.looper),
                Consumer { error: Throwable -> handleOverlayError(error) },
            )
            effect.setOnDrawListener { frame ->
                val canvas = frame.overlayCanvas
                canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                val localPose = pose.get()
                val localSettings = settings
                if (
                    machine.isActive() &&
                    localSettings.lensId in FaceArContract.glassesLensIds &&
                    localPose != null
                ) {
                    renderer.draw(frame, localPose, localSettings.intensity)
                }
                true
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
            try {
                val localMeshes = meshAssetPaths.mapValues { (_, path) ->
                    RuntimeMesh.load(context, path)
                }
                val localTracker = MediaPipeFaceTracker.create(
                    context,
                    modelAssetPath,
                    onResult = { timestampNs, nextPose ->
                        onTrackingResult(timestampNs, nextPose)
                    },
                    onError = { error -> emitError("TRACKER_RUNTIME", error) },
                )
                if (closed || generation.get() != expectedGeneration) {
                    localTracker.close()
                    return@execute
                }
                meshes = localMeshes
                renderer.mesh = localMeshes[settings.lensId]
                tracker = localTracker
                emitState(machine.markReady())
            } catch (error: Throwable) {
                emitState(machine.markUnavailable())
                emitError("PREPARE_FAILED", error)
            }
        }
    }

    private fun onTrackingResult(timestampNs: Long, next: FacePose?) {
        val smoothPose = smoother.update(next)
        pose.set(smoothPose)
        emitTracking(smoothPose != null)
        try {
            overlayEffect?.drawFrameAsync(timestampNs)
        } catch (_: IllegalStateException) {
            // The camera effect may be closing concurrently with the tracker callback.
        }
    }

    private fun clearTracking() {
        smoother.clear()
        pose.set(null)
        emitTracking(false)
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
        renderer.mesh = null
        meshes = emptyMap()
        val staleTracker = tracker
        tracker = null
        if (staleTracker != null) {
            trackerExecutor.execute { staleTracker.close() }
        }
    }

    private fun emitState(state: FaceArState) {
        emit(mapOf("type" to "state", "state" to state.wire))
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
        renderer.mesh = null
        meshes = emptyMap()
        overlayEffect?.clearOnDrawListener()
        overlayEffect?.close()
        overlayEffect = null
        glThread?.quitSafely()
        glThread = null
        val staleTracker = tracker
        tracker = null
        if (staleTracker != null) trackerExecutor.execute { staleTracker.close() }
        trackerExecutor.shutdown()
    }

    companion object {
        internal const val EFFECT_TARGETS =
            CameraEffect.PREVIEW or CameraEffect.VIDEO_CAPTURE or CameraEffect.IMAGE_CAPTURE
    }
}
