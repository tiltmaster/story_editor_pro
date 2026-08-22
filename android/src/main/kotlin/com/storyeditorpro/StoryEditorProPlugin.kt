package com.storyeditorpro

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.Surface
import androidx.camera.core.*
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
        val meshAssetPath = resolveFlutterAsset(
            flutterAssets,
            "assets/ar/glasses_classic/runtime_mesh.json",
        )
        arController = FaceArController(context, modelAssetPath, meshAssetPath)
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
        activity?.let {
            ActivityCompat.requestPermissions(
                it,
                arrayOf(android.Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST_CODE
            )
            result.success(true)
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
                    videoCapture = VideoCapture.withOutput(recorder)

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

            if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
                matrix.preScale(-1f, 1f)
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
            if (recording != null) {
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
                    Rational(previewWidth.coerceAtLeast(1), previewHeight.coerceAtLeast(1)),
                    cameraTargetRotation,
                ).setScaleType(ViewPort.FILL_CENTER).build(),
            )
        imageAnalysis?.let { group.addUseCase(it) }
        arController.cameraEffectOrNull()?.let { group.addEffect(it) }
        return cameraProvider?.bindToLifecycle(owner, selector, group.build())
    }

    private fun Int.toCameraLens(): CameraLens =
        if (this == CameraSelector.LENS_FACING_FRONT) CameraLens.FRONT else CameraLens.BACK

    private fun CameraLens.toCameraXLensFacing(): Int =
        if (this == CameraLens.FRONT) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }

    private fun setFlashMode(call: MethodCall, result: Result) {
        val mode = call.argument<String>("mode") ?: "off"
        val flashMode = when (mode) {
            "on" -> ImageCapture.FLASH_MODE_ON
            "auto" -> ImageCapture.FLASH_MODE_AUTO
            else -> ImageCapture.FLASH_MODE_OFF
        }
        imageCapture?.flashMode = flashMode
        result.success(true)
    }

    private fun setZoomLevel(call: MethodCall, result: Result) {
        val level = call.argument<Double>("level") ?: 1.0
        camera?.cameraControl?.setZoomRatio(level.toFloat())
        result.success(true)
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
        val shouldMuteAudio = call.argument<Boolean>("shouldMuteAudio") ?: false
        val animatedStickers =
            call.argument<List<Map<String, Any?>>>("animatedStickers") ?: emptyList()

        if (videoPath == null || overlayImagePath == null || outputPath == null) {
            result.error("INVALID_ARGS",
                "videoPath, overlayImagePath and outputPath are required", null)
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
                    shouldMuteAudio = shouldMuteAudio
                )

                activity?.runOnUiThread {
                    if (output != null) {
                        result.success(output)
                    } else {
                        val details = mapOf(
                            "videoPath" to videoPath,
                            "overlayImagePath" to overlayImagePath,
                            "outputPath" to outputPath,
                            "processorError" to processor.lastError
                        )
                        result.error("EXPORT_FAILED",
                            processor.lastError ?: "Failed to export video with overlay",
                            details)
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

        if (videoCapture == null) {
            result.error("NOT_INITIALIZED", "Video capture not initialized", null)
            return
        }

        if (recording != null) {
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

        try {
            recording = videoCapture!!.output
                .prepareRecording(context, outputOptions)
                .withAudioEnabled()
                .start(ContextCompat.getMainExecutor(context)) { event ->
                    when (event) {
                        is VideoRecordEvent.Start -> Unit
                        is VideoRecordEvent.Finalize -> {
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
            result.success(true)
        } catch (_: SecurityException) {
            recording = null
            result.error(
                "AUDIO_PERMISSION_REQUIRED",
                "Microphone permission is required before video recording",
                null,
            )
        } catch (_: IllegalStateException) {
            recording = null
            result.error("RECORDING_ERROR", "Unable to start video recording", null)
        }
    }

    private fun stopVideoRecording(result: Result) {
        if (recording == null) {
            result.error("NOT_RECORDING", "Not recording", null)
            return
        }

        videoResultCallback = result
        recording?.stop()
    }

    private fun dispose(result: Result) {
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
        pendingAudioPermissionResult?.error(
            "NO_ACTIVITY",
            "Activity detached while microphone permission was pending",
            null,
        )
        pendingAudioPermissionResult = null
    }
}
