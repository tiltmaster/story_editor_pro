package com.storyeditorpro

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.PointF
import android.hardware.camera2.CameraCharacteristics
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Rational
import android.util.Range
import android.view.Surface
import androidx.camera.core.*
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.video.*
import androidx.camera.video.VideoCapture
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.storyeditorpro.ar.FaceArContract
import com.storyeditorpro.ar.FaceArController
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import com.google.common.util.concurrent.ListenableFuture

class StoryEditorProPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var arMethodChannel: MethodChannel
    private lateinit var arEventChannel: EventChannel
    private lateinit var arController: FaceArController
    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCameraPermissionResult: Result? = null
    private var pendingAudioPermissionResult: Result? = null
    private lateinit var textureRegistry: TextureRegistry
    private val mainHandler = Handler(Looper.getMainLooper())

    private var cameraProvider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var recording: Recording? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService? = null

    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var previewWidth = 0
    private var previewHeight = 0
    private var cameraTargetRotation = Surface.ROTATION_0
    private var requestedFlashMode = ImageCapture.FLASH_MODE_OFF
    private var recordingStartPending = false
    private var cancelRecordingStart: (() -> Unit)? = null

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1001
        private const val GALLERY_PERMISSION_REQUEST_CODE = 1002
        private const val AUDIO_PERMISSION_REQUEST_CODE = 1003
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "story_editor_pro")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        textureRegistry = flutterPluginBinding.textureRegistry
        ensureCameraExecutor()

        val flutterAssets = flutterPluginBinding.flutterAssets
        val modelAssetPath = resolveFlutterAsset(
            flutterAssets,
            "assets/ar/models/face_landmarker.task",
        )
        arController = FaceArController(context, modelAssetPath, resolveFlutterAsset(
            flutterAssets, "assets/ar/models/selfie_segmenter.tflite",
        ), mapOf(
            2 to resolveFlutterAsset(flutterAssets, "assets/ar/backgrounds/sunset_terrace.png"),
            3 to resolveFlutterAsset(flutterAssets, "assets/ar/backgrounds/night_waterfront.png"),
        ))
        arMethodChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            FaceArContract.METHOD_CHANNEL,
        ).also { it.setMethodCallHandler(arController) }
        arEventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            FaceArContract.EVENT_CHANNEL,
        ).also { it.setStreamHandler(arController) }
    }

    private fun resolveFlutterAsset(
        flutterAssets: FlutterPlugin.FlutterAssets,
        logicalPath: String,
    ): String {
        val candidates = listOf(
            flutterAssets.getAssetFilePathByName(logicalPath, "story_editor_pro"),
            flutterAssets.getAssetFilePathByName(logicalPath),
        ).distinct()
        return candidates.firstOrNull { candidate ->
            try {
                context.assets.open(candidate).use { true }
            } catch (_: Exception) {
                false
            }
        } ?: candidates.first()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "checkPermission" -> checkPermission(result)
            "requestPermission" -> requestPermission(result)
            "checkGalleryPermission" -> checkGalleryPermission(result)
            "requestGalleryPermission" -> requestGalleryPermission(result)
            "checkAudioPermission" -> checkAudioPermission(result)
            "requestAudioPermission" -> requestAudioPermission(result)
            "initializeCamera" -> initializeCamera(call, result)
            "takePicture" -> takePicture(result)
            "switchCamera" -> switchCamera(result)
            "setFlashMode" -> setFlashMode(call, result)
            "setZoomLevel" -> setZoomLevel(call, result)
            "getCameraControls" -> getCameraControls(result)
            "setFocusPoint" -> setFocusPoint(call, result)
            "setExposureOffset" -> setExposureOffset(call, result)
            "getLastGalleryImage" -> getLastGalleryImage(result)
            "startVideoRecording" -> startVideoRecording(call, result)
            "stopVideoRecording" -> stopVideoRecording(result)
            "createBoomerang" -> createBoomerang(call, result)
            "createBoomerangFromFrames" -> createBoomerangFromFrames(call, result)
            "exportVideoWithOverlay" -> exportVideoWithOverlay(call, result)
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }

    private fun createBoomerang(call: MethodCall, result: Result) {
        val inputPath = call.argument<String>("inputPath")
        val outputPath = call.argument<String>("outputPath")
        val loopCount = call.argument<Int>("loopCount") ?: 3
        val fps = call.argument<Int>("fps") ?: 30
        val maxDuration = call.argument<Double>("maxDuration") ?: 2.0

        if (inputPath == null || outputPath == null) {
            result.error("INVALID_ARGS", "inputPath and outputPath are required", null)
            return
        }

        // Background thread'de işle
        cameraExecutor?.execute {
            try {
                val processor = BoomerangProcessor()
                val output = processor.createBoomerang(
                    inputPath = inputPath,
                    outputPath = outputPath,
                    loopCount = loopCount,
                    fps = fps,
                    maxDurationSeconds = maxDuration
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        result.error("BOOMERANG_FAILED", "Failed to create boomerang", null)
                    }
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("BOOMERANG_ERROR", e.message, null)
                }
            }
        }
    }

    private fun createBoomerangFromFrames(call: MethodCall, result: Result) {
        val frameDir = call.argument<String>("frameDir")
        val outputPath = call.argument<String>("outputPath")
        val fps = call.argument<Int>("fps") ?: 30
        val loopCount = call.argument<Int>("loopCount") ?: 3

        if (frameDir == null || outputPath == null) {
            result.error("INVALID_ARGS", "frameDir and outputPath are required", null)
            return
        }

        // Background thread'de işle
        cameraExecutor?.execute {
            try {
                val processor = BoomerangProcessor()
                val output = processor.createBoomerangFromFrames(
                    frameDir = frameDir,
                    outputPath = outputPath,
                    fps = fps,
                    loopCount = loopCount
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        result.error("BOOMERANG_FAILED", "Failed to create boomerang from frames", null)
                    }
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("BOOMERANG_ERROR", e.message, null)
                }
            }
        }
    }

    private fun getLastGalleryImage(result: Result) {
        activity?.runOnUiThread {
            try {
                val projection = arrayOf(
                    android.provider.MediaStore.Images.Media._ID,
                    android.provider.MediaStore.Images.Media.DATA
                )
                val cursor = context.contentResolver.query(
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    null,
                    null,
                    "${android.provider.MediaStore.Images.Media.DATE_ADDED} DESC"
                )
                cursor?.use {
                    if (it.moveToFirst()) {
                        val columnIndex = it.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DATA)
                        val imagePath = it.getString(columnIndex)
                        result.success(imagePath)
                    } else {
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                result.error("GALLERY_ERROR", "Failed to get last image: ${e.message}", null)
            }
        }
    }

    private fun checkPermission(result: Result) {
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
        result.success(hasPermission)
    }

    private fun requestPermission(result: Result) {
        if (
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.CAMERA,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingCameraPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "A camera permission request is already in progress",
                null,
            )
            return
        }
        activity?.let {
            pendingCameraPermissionResult = result
            ActivityCompat.requestPermissions(
                it,
                arrayOf(android.Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST_CODE
            )
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun checkAudioPermission(result: Result) {
        result.success(
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun requestAudioPermission(result: Result) {
        if (
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingAudioPermissionResult != null) {
            result.error(
                "PERMISSION_REQUEST_IN_PROGRESS",
                "A microphone permission request is already in progress",
                null,
            )
            return
        }
        activity?.let {
            pendingAudioPermissionResult = result
            ActivityCompat.requestPermissions(
                it,
                arrayOf(android.Manifest.permission.RECORD_AUDIO),
                AUDIO_PERMISSION_REQUEST_CODE,
            )
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            val pending = pendingCameraPermissionResult ?: return false
            pendingCameraPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults.first() == PackageManager.PERMISSION_GRANTED
            pending.success(granted)
            return true
        }
        if (requestCode != AUDIO_PERMISSION_REQUEST_CODE) return false
        val pending = pendingAudioPermissionResult ?: return false
        pendingAudioPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults.first() == PackageManager.PERMISSION_GRANTED
        pending.success(granted)
        return true
    }

    private fun checkGalleryPermission(result: Result) {
        val hasPermission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.READ_MEDIA_IMAGES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
        result.success(hasPermission)
    }

    private fun requestGalleryPermission(result: Result) {
        activity?.let {
            val permission = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                android.Manifest.permission.READ_MEDIA_IMAGES
            } else {
                android.Manifest.permission.READ_EXTERNAL_STORAGE
            }
            ActivityCompat.requestPermissions(
                it,
                arrayOf(permission),
                GALLERY_PERMISSION_REQUEST_CODE
            )
            result.success(true)
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun initializeCamera(call: MethodCall, result: Result) {
        if (
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.CAMERA,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "CAMERA_PERMISSION_DENIED",
                "Camera permission must be granted before initialization",
                null,
            )
            return
        }
        val facing = call.argument<String>("facing") ?: "back"
        val requestedLensFacing = if (facing == "front") {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        val requestedLens = requestedLensFacing.toCameraLens()
        val currentExecutor = cameraExecutor
        val currentProvider = cameraProvider
        val currentPreview = preview
        if (
            CameraSessionReusePolicy.shouldReuse(
                currentLens = lensFacing.toCameraLens(),
                requestedLens = requestedLens,
                hasCamera = camera != null && currentProvider != null &&
                    currentPreview != null && currentProvider.isBound(currentPreview),
                hasTexture = textureEntry != null,
                hasRequiredUseCases =
                    preview != null && imageCapture != null && videoCapture != null,
                executorRunning = currentExecutor != null &&
                    !currentExecutor.isShutdown && !currentExecutor.isTerminated,
            )
        ) {
            result.success(currentCameraResult())
            return
        }
        lensFacing = requestedLensFacing

        activity?.let { act ->
            val surfaceExecutor = ensureCameraExecutor()
            val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

            cameraProviderFuture.addListener({
                try {
                    cameraProvider = cameraProviderFuture.get()
                    cameraProvider?.unbindAll()
                    imageAnalysis?.clearAnalyzer()
                    imageAnalysis = null
                    textureEntry?.release()
                    textureEntry = textureRegistry.createSurfaceTexture()
                    val surfaceTexture = textureEntry!!.surfaceTexture()

                    val rotation = act.windowManager.defaultDisplay.rotation
                    val targetRotation = when (rotation) {
                        Surface.ROTATION_0 -> Surface.ROTATION_0
                        Surface.ROTATION_90 -> Surface.ROTATION_90
                        Surface.ROTATION_180 -> Surface.ROTATION_180
                        Surface.ROTATION_270 -> Surface.ROTATION_270
                        else -> Surface.ROTATION_0
                    }
                    cameraTargetRotation = targetRotation

                    // Hedef çözünürlük: 1080x1920 (Full HD Portrait)
                    previewWidth = 1080
                    previewHeight = 1920

                    // Preview - YÜKSEK KALİTE için targetResolution belirt
                    preview = Preview.Builder()
                        .setTargetResolution(android.util.Size(1080, 1920))
                        .setTargetRotation(targetRotation)
                        // Flutter owns the optional selfie mirror. CameraX's
                        // front-only default flipped text a second time.
                        .setMirrorMode(MirrorMode.MIRROR_MODE_OFF)
                        .setTargetFrameRate(Range(30, 30))
                        .build()
                        .also {
                            it.setSurfaceProvider { request ->
                                val width = request.resolution.width
                                val height = request.resolution.height

                                surfaceTexture.setDefaultBufferSize(width, height)
                                val surface = Surface(surfaceTexture)
                                request.provideSurface(surface, surfaceExecutor) {
                                    surface.release()
                                }

                                // Preview boyutunu güncelle
                                previewWidth = width
                                previewHeight = height
                            }
                        }

                    // Story capture prioritizes a responsive shutter over Camera2's potentially
                    // unbounded 3A convergence wait used by maximum-quality capture.
                    imageCapture = ImageCapture.Builder()
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                        .setFlashMode(PhotoCapturePolicy.DEFAULT_FLASH_MODE)
                        .setTargetResolution(android.util.Size(1080, 1920))
                        .setTargetRotation(targetRotation)
                        .build()

                    // Video recording - FHD (1080p) kalite
                    val recorder = Recorder.Builder()
                        .setQualitySelector(
                            QualitySelector.fromOrderedList(
                                listOf(Quality.FHD, Quality.HD, Quality.SD),
                                FallbackStrategy.higherQualityOrLowerThan(Quality.FHD)
                            )
                        )
                        .build()
                    videoCapture = VideoCapture.Builder(recorder)
                        .setTargetRotation(targetRotation)
                        .setMirrorMode(MirrorMode.MIRROR_MODE_OFF)
                        .setTargetFrameRate(Range(30, 30))
                        .build()

                    imageAnalysis = arController.createImageAnalysis(targetRotation)

                    camera = bindCameraUseCases(act as LifecycleOwner)

                    result.success(currentCameraResult())
                } catch (e: Exception) {
                    result.error("CAMERA_ERROR", "Failed to initialize camera: ${e.message}", null)
                }
            }, ContextCompat.getMainExecutor(context))
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun currentCameraResult(): Map<String, Any> = hashMapOf(
        "textureId" to requireNotNull(textureEntry).id(),
        "previewWidth" to previewWidth,
        "previewHeight" to previewHeight,
    )

    private fun takePicture(result: Result) {
        val imageCapture = imageCapture ?: run {
            result.error("CAMERA_NOT_INITIALIZED", "Camera not initialized", null)
            return
        }

        val photoFile = File(context.cacheDir, "story_${System.currentTimeMillis()}.jpg")

        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()
        val completion = SingleCompletionGate()
        lateinit var timeoutTask: Runnable

        fun postError(code: String, message: String) {
            mainHandler.post {
                if (completion.tryComplete()) {
                    mainHandler.removeCallbacks(timeoutTask)
                    photoFile.delete()
                    result.error(code, message, null)
                } else {
                    // A timed-out capture may finish writing after the first cleanup attempt.
                    photoFile.delete()
                }
            }
        }

        timeoutTask = Runnable {
            if (completion.tryComplete()) {
                photoFile.delete()
                result.error(
                    "CAPTURE_TIMEOUT",
                    "Photo capture timed out; please try again",
                    null,
                )
            }
        }
        mainHandler.postDelayed(timeoutTask, PhotoCapturePolicy.TIMEOUT_MS)

        try {
            imageCapture.takePicture(
                outputOptions,
                ensureCameraExecutor(),
                object : ImageCapture.OnImageSavedCallback {
                    override fun onError(exc: ImageCaptureException) {
                        postError("CAPTURE_ERROR", "Failed to capture image")
                    }

                    override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                        val correctedPath = correctImageOrientation(photoFile.absolutePath)
                        mainHandler.post {
                            if (completion.tryComplete()) {
                                mainHandler.removeCallbacks(timeoutTask)
                                result.success(correctedPath)
                            } else {
                                // Never leave a late JPEG behind after Dart already received timeout.
                                photoFile.delete()
                            }
                        }
                    }
                },
            )
        } catch (_: Exception) {
            postError("CAPTURE_ERROR", "Unable to start photo capture")
        }
    }

    private fun correctImageOrientation(imagePath: String): String {
        try {
            val exif = ExifInterface(imagePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )

            val bitmap = BitmapFactory.decodeFile(imagePath)
            val matrix = Matrix()

            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            }

            val rotatedBitmap = Bitmap.createBitmap(
                bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true
            )

            FileOutputStream(imagePath).use { out ->
                rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
            }

            bitmap.recycle()
            rotatedBitmap.recycle()

        } catch (e: Exception) {
            e.printStackTrace()
        }
        return imagePath
    }

    private fun switchCamera(result: Result) {
        activity?.let { act ->
            val provider = cameraProvider
            if (provider == null) {
                result.error("CAMERA_NOT_INITIALIZED", "Camera not initialized", null)
                return
            }
            if (recording != null || recordingStartPending) {
                result.error(
                    "RECORDING_ACTIVE",
                    "Camera cannot be switched while recording",
                    null,
                )
                return
            }
            val owner = act as LifecycleOwner
            val previousLensFacing = lensFacing
            val currentLens = previousLensFacing.toCameraLens()
            val targetLens = if (currentLens == CameraLens.BACK) {
                CameraLens.FRONT
            } else {
                CameraLens.BACK
            }
            val targetLensFacing = targetLens.toCameraXLensFacing()
            val targetSelector = CameraSelector.Builder()
                .requireLensFacing(targetLensFacing)
                .build()
            val targetAvailable = try {
                provider.hasCamera(targetSelector)
            } catch (_: Exception) {
                false
            }
            val plan = CameraSwitchPolicy.plan(currentLens, targetAvailable)
            if (!plan.shouldUnbind) {
                result.error(
                    "SWITCH_UNAVAILABLE",
                    "The requested camera is not available",
                    null,
                )
                return
            }
            try {
                provider.unbindAll()
                val switchedCamera = bindCameraUseCases(owner, targetLensFacing)
                    ?: error("Camera use cases are not initialized")
                lensFacing = plan.lensAfter(bindSucceeded = true).toCameraXLensFacing()
                camera = switchedCamera
                result.success(true)
            } catch (_: Exception) {
                lensFacing = plan.lensAfter(bindSucceeded = false).toCameraXLensFacing()
                try {
                    provider.unbindAll()
                    camera = bindCameraUseCases(owner, previousLensFacing)
                } catch (_: Exception) {
                    camera = null
                }
                result.error("SWITCH_ERROR", "Failed to switch camera", null)
            }
        } ?: result.error("NO_ACTIVITY", "Activity not available", null)
    }

    private fun bindCameraUseCases(
        owner: LifecycleOwner,
        requestedLensFacing: Int = lensFacing,
    ): Camera? {
        val localPreview = preview ?: return null
        val localImageCapture = imageCapture ?: return null
        val localVideoCapture = videoCapture ?: return null
        val selector = CameraSelector.Builder()
            .requireLensFacing(requestedLensFacing)
            .build()
        val group = UseCaseGroup.Builder()
            .addUseCase(localPreview)
            .addUseCase(localImageCapture)
            .addUseCase(localVideoCapture)
            .setViewPort(
                ViewPort.Builder(
                    // SurfaceRequest dimensions are sensor/buffer dimensions.
                    // They may be landscape even with a portrait target. Never
                    // feed them back into the viewport when switching cameras.
                    if (CameraViewportPolicy.isLandscape(cameraTargetRotation))
                        Rational(16, 9) else Rational(9, 16),
                    cameraTargetRotation,
                ).setScaleType(ViewPort.FILL_CENTER).build(),
            )
        imageAnalysis?.let { group.addUseCase(it) }
        arController.cameraEffectOrNull()?.let { group.addEffect(it) }
        arController.onCameraRebound()
        return cameraProvider?.bindToLifecycle(owner, selector, group.build())?.also {
            if (!it.cameraInfo.hasFlashUnit()) requestedFlashMode = ImageCapture.FLASH_MODE_OFF
            localImageCapture.flashMode = requestedFlashMode
        }
    }

    private fun Int.toCameraLens(): CameraLens =
        if (this == CameraSelector.LENS_FACING_FRONT) CameraLens.FRONT else CameraLens.BACK

    private fun CameraLens.toCameraXLensFacing(): Int =
        if (this == CameraLens.FRONT) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }

    private fun getCameraControls(result: Result) {
        val localCamera = camera ?: return result.error("NOT_INITIALIZED", "Camera is not initialized", null)
        val info = localCamera.cameraInfo
        val zoom = info.zoomState.value
        val exposure = info.exposureState
        val step = exposure.exposureCompensationStep.toDouble()
        val exposureSupported = exposure.isExposureCompensationSupported && step > 0.0
        val point = SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(.5f, .5f)
        val focus = info.isFocusMeteringSupported(FocusMeteringAction.Builder(point).build())
        result.success(mapOf(
            "minZoom" to (zoom?.minZoomRatio?.toDouble() ?: 1.0),
            "maxZoom" to (zoom?.maxZoomRatio?.toDouble() ?: 1.0),
            "minExposure" to if (exposureSupported) exposure.exposureCompensationRange.lower * step else 0.0,
            "maxExposure" to if (exposureSupported) exposure.exposureCompensationRange.upper * step else 0.0,
            "exposureStep" to if (exposureSupported) step else 0.0,
            "focus" to focus,
            "exposure" to exposureSupported,
            "torch" to info.hasFlashUnit(),
        ))
    }

    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun setFocusPoint(call: MethodCall, result: Result) {
        val localCamera = camera ?: return result.error("NOT_INITIALIZED", "Camera is not initialized", null)
        val x = call.argument<Number>("x")?.toDouble()
        val y = call.argument<Number>("y")?.toDouble()
        if (x == null || y == null || !x.isFinite() || !y.isFinite()) {
            result.error("INVALID_ARGS", "A finite focus point is required", null); return
        }
        val frame = arController.meteringFrame ?: run {
            result.error("CAMERA_NOT_READY", "Wait for the camera preview before focusing", null); return
        }
        val active = Camera2CameraInfo.from(localCamera.cameraInfo)
            .getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            ?: run { result.success(false); return }
        try {
            val sensor = CameraSensorBounds(active.left.toFloat(), active.top.toFloat(), active.width().toFloat(), active.height().toFloat())
            val normalized = CameraControlPolicy.focusPoint(x, y, frame, sensor)
            val factory = object : MeteringPointFactory(Rational(active.width(), active.height())) {
                override fun convertPoint(x: Float, y: Float): PointF = PointF(x, y)
            }
            val point = factory.createPoint(normalized.first, normalized.second, .12f)
            val action = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                .setAutoCancelDuration(4, TimeUnit.SECONDS).build()
            if (!localCamera.cameraInfo.isFocusMeteringSupported(action)) { result.success(false); return }
            completeCameraOperation(localCamera.cameraControl.startFocusAndMetering(action), result, "FOCUS_FAILED")
        } catch (_: IllegalArgumentException) {
            result.error("FOCUS_FAILED", "Could not map the focus point", null)
        }
    }

    private fun setExposureOffset(call: MethodCall, result: Result) {
        val localCamera = camera ?: return result.error("NOT_INITIALIZED", "Camera is not initialized", null)
        val value = call.argument<Number>("value")?.toDouble()
        if (value == null || !value.isFinite()) { result.error("INVALID_ARGS", "A finite exposure value is required", null); return }
        val state = localCamera.cameraInfo.exposureState
        val step = state.exposureCompensationStep.toDouble()
        if (!state.isExposureCompensationSupported || step <= 0.0) { result.success(false); return }
        val index = CameraControlPolicy.exposureIndex(value, step,
            state.exposureCompensationRange.lower, state.exposureCompensationRange.upper)
        completeCameraOperation(localCamera.cameraControl.setExposureCompensationIndex(index), result, "EXPOSURE_FAILED")
    }

    private fun setFlashMode(call: MethodCall, result: Result) {
        val localCamera = camera ?: return result.error("NOT_INITIALIZED", "Camera is not initialized", null)
        val mode = when (call.argument<String>("mode")) {
            "on" -> ImageCapture.FLASH_MODE_ON
            "auto" -> ImageCapture.FLASH_MODE_AUTO
            "off" -> ImageCapture.FLASH_MODE_OFF
            else -> { result.error("INVALID_ARGS", "Unsupported flash mode", null); return }
        }
        if (mode != ImageCapture.FLASH_MODE_OFF && !localCamera.cameraInfo.hasFlashUnit()) {
            result.success(false); return
        }
        requestedFlashMode = mode
        imageCapture?.flashMode = mode
        if (recording != null || recordingStartPending) {
            completeCameraOperation(localCamera.cameraControl.enableTorch(mode == ImageCapture.FLASH_MODE_ON), result, "TORCH_FAILED")
        } else result.success(true)
    }

    private fun setZoomLevel(call: MethodCall, result: Result) {
        val localCamera = camera ?: return result.error("NOT_INITIALIZED", "Camera is not initialized", null)
        val level = call.argument<Number>("level")?.toDouble()
        if (level == null || !level.isFinite()) { result.error("INVALID_ARGS", "A finite zoom value is required", null); return }
        val state = localCamera.cameraInfo.zoomState.value ?: run { result.success(false); return }
        val zoom = CameraControlPolicy.zoom(level, state.minZoomRatio, state.maxZoomRatio)
        completeCameraOperation(localCamera.cameraControl.setZoomRatio(zoom), result, "ZOOM_FAILED")
    }

    private fun <T> completeCameraOperation(future: ListenableFuture<T>, result: Result, code: String) {
        future.addListener({
            try { future.get(); result.success(true) }
            catch (_: Exception) { result.error(code, "The camera could not apply this control", null) }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun turnOffRecordingTorch(localCamera: Camera? = camera) {
        if (localCamera?.cameraInfo?.hasFlashUnit() != true) return
        try { localCamera.cameraControl.enableTorch(false) } catch (_: Exception) { }
    }

    private fun exportVideoWithOverlay(call: MethodCall, result: Result) {
        val videoPath = call.argument<String>("videoPath")
        val overlayImagePath = call.argument<String>("overlayImagePath")
        val outputPath = call.argument<String>("outputPath")
        val mirrorHorizontally = call.argument<Boolean>("mirrorHorizontally") ?: false
        val outputWidth = call.argument<Int>("outputWidth")
        val outputHeight = call.argument<Int>("outputHeight")
        val filterPreset = call.argument<String>("filterPreset") ?: "none"
        val filterStrength = call.argument<Double>("filterStrength") ?: 1.0
        val beautyStrength = call.argument<Double>("beautyStrength") ?: 0.0
        val beautyEyes = call.argument<Number>("beautyEyes")?.toDouble() ?: 0.0
        val beautySlim = call.argument<Number>("beautySlim")?.toDouble() ?: 0.0
        val faceTimeline = call.argument<List<Map<String, Any?>>>("faceTimeline") ?: emptyList()
        val mediaScale = call.argument<Number>("mediaScale")?.toDouble() ?: 1.0
        val mediaOffsetX = call.argument<Number>("mediaOffsetX")?.toDouble() ?: 0.0
        val mediaOffsetY = call.argument<Number>("mediaOffsetY")?.toDouble() ?: 0.0
        val shouldMuteAudio = call.argument<Boolean>("shouldMuteAudio") ?: false
        val trimStartMs = call.argument<Number>("trimStartMs")?.toLong() ?: 0L
        val trimEndMs = call.argument<Number>("trimEndMs")?.toLong() ?: 0L
        val animatedStickers =
            call.argument<List<Map<String, Any?>>>("animatedStickers") ?: emptyList()

        if (videoPath == null || overlayImagePath == null || outputPath == null) {
            result.error("INVALID_ARGS",
                "videoPath, overlayImagePath and outputPath are required", null)
            return
        }
        if (trimStartMs < 0L || trimEndMs < 0L ||
            (trimEndMs > 0L && trimEndMs <= trimStartMs)) {
            result.error("INVALID_TRIM", "The video trim range is invalid", null)
            return
        }
        if (!mediaScale.isFinite() || !mediaOffsetX.isFinite() || !mediaOffsetY.isFinite()) {
            result.error("INVALID_TRANSFORM", "The media transform must be finite", null)
            return
        }

        // Use a dedicated thread (cameraExecutor may be null if camera is disposed)
        Thread {
            try {
                val processor = VideoOverlayProcessor()
                val output = processor.exportVideoWithOverlay(
                    videoPath = videoPath,
                    overlayImagePath = overlayImagePath,
                    outputPath = outputPath,
                    animatedStickers = animatedStickers,
                    mirrorHorizontally = mirrorHorizontally,
                    outputWidth = outputWidth,
                    outputHeight = outputHeight,
                    filterPreset = filterPreset,
                    filterStrength = filterStrength,
                    beautyStrength = beautyStrength,
                    beautyEyes = beautyEyes,
                    beautySlim = beautySlim,
                    faceTimeline = faceTimeline,
                    mediaScale = mediaScale,
                    mediaOffsetX = mediaOffsetX,
                    mediaOffsetY = mediaOffsetY,
                    shouldMuteAudio = shouldMuteAudio,
                    trimStartMs = trimStartMs,
                    trimEndMs = trimEndMs
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        result.error("EXPORT_FAILED",
                            processor.lastError ?: "Failed to export video with overlay",
                            mapOf("processorError" to processor.lastError))
                    }
                }
            } catch (e: Exception) {
                activity?.runOnUiThread {
                    result.error("EXPORT_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private var videoResultCallback: Result? = null
    private var currentVideoPath: String? = null

    @androidx.annotation.OptIn(androidx.camera.video.ExperimentalPersistentRecording::class)
    private fun startVideoRecording(call: MethodCall, result: Result) {
        val outputPath = call.argument<String>("outputPath")
        if (outputPath == null) {
            result.error("INVALID_ARGS", "Output path required", null)
            return
        }

        val localVideoCapture = videoCapture
        val localCamera = camera
        if (localVideoCapture == null || localCamera == null) {
            result.error("NOT_INITIALIZED", "Video capture not initialized", null)
            return
        }

        if (recording != null || recordingStartPending) {
            result.error("ALREADY_RECORDING", "Already recording", null)
            return
        }

        if (
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.RECORD_AUDIO,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "AUDIO_PERMISSION_REQUIRED",
                "Microphone permission is required before video recording",
                null,
            )
            return
        }

        currentVideoPath = outputPath
        val outputFile = File(outputPath)
        val outputOptions = FileOutputOptions.Builder(outputFile).build()
        val startCompletion = SingleCompletionGate()
        var startCancelled = false
        recordingStartPending = true
        fun failStart(code: String, message: String) {
            if (startCompletion.tryComplete()) {
                startCancelled = true
                recordingStartPending = false
                cancelRecordingStart = null
                turnOffRecordingTorch(localCamera)
                result.error(code, message, null)
            }
        }
        cancelRecordingStart = { failStart("RECORDING_CANCELLED", "Recording start was cancelled") }

        fun beginRecording() {
          if (startCancelled || !recordingStartPending || camera !== localCamera) return
          try {
            recording = localVideoCapture.output
                .prepareRecording(context, outputOptions)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(context)) { event ->
                    when (event) {
                        is VideoRecordEvent.Start -> {
                            // PendingRecording submission can precede encoder
                            // and audio readiness by hundreds of milliseconds.
                            // Align Flutter's pose timeline to the actual
                            // recorder start and expose the same native clock.
                            if (startCompletion.tryComplete()) {
                                arController.onRecordingStarted(SystemClock.elapsedRealtime())
                                recordingStartPending = false
                                cancelRecordingStart = null
                                result.success(true)
                            }
                        }
                        is VideoRecordEvent.Finalize -> {
                            turnOffRecordingTorch(localCamera)
                            failStart("RECORDING_ERROR", "Video recording could not start")
                            if (event.hasError()) {
                                videoResultCallback?.error(
                                    "RECORDING_ERROR",
                                    "Recording failed",
                                    null,
                                )
                            } else {
                                videoResultCallback?.success(currentVideoPath)
                            }
                            videoResultCallback = null
                            recording = null
                        }
                    }
                }
          } catch (_: SecurityException) {
            recording = null
            failStart(
                "AUDIO_PERMISSION_REQUIRED",
                "Microphone permission is required before video recording",
            )
          } catch (_: Exception) {
            recording = null
            failStart("RECORDING_ERROR", "Unable to start video recording")
          }
        }
        if (requestedFlashMode == ImageCapture.FLASH_MODE_ON && localCamera.cameraInfo.hasFlashUnit()) {
            try {
                val torch = localCamera.cameraControl.enableTorch(true)
                torch.addListener({
                    try { torch.get(); beginRecording() }
                    catch (_: Exception) { failStart("TORCH_FAILED", "Could not enable the recording light") }
                }, ContextCompat.getMainExecutor(context))
            } catch (_: Exception) {
                failStart("TORCH_FAILED", "Could not enable the recording light")
            }
        } else {
            beginRecording()
        }
    }

    private fun stopVideoRecording(result: Result) {
        turnOffRecordingTorch()
        if (recording == null) {
            cancelRecordingStart?.invoke()
            result.error("NOT_RECORDING", "Not recording", null)
            return
        }

        videoResultCallback = result
        recording?.stop()
    }

    private fun dispose(result: Result) {
        cancelRecordingStart?.invoke()
        turnOffRecordingTorch()
        recording?.stop()
        recording = null
        cameraProvider?.unbindAll()
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
        textureEntry?.release()
        textureEntry = null
        cameraExecutor?.shutdown()
        cameraExecutor = null
        preview = null
        imageCapture = null
        videoCapture = null
        camera = null
        result.success(true)
    }

    private fun ensureCameraExecutor(): ExecutorService {
        val current = cameraExecutor
        if (current != null && !current.isShutdown && !current.isTerminated) return current
        return Executors.newSingleThreadExecutor().also { cameraExecutor = it }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cancelRecordingStart?.invoke()
        turnOffRecordingTorch()
        recording?.stop()
        recording = null
        channel.setMethodCallHandler(null)
        arMethodChannel.setMethodCallHandler(null)
        arEventChannel.setStreamHandler(null)
        cameraProvider?.unbindAll()
        imageAnalysis?.clearAnalyzer()
        imageAnalysis = null
        textureEntry?.release()
        textureEntry = null
        cameraExecutor?.shutdown()
        cameraExecutor = null
        pendingAudioPermissionResult?.error(
            "PLUGIN_DETACHED",
            "Plugin detached while microphone permission was pending",
            null,
        )
        pendingAudioPermissionResult = null
        pendingCameraPermissionResult?.error(
            "PLUGIN_DETACHED",
            "Plugin detached while camera permission was pending",
            null,
        )
        pendingCameraPermissionResult = null
        arController.close()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        pendingCameraPermissionResult?.error(
            "NO_ACTIVITY",
            "Activity detached while camera permission was pending",
            null,
        )
        pendingCameraPermissionResult = null
        pendingAudioPermissionResult?.error(
            "NO_ACTIVITY",
            "Activity detached while microphone permission was pending",
            null,
        )
        pendingAudioPermissionResult = null
    }
}
