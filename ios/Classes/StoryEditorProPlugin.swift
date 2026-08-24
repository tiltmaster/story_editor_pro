import Flutter
import UIKit
import AVFoundation
import Photos

struct NativeCameraSessionReuseContract {
    static func shouldReuse(isActive: Bool, existingFacing: String, requestedFacing: String) -> Bool {
        isActive && existingFacing == requestedFacing
    }
}

public class StoryEditorProPlugin: NSObject, FlutterPlugin {
    private var registrar: FlutterPluginRegistrar?
    private var textureRegistry: FlutterTextureRegistry?
    private var cameraManager: CameraManager?
    private var faceARCoordinator: FaceARCoordinator?
    private var faceARMethodHandler: FaceARMethodHandler?
    private var faceAREventHandler: FaceAREventStreamHandler?
    private var pendingCameraInitializations: [(facing: String, result: FlutterResult)] = []
    private var isProcessingCameraInitialization = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "story_editor_pro", binaryMessenger: registrar.messenger())
        let arChannel = FlutterMethodChannel(name: "story_editor_pro/ar", binaryMessenger: registrar.messenger())
        let arEvents = FlutterEventChannel(name: "story_editor_pro/ar_events", binaryMessenger: registrar.messenger())
        let instance = StoryEditorProPlugin()
        instance.registrar = registrar
        instance.textureRegistry = registrar.textures()
        func bundledAssetPath(_ asset: String) -> String? {
            let packageKey = registrar.lookupKey(forAsset: asset, fromPackage: "story_editor_pro")
            if let path = Bundle.main.path(forResource: packageKey, ofType: nil) { return path }
            let applicationKey = registrar.lookupKey(forAsset: asset)
            return Bundle.main.path(forResource: applicationKey, ofType: nil)
        }
        let coordinator = FaceARCoordinator(
            modelPath: bundledAssetPath("assets/ar/models/face_landmarker.task"),
            meshPaths: [
                "glasses_classic": bundledAssetPath("assets/ar/glasses_classic/runtime_mesh.json"),
                "glasses_aviator_gold": bundledAssetPath("assets/ar/glasses_aviator_gold/runtime_mesh.json"),
                "glasses_visor_cyan": bundledAssetPath("assets/ar/glasses_visor_cyan/runtime_mesh.json")
            ].compactMapValues { $0 }
        )
        let arHandler = FaceARMethodHandler(coordinator: coordinator)
        let eventHandler = FaceAREventStreamHandler(coordinator: coordinator)
        instance.faceARCoordinator = coordinator
        instance.faceARMethodHandler = arHandler
        instance.faceAREventHandler = eventHandler
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addMethodCallDelegate(arHandler, channel: arChannel)
        arEvents.setStreamHandler(eventHandler)
    }

    private var boomerangProcessor: BoomerangProcessor?
    private var videoOverlayProcessor: VideoOverlayProcessor?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkPermission":
            checkPermission(result: result)
        case "requestPermission":
            requestPermission(result: result)
        case "checkGalleryPermission":
            checkGalleryPermission(result: result)
        case "requestGalleryPermission":
            requestGalleryPermission(result: result)
        case "initializeCamera":
            let args = call.arguments as? [String: Any]
            let facing = args?["facing"] as? String ?? "back"
            initializeCamera(facing: facing, result: result)
        case "takePicture":
            takePicture(result: result)
        case "startVideoRecording":
            startVideoRecording(call: call, result: result)
        case "stopVideoRecording":
            stopVideoRecording(result: result)
        case "switchCamera":
            switchCamera(result: result)
        case "setFlashMode":
            let args = call.arguments as? [String: Any]
            let mode = args?["mode"] as? String ?? "off"
            setFlashMode(mode: mode, result: result)
        case "setZoomLevel":
            let args = call.arguments as? [String: Any]
            let level = args?["level"] as? Double ?? 1.0
            setZoomLevel(level: level, result: result)
        case "getLastGalleryImage":
            getLastGalleryImage(result: result)
        case "createBoomerang":
            createBoomerang(call: call, result: result)
        case "createBoomerangFromFrames":
            createBoomerangFromFrames(call: call, result: result)
        case "exportVideoWithOverlay":
            exportVideoWithOverlay(call: call, result: result)
        case "dispose":
            dispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func exportVideoWithOverlay(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let overlayImagePath = args["overlayImagePath"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS",
                   message: "videoPath, overlayImagePath and outputPath are required",
                   details: nil))
            return
        }
        let mirrorHorizontally = args["mirrorHorizontally"] as? Bool ?? false
        let outputWidth = args["outputWidth"] as? Int
        let outputHeight = args["outputHeight"] as? Int
        let filterPreset = args["filterPreset"] as? String ?? "none"
        let filterStrength = args["filterStrength"] as? Double ?? 1.0
        let shouldMuteAudio = args["shouldMuteAudio"] as? Bool ?? false
        let animatedStickers = args["animatedStickers"] as? [[String: Any]] ?? []

        if videoOverlayProcessor == nil {
            videoOverlayProcessor = VideoOverlayProcessor()
        }

        videoOverlayProcessor?.exportVideoWithOverlay(
            videoPath: videoPath,
            overlayImagePath: overlayImagePath,
            outputPath: outputPath,
            animatedStickers: animatedStickers,
            mirrorHorizontally: mirrorHorizontally,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            filterPreset: filterPreset,
            filterStrength: filterStrength,
            shouldMuteAudio: shouldMuteAudio
        ) { output, errorMessage in
            if let output = output {
                result(output)
            } else {
                result(FlutterError(code: "EXPORT_FAILED",
                       message: errorMessage ?? "Failed to export video with overlay",
                       details: [
                            "videoPath": videoPath,
                            "overlayImagePath": overlayImagePath,
                            "outputPath": outputPath,
                            "nativeError": errorMessage ?? "unknown"
                       ]))
            }
        }
    }

    private func createBoomerang(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let inputPath = args["inputPath"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "inputPath and outputPath are required", details: nil))
            return
        }

        let loopCount = args["loopCount"] as? Int ?? 3
        let fps = args["fps"] as? Int ?? 30
        let maxDuration = args["maxDuration"] as? Double ?? 2.0

        if boomerangProcessor == nil {
            boomerangProcessor = BoomerangProcessor()
        }

        boomerangProcessor?.createBoomerang(
            inputPath: inputPath,
            outputPath: outputPath,
            loopCount: loopCount,
            fps: fps,
            maxDurationSeconds: maxDuration
        ) { output in
            if let output = output {
                result(output)
            } else {
                result(FlutterError(code: "BOOMERANG_FAILED", message: "Failed to create boomerang", details: nil))
            }
        }
    }

    private func createBoomerangFromFrames(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let frameDir = args["frameDir"] as? String,
              let outputPath = args["outputPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "frameDir and outputPath are required", details: nil))
            return
        }

        let fps = args["fps"] as? Int ?? 30
        let loopCount = args["loopCount"] as? Int ?? 3

        if boomerangProcessor == nil {
            boomerangProcessor = BoomerangProcessor()
        }

        boomerangProcessor?.createBoomerangFromFrames(
            frameDir: frameDir,
            outputPath: outputPath,
            fps: fps,
            loopCount: loopCount
        ) { output in
            if let output = output {
                result(output)
            } else {
                result(FlutterError(code: "BOOMERANG_FAILED", message: "Failed to create boomerang from frames", details: nil))
            }
        }
    }

    private func getLastGalleryImage(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

            guard let asset = fetchResult.firstObject else {
                DispatchQueue.main.async {
                    result(nil)
                }
                return
            }

            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat

            manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, options: options) { image, _ in
                guard let image = image, let data = image.jpegData(compressionQuality: 0.8) else {
                    DispatchQueue.main.async {
                        result(nil)
                    }
                    return
                }

                let tempDir = NSTemporaryDirectory()
                let fileName = "last_gallery_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
                let filePath = (tempDir as NSString).appendingPathComponent(fileName)

                do {
                    try data.write(to: URL(fileURLWithPath: filePath))
                    DispatchQueue.main.async {
                        result(filePath)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "GALLERY_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }

    private func checkPermission(result: @escaping FlutterResult) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        result(status == .authorized)
    }

    private func requestPermission(result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                result(granted)
            }
        }
    }

    private func checkGalleryPermission(result: @escaping FlutterResult) {
        let status = PHPhotoLibrary.authorizationStatus()
        result(isGalleryPermissionGranted(status))
    }

    private func requestGalleryPermission(result: @escaping FlutterResult) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                result(self.isGalleryPermissionGranted(status))
            }
        }
    }

    private func isGalleryPermissionGranted(_ status: PHAuthorizationStatus) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 14, *), status == .limited { return true }
        return false
    }

    private func initializeCamera(facing: String, result: @escaping FlutterResult) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            result(FlutterError(
                code: "CAMERA_PERMISSION_DENIED",
                message: "Camera permission must be granted before initialization",
                details: nil
            ))
            return
        }
        guard let textureRegistry = textureRegistry else {
            result(FlutterError(code: "NO_TEXTURE_REGISTRY", message: "Texture registry not available", details: nil))
            return
        }

        pendingCameraInitializations.append((facing, result))
        processNextCameraInitialization(textureRegistry: textureRegistry)
    }

    /// Flutter method calls can overlap while a previous asynchronous camera
    /// setup is still running. Serializing them here prevents two different-
    /// facing requests from tearing down and replacing the same session twice.
    private func processNextCameraInitialization(textureRegistry: FlutterTextureRegistry) {
        guard !isProcessingCameraInitialization,
              !pendingCameraInitializations.isEmpty else { return }
        isProcessingCameraInitialization = true
        let request = pendingCameraInitializations.removeFirst()
        let result = request.result

        let position: AVCaptureDevice.Position = request.facing == "front" ? .front : .back

        let finish: (Any?) -> Void = { [weak self] value in
            result(value)
            guard let self = self else { return }
            self.isProcessingCameraInitialization = false
            self.processNextCameraInitialization(textureRegistry: textureRegistry)
        }

        let startSingleSession = { [weak self] in
            guard let self = self else { return }
            let manager = CameraManager(
                textureRegistry: textureRegistry,
                position: position,
                faceARCoordinator: self.faceARCoordinator
            )
            self.cameraManager = manager
            manager.initialize { textureId, width, height, error in
                DispatchQueue.main.async {
                    if let error = error {
                        finish(FlutterError(code: "CAMERA_ERROR", message: error.localizedDescription, details: nil))
                    } else {
                        finish([
                            "textureId": textureId,
                            "previewWidth": width,
                            "previewHeight": height
                        ])
                    }
                }
            }
        }
        // A prewarmed same-facing native session is adopted directly, avoiding
        // a black preview handoff. Inactive or different-facing sessions still
        // serialize teardown before replacement.
        if let previous = cameraManager {
            previous.reusableDescriptor(for: position) { [weak self] descriptor in
                if let descriptor = descriptor {
                    finish([
                        "textureId": descriptor.textureId,
                        "previewWidth": descriptor.width,
                        "previewHeight": descriptor.height
                    ])
                    return
                }
                guard let self = self else { return }
                guard self.cameraManager === previous else {
                    finish(FlutterError(code: "CAMERA_INITIALIZATION_SUPERSEDED",
                                        message: "Camera lifecycle changed during initialization",
                                        details: nil))
                    return
                }
                self.cameraManager = nil
                previous.dispose(completion: startSingleSession)
            }
        } else {
            startSingleSession()
        }
    }

    private func takePicture(result: @escaping FlutterResult) {
        guard let cameraManager = cameraManager else {
            result(FlutterError(code: "CAMERA_NOT_INITIALIZED", message: "Initialize the native camera before taking a picture", details: nil))
            return
        }
        cameraManager.takePicture { path, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "CAPTURE_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(path)
                }
            }
        }
    }

    private func startVideoRecording(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let requestedPath = (call.arguments as? [String: Any])?["outputPath"] as? String
        guard let cameraManager = cameraManager else {
            result(FlutterError(code: "CAMERA_NOT_INITIALIZED", message: "Initialize the native camera before recording", details: nil))
            return
        }
        cameraManager.startVideoRecording(outputPath: requestedPath) { error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "RECORDING_START_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(true)
                }
            }
        }
    }

    private func stopVideoRecording(result: @escaping FlutterResult) {
        guard let cameraManager = cameraManager else {
            result(FlutterError(code: "CAMERA_NOT_INITIALIZED", message: "Initialize the native camera before recording", details: nil))
            return
        }
        cameraManager.stopVideoRecording { path, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "RECORDING_STOP_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(path)
                }
            }
        }
    }

    private func switchCamera(result: @escaping FlutterResult) {
        guard let cameraManager = cameraManager else {
            result(FlutterError(code: "CAMERA_NOT_INITIALIZED", message: "Initialize the native camera before switching cameras", details: nil))
            return
        }
        cameraManager.switchCamera { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "SWITCH_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(success)
                }
            }
        }
    }

    private func setFlashMode(mode: String, result: @escaping FlutterResult) {
        cameraManager?.setFlashMode(mode: mode)
        result(true)
    }

    private func setZoomLevel(level: Double, result: @escaping FlutterResult) {
        cameraManager?.setZoomLevel(level: CGFloat(level))
        result(true)
    }

    private func dispose(result: @escaping FlutterResult) {
        guard let manager = cameraManager else { result(true); return }
        cameraManager = nil
        manager.dispose { result(true) }
    }
}

class CameraManager: NSObject {
    struct TextureDescriptor {
        let textureId: Int64
        let width: Int
        let height: Int
    }

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private var currentPosition: AVCaptureDevice.Position

    private var textureRegistry: FlutterTextureRegistry
    private var textureId: Int64 = -1
    private var previewWidth = 0
    private var previewHeight = 0
    private var pixelBuffer: CVPixelBuffer?
    private var latestPixelBuffer: CVPixelBuffer?
    private let pixelBufferLock = NSLock()
    private let faceARCoordinator: FaceARCoordinator?
    private let videoRecorder = FaceARVideoRecorder()
    private let audioStateLock = NSLock()
    private var microphoneReady = false

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var photoCompletionHandler: ((String?, Error?) -> Void)?

    init(
        textureRegistry: FlutterTextureRegistry,
        position: AVCaptureDevice.Position,
        faceARCoordinator: FaceARCoordinator?
    ) {
        self.textureRegistry = textureRegistry
        self.currentPosition = position
        self.faceARCoordinator = faceARCoordinator
        super.init()
    }

    func initialize(completion: @escaping (Int64, Int, Int, Error?) -> Void) {
        sessionQueue.async { [weak self] in
            self?.setupCamera(completion: completion)
        }
    }

    private func setupCamera(completion: @escaping (Int64, Int, Int, Error?) -> Void) {
        captureSession = AVCaptureSession()

        // YÜKSEK KALİTE: 1080p Full HD preset
        if captureSession?.canSetSessionPreset(.hd1920x1080) == true {
            captureSession?.sessionPreset = .hd1920x1080
        } else if captureSession?.canSetSessionPreset(.high) == true {
            captureSession?.sessionPreset = .high
        } else {
            captureSession?.sessionPreset = .photo
        }

        guard let device = getCamera(for: currentPosition) else {
            completion(-1, 0, 0, NSError(domain: "CameraManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera not available"]))
            return
        }

        currentDevice = device

        // Kamera cihazını 1080p için optimize et
        configureCameraForHighQuality(device: device)

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }

            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1080,
                kCVPixelBufferHeightKey as String: 1920
            ]
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.video.queue"))
            // Latency matters more than queueing stale frames. Recording uses
            // the same real-time processed stream and therefore stays aligned.
            videoOutput?.alwaysDiscardsLateVideoFrames = true

            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }

            photoOutput = AVCapturePhotoOutput()
            // Yüksek çözünürlüklü fotoğraf yakala
            photoOutput?.isHighResolutionCaptureEnabled = true
            if captureSession?.canAddOutput(photoOutput!) == true {
                captureSession?.addOutput(photoOutput!)
            }

            configureMicrophoneIfAuthorized()

            if let connection = videoOutput?.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    // Keep the native frame graph and saved media unmirrored.
                    // Flutter mirrors only the visible front-camera texture,
                    // so tracking and the rendered lens share one coordinate space.
                    connection.isVideoMirrored = false
                }
            }

            textureId = textureRegistry.register(self)

            captureSession?.startRunning()

            let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            previewWidth = Int(dimensions.width)
            previewHeight = Int(dimensions.height)
            completion(textureId, previewWidth, previewHeight, nil)

        } catch {
            completion(-1, 0, 0, error)
        }
    }

    // Kamerayı yüksek kalite için yapılandır
    private func configureCameraForHighQuality(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // En iyi 1080p formatını bul
            let targetWidth: Int32 = 1920
            let targetHeight: Int32 = 1080

            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?

            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

                // 1080p veya daha yüksek çözünürlük
                if dimensions.width >= targetWidth && dimensions.height >= targetHeight {
                    for range in format.videoSupportedFrameRateRanges {
                        if range.maxFrameRate >= 30 {
                            if bestFormat == nil {
                                bestFormat = format
                                bestFrameRateRange = range
                            } else {
                                // Daha uygun boyut bul (1080p'ye yakın)
                                let currentDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat!.formatDescription)
                                if dimensions.width <= currentDimensions.width {
                                    bestFormat = format
                                    bestFrameRateRange = range
                                }
                            }
                        }
                    }
                }
            }

            if let format = bestFormat, let frameRateRange = bestFrameRateRange {
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(min(frameRateRange.maxFrameRate, 30)))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(min(frameRateRange.maxFrameRate, 30)))
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure camera for high quality: \(error)")
        }
    }

    private func getCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInDualCamera]
        if #available(iOS 13.0, *) { deviceTypes.append(.builtInTripleCamera) }
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        return discoverySession.devices.first
    }

    /// Runs behind any queued setup work, so a second initialize call can
    /// adopt a prewarm even if startRunning had not completed when it arrived.
    func reusableDescriptor(
        for requestedPosition: AVCaptureDevice.Position,
        completion: @escaping (TextureDescriptor?) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion(nil) }; return }
            let existingFacing = self.currentPosition == .front ? "front" : "back"
            let requestedFacing = requestedPosition == .front ? "front" : "back"
            let active = self.captureSession?.isRunning == true && self.textureId >= 0 &&
                self.previewWidth > 0 && self.previewHeight > 0
            let descriptor = NativeCameraSessionReuseContract.shouldReuse(
                isActive: active,
                existingFacing: existingFacing,
                requestedFacing: requestedFacing
            ) ? TextureDescriptor(
                textureId: self.textureId,
                width: self.previewWidth,
                height: self.previewHeight
            ) : nil
            DispatchQueue.main.async { completion(descriptor) }
        }
    }

    /// Existing authorization is used during setup, but opening the camera
    /// never triggers an unrelated microphone prompt or delays first preview.
    private func configureMicrophoneIfAuthorized() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        addMicrophoneToCaptureSession()
    }

    private func addMicrophoneToCaptureSession() {
        guard let session = captureSession, audioOutput == nil,
              let microphone = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: microphone) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            return
        }
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.audio.queue", qos: .userInitiated))
        session.addOutput(output)
        audioOutput = output
        audioStateLock.lock(); microphoneReady = true; audioStateLock.unlock()
    }

    func takePicture(completion: @escaping (String?, Error?) -> Void) {
        if faceARCoordinator?.hasActiveEffect == true {
            pixelBufferLock.lock()
            let renderedFrame = latestPixelBuffer
            pixelBufferLock.unlock()
            if let renderedFrame = renderedFrame,
               let data = faceARCoordinator?.jpegData(from: renderedFrame) {
                writePhotoData(data, completion: completion)
                return
            }
        }
        guard let photoOutput = photoOutput else {
            completion(nil, NSError(domain: "CameraManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Photo output not available"]))
            return
        }

        photoCompletionHandler = completion

        if let connection = photoOutput.connection(with: .video) {
            updateVideoOrientationIfNeeded(connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = photoOutput.supportedFlashModes.contains(.auto) ? .auto : .off
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startVideoRecording(outputPath: String?, completion: @escaping (Error?) -> Void) {
        ensureMicrophoneReady { [weak self] microphoneError in
            guard let self = self else {
                completion(NSError(domain: "CameraManager", code: 9,
                    userInfo: [NSLocalizedDescriptionKey: "Camera was disposed before recording started"]))
                return
            }
            if let microphoneError = microphoneError { completion(microphoneError); return }
            self.pixelBufferLock.lock()
            let frame = self.latestPixelBuffer
            self.pixelBufferLock.unlock()
            guard let frame = frame else {
                completion(NSError(domain: "CameraManager", code: 6,
                                   userInfo: [NSLocalizedDescriptionKey: "Camera preview is not ready"]))
                return
            }
            let path = outputPath ?? (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("story_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
            completion(self.videoRecorder.start(outputPath: path,
                                                width: CVPixelBufferGetWidth(frame),
                                                height: CVPixelBufferGetHeight(frame)))
        }
    }

    private func ensureMicrophoneReady(completion: @escaping (Error?) -> Void) {
        func configureAuthorizedMicrophone() {
            self.sessionQueue.async { [weak self] in
                guard let self = self else {
                    completion(NSError(domain: "CameraManager", code: 9,
                        userInfo: [NSLocalizedDescriptionKey: "Camera was disposed before microphone setup completed"]))
                    return
                }
                self.addMicrophoneToCaptureSession()
                self.audioStateLock.lock(); let ready = self.microphoneReady; self.audioStateLock.unlock()
                completion(ready ? nil : NSError(domain: "CameraManager", code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Microphone capture is not available"]))
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            configureAuthorizedMicrophone()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    configureAuthorizedMicrophone()
                } else {
                    completion(NSError(domain: "CameraManager", code: 7,
                        userInfo: [NSLocalizedDescriptionKey: "Microphone permission was denied"]))
                }
            }
        default:
            completion(NSError(domain: "CameraManager", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission is required for recording"]))
        }
    }

    func stopVideoRecording(completion: @escaping (String?, Error?) -> Void) {
        videoRecorder.stop(completion: completion)
    }

    private func writePhotoData(_ data: Data, completion: @escaping (String?, Error?) -> Void) {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("story_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            completion(path, nil)
        } catch {
            completion(nil, error)
        }
    }

    func switchCamera(completion: @escaping (Bool, Error?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else {
                completion(false, NSError(domain: "CameraManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Session not available"]))
                return
            }

            session.beginConfiguration()

            let previousVideoInput = session.inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .first { input in input.ports.contains(where: { $0.mediaType == .video }) }
            if let previousVideoInput = previousVideoInput { session.removeInput(previousVideoInput) }

            let previousPosition = self.currentPosition
            let previousDevice = self.currentDevice
            // Switch position
            self.currentPosition = self.currentPosition == .back ? .front : .back

            guard let newDevice = self.getCamera(for: self.currentPosition) else {
                self.currentPosition = previousPosition
                self.currentDevice = previousDevice
                if let previousVideoInput = previousVideoInput, session.canAddInput(previousVideoInput) {
                    session.addInput(previousVideoInput)
                }
                session.commitConfiguration()
                completion(false, NSError(domain: "CameraManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "New camera not available"]))
                return
            }

            self.currentDevice = newDevice

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                guard session.canAddInput(newInput) else {
                    self.currentPosition = previousPosition
                    self.currentDevice = previousDevice
                    if let previousVideoInput = previousVideoInput, session.canAddInput(previousVideoInput) {
                        session.addInput(previousVideoInput)
                    }
                    session.commitConfiguration()
                    completion(false, NSError(domain: "CameraManager", code: 10,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot attach the selected camera"])); return
                }
                session.addInput(newInput)

                if let connection = self.videoOutput?.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }

                session.commitConfiguration()
                completion(true, nil)
            } catch {
                self.currentPosition = previousPosition
                self.currentDevice = previousDevice
                if let previousVideoInput = previousVideoInput, session.canAddInput(previousVideoInput) {
                    session.addInput(previousVideoInput)
                }
                session.commitConfiguration()
                completion(false, error)
            }
        }
    }

    func setFlashMode(mode: String) {
        // Flash mode is set during photo capture
    }

    func setZoomLevel(level: CGFloat) {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            device.videoZoomFactor = min(max(level, 1.0), maxZoom)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }

    private func updateVideoOrientationIfNeeded(_ connection: AVCaptureConnection) {
        guard connection.isVideoOrientationSupported,
              let orientation = Self.captureOrientation(for: UIDevice.current.orientation),
              connection.videoOrientation != orientation else { return }
        connection.videoOrientation = orientation
    }

    private static func captureOrientation(for orientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        // Device and capture landscape names describe opposite viewpoints.
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }

    func dispose(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion?() }; return }
            self.videoRecorder.cancel()
            self.audioStateLock.lock(); self.microphoneReady = false; self.audioStateLock.unlock()
            self.videoOutput?.setSampleBufferDelegate(nil, queue: nil)
            self.audioOutput?.setSampleBufferDelegate(nil, queue: nil)
            self.captureSession?.stopRunning()
            self.captureSession = nil
            self.videoOutput = nil
            self.audioOutput = nil
            self.photoOutput = nil
            self.currentDevice = nil
            self.pixelBufferLock.lock(); self.latestPixelBuffer = nil; self.pixelBufferLock.unlock()
            let textureId = self.textureId
            self.textureId = -1
            self.previewWidth = 0
            self.previewHeight = 0
            DispatchQueue.main.async {
                if textureId >= 0 { self.textureRegistry.unregisterTexture(textureId) }
                completion?()
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            videoRecorder.appendAudio(sampleBuffer: sampleBuffer)
            return
        }
        // AVCaptureConnection rotates and mirrors the delivered pixel buffer.
        // The tracker and renderer both consume that same buffer, so MediaPipe
        // input orientation always matches the Flutter texture and recording.
        if !videoRecorder.isRecording { updateVideoOrientationIfNeeded(connection) }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let displayBuffer = faceARCoordinator?.process(pixelBuffer: pixelBuffer, timestamp: timestamp) ?? pixelBuffer
        pixelBufferLock.lock()
        latestPixelBuffer = displayBuffer
        pixelBufferLock.unlock()
        videoRecorder.appendVideo(pixelBuffer: displayBuffer, presentationTime: timestamp)
        textureRegistry.textureFrameAvailable(textureId)
    }
}

extension CameraManager: FlutterTexture {
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        pixelBufferLock.lock()
        let buffer = latestPixelBuffer
        pixelBufferLock.unlock()
        guard let buffer = buffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let completion = photoCompletionHandler
        photoCompletionHandler = nil
        if let error = error {
            completion?(nil, error)
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            completion?(nil, NSError(domain: "CameraManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to get image data"]))
            return
        }

        let tempDir = NSTemporaryDirectory()
        let fileName = "story_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)

        do {
            try imageData.write(to: URL(fileURLWithPath: filePath))
            completion?(filePath, nil)
        } catch {
            completion?(nil, error)
        }
    }
}
