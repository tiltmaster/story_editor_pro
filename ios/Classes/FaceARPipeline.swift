import AVFoundation
import CoreImage
import Flutter
import ImageIO
import Metal
import UIKit
import Vision

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

/// Renderer-facing pose. Keeping this independent of the detector makes the
/// native frame graph usable with MediaPipe and with the system fallback.
struct FaceARPose: Equatable {
    let center: CGPoint
    let eyeDistance: CGFloat
    let rollRadians: CGFloat
    let yawNormalized: CGFloat
    let contour: [CGPoint]
    let contourClosed: Bool

    init(center: CGPoint, eyeDistance: CGFloat, rollRadians: CGFloat, yawNormalized: CGFloat = 0,
         contour: [CGPoint] = [], contourClosed: Bool = true) {
        self.center = center
        self.eyeDistance = eyeDistance
        self.rollRadians = rollRadians
        self.yawNormalized = yawNormalized
        self.contour = contour
        self.contourClosed = contourClosed
    }

    /// Normalized upright unmirrored camera coordinates, with a top-left origin,
    /// consumed by the Flutter preview shader and recorded pose timeline.
    var normalizedTopLeftEyes: [String: Double] {
        let dx = cos(rollRadians) * eyeDistance * 0.5
        let dy = sin(rollRadians) * eyeDistance * 0.5
        return ["leftX": Double(center.x - dx), "leftY": Double(1 - center.y + dy),
                "rightX": Double(center.x + dx), "rightY": Double(1 - center.y - dy)]
    }

    func pixelEyeAxis(in size: CGSize) -> CGPoint {
        CGPoint(x: cos(rollRadians) * eyeDistance * size.width,
                y: sin(rollRadians) * eyeDistance * size.height)
    }

    func smoothed(toward next: FaceARPose, alpha: CGFloat) -> FaceARPose {
        let t = min(max(alpha, 0), 1)
        var angleDelta = next.rollRadians - rollRadians
        while angleDelta > .pi { angleDelta -= 2 * .pi }
        while angleDelta < -.pi { angleDelta += 2 * .pi }
        return FaceARPose(
            center: CGPoint(
                x: center.x + (next.center.x - center.x) * t,
                y: center.y + (next.center.y - center.y) * t
            ),
            eyeDistance: eyeDistance + (next.eyeDistance - eyeDistance) * t,
            rollRadians: rollRadians + angleDelta * t,
            yawNormalized: yawNormalized + (next.yawNormalized - yawNormalized) * t,
            contour: contour.count == next.contour.count && contourClosed == next.contourClosed
                ? zip(contour, next.contour).map { previous, following in
                    CGPoint(x: previous.x + (following.x - previous.x) * t,
                            y: previous.y + (following.y - previous.y) * t)
                } : next.contour,
            contourClosed: next.contourClosed
        )
    }
}

enum FaceARPoseGeometry {
    static func eyeCenter(outer: CGPoint, inner: CGPoint) -> CGPoint {
        CGPoint(x: (outer.x + inner.x) * 0.5, y: (outer.y + inner.y) * 0.5)
    }

    /// Converts detector-semantic eye points into a stable screen-space axis.
    /// Anatomical left/right labels can reverse their X ordering under mirror
    /// transforms; roll must always follow visual left-to-right ordering.
    static func make(firstEye: CGPoint, secondEye: CGPoint, nose: CGPoint?,
                     contour: [CGPoint] = [], contourClosed: Bool = true) -> FaceARPose? {
        let left: CGPoint
        let right: CGPoint
        if firstEye.x <= secondEye.x {
            left = firstEye; right = secondEye
        } else {
            left = secondEye; right = firstEye
        }
        let dx = right.x - left.x
        let dy = right.y - left.y
        let distance = hypot(dx, dy)
        guard distance > 0.015 else { return nil }
        let center = CGPoint(x: (left.x + right.x) * 0.5, y: (left.y + right.y) * 0.5)
        let yaw: CGFloat
        if let nose = nose {
            // Project along the eye axis so head roll cannot masquerade as yaw.
            let alongAxis = ((nose.x - center.x) * dx + (nose.y - center.y) * dy) /
                (distance * distance)
            yaw = max(-1, min(1, alongAxis * 1.8))
        } else {
            yaw = 0
        }
        return FaceARPose(
            center: center,
            eyeDistance: distance,
            rollRadians: atan2(dy, dx),
            yawNormalized: yaw, contour: contour, contourClosed: contourClosed
        )
    }
}

protocol FaceLandmarkTracking: AnyObject {
    func track(pixelBuffer: CVPixelBuffer, timestampMilliseconds: Int, completion: @escaping (FaceARPose?) -> Void)
    func cancel()
}

#if canImport(MediaPipeTasksVision)
/// Apache-2 MediaPipe Tasks face landmarker. The task model is packaged as a
/// Flutter asset and resolved by the plugin registrar; no network or paid SDK
/// is involved at runtime.
final class MediaPipeFaceLandmarkTracker: NSObject, FaceLandmarkTracking, FaceLandmarkerLiveStreamDelegate {
    private var landmarker: FaceLandmarker?
    private let lock = NSLock()
    private var completions: [Int: (FaceARPose?) -> Void] = [:]

    init(modelPath: String) throws {
        super.init()
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.55
        options.minFacePresenceConfidence = 0.55
        options.minTrackingConfidence = 0.55
        options.faceLandmarkerLiveStreamDelegate = self
        landmarker = try FaceLandmarker(options: options)
    }

    func track(pixelBuffer: CVPixelBuffer, timestampMilliseconds: Int, completion: @escaping (FaceARPose?) -> Void) {
        guard let landmarker = landmarker else { completion(nil); return }
        do {
            let image = try MPImage(pixelBuffer: pixelBuffer)
            lock.lock()
            completions[timestampMilliseconds] = completion
            // Bound retained callbacks if the detector drops a frame.
            var dropped: ((FaceARPose?) -> Void)?
            if completions.count > 4, let oldest = completions.keys.min() {
                dropped = completions.removeValue(forKey: oldest)
            }
            lock.unlock()
            dropped?(nil)
            try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampMilliseconds)
        } catch {
            lock.lock()
            let callback = completions.removeValue(forKey: timestampMilliseconds)
            lock.unlock()
            callback?(nil)
        }
    }

    func faceLandmarker(
        _ faceLandmarker: FaceLandmarker,
        didFinishDetection result: FaceLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        lock.lock()
        let callback = completions.removeValue(forKey: timestampInMilliseconds)
        lock.unlock()
        guard error == nil,
              let landmarks = result?.faceLandmarks.first,
              landmarks.count > 362 else {
            callback?(nil)
            return
        }
        // Match Android: average each eye's inner and outer corners. Outer
        // corners alone incorrectly place the reshape center at the temples.
        // Convert the top-left detector origin once at the provider boundary.
        func point(_ index: Int) -> CGPoint {
            CGPoint(x: CGFloat(landmarks[index].x), y: 1 - CGFloat(landmarks[index].y))
        }
        let faceOval = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
                        397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
                        172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
        // A partial result may contain eyes without the complete oval.
        let contour = landmarks.count > 454 ? faceOval.map(point) : []
        callback?(FaceARPoseGeometry.make(
            firstEye: FaceARPoseGeometry.eyeCenter(outer: point(33), inner: point(133)),
            secondEye: FaceARPoseGeometry.eyeCenter(outer: point(263), inner: point(362)),
            nose: CGPoint(x: CGFloat(landmarks[1].x), y: 1 - CGFloat(landmarks[1].y)),
            contour: contour
        ))
    }

    func cancel() {
        lock.lock()
        let callbacks = completions.values
        completions.removeAll()
        landmarker = nil
        lock.unlock()
        callbacks.forEach { $0(nil) }
    }
}
#endif

/// Free system fallback used if MediaPipe cannot be initialized on a device.
final class VisionFaceLandmarkTracker: FaceLandmarkTracking {
    private let queue = DispatchQueue(label: "story_editor_pro.ar.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt = 0

    func track(pixelBuffer: CVPixelBuffer, timestampMilliseconds: Int, completion: @escaping (FaceARPose?) -> Void) {
        lock.lock(); let requestGeneration = generation; lock.unlock()
        queue.async { [weak self] in
            guard let self = self else { return }
            let request = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try? handler.perform([request])
            let pose = Self.pose(from: request.results?.first)
            self.lock.lock(); let current = requestGeneration == self.generation; self.lock.unlock()
            if current { completion(pose) }
        }
    }

    func cancel() {
        lock.lock(); generation &+= 1; lock.unlock()
    }

    static func pose(from observation: VNFaceObservation?) -> FaceARPose? {
        guard let observation = observation,
              let left = center(of: observation.landmarks?.leftEye, in: observation.boundingBox),
              let right = center(of: observation.landmarks?.rightEye, in: observation.boundingBox) else { return nil }
        let nose = center(of: observation.landmarks?.nose, in: observation.boundingBox)
        let contour = points(of: observation.landmarks?.faceContour, in: observation.boundingBox)
        // Vision provides a real open jaw contour, not forehead landmarks.
        return FaceARPoseGeometry.make(firstEye: left, secondEye: right, nose: nose,
                                       contour: contour, contourClosed: false)
    }

    private static func points(of region: VNFaceLandmarkRegion2D?, in box: CGRect) -> [CGPoint] {
        guard let region = region else { return [] }
        return (0..<region.pointCount).map { index in
            CGPoint(x: box.minX + CGFloat(region.normalizedPoints[index].x) * box.width,
                    y: box.minY + CGFloat(region.normalizedPoints[index].y) * box.height)
        }
    }

    private static func center(of region: VNFaceLandmarkRegion2D?, in box: CGRect) -> CGPoint? {
        guard let region = region, region.pointCount > 0 else { return nil }
        var sum = CGPoint.zero
        for index in 0..<region.pointCount {
            sum.x += region.normalizedPoints[index].x
            sum.y += region.normalizedPoints[index].y
        }
        let count = CGFloat(region.pointCount)
        return CGPoint(
            x: box.minX + (sum.x / count) * box.width,
            y: box.minY + (sum.y / count) * box.height
        )
    }
}

final class FaceARCoordinator {
    enum State: String { case disabled, preparing, ready, active, unavailable }

    static func operationalState(enabled: Bool, lensId: String, trackerAvailable: Bool) -> State {
        guard enabled else { return .disabled }
        guard trackerAvailable else { return .preparing }
        return lensId == "none" ? .ready : .active
    }

    private let modelPath: String?
    private let lock = NSLock()
    // Video frames and AVCapturePhoto callbacks arrive on different queues.
    // Renderer pools/caches are dimension-specific mutable state, so serialize
    // only the actual render/encode work while keeping coordinator state reads
    // under the shorter lock above.
    private let renderLock = NSLock()
    private var tracker: FaceLandmarkTracking?
    private var backend = "unprepared"
    private var state: State = .disabled
    private var enabled = false
    private var lensId = "none"
    private var intensity: CGFloat = 1
    private var beautyEyes: CGFloat = 0
    private var beautySlim: CGFloat = 0
    private var pose: FaceARPose?
    private var trackingInFlight = false
    private var lastTrackingEvent: Bool?
    private var eventSink: FlutterEventSink?
    private var preparationStarted = false
    private var preparationGeneration: UInt = 0
    private var trackingGeneration: UInt = 0
    private var lastTimestampMilliseconds = -1
    private var lastTrackingRequestMilliseconds = -1
    private var poseReceivedAt = Date.distantPast
    private var creativeRenderer: CreativeLensFrameRenderer?
    private var creativeContext = CreativeLensContext()

    init(modelPath: String?) {
        self.modelPath = modelPath
    }

    var capabilities: [String: Any] {
        lock.lock(); let currentBackend = backend; lock.unlock()
        // Vision is always available on the iOS 15 deployment target.
        let faceTrackingSupported = true
        let supported = faceTrackingSupported || !CreativeLensFrameRenderer.lensIds.isEmpty
        return ["supported": supported, "backend": currentBackend, "maxFaces": 1,
                "supports3D": false, "supportsRecording": supported,
                "faceTracking": faceTrackingSupported, "preview": supported, "recording": supported,
                "lensIds": Array(CreativeLensFrameRenderer.lensIds.union(CreativeLensFrameRenderer.adornmentIds)).sorted()]
    }

    var faceReady: Bool {
        lock.lock(); defer { lock.unlock() }; return tracker != nil
    }

    var runtimeState: String {
        lock.lock(); defer { lock.unlock() }; return state.rawValue
    }

    // Called only while holding `lock`.
    private var hasSelection: Bool {
        creativeContext.hasOverlay || beautyEyes > 0 || beautySlim > 0 || lensId != "none"
    }

    var hasActiveEffect: Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && state == .active &&
            (CreativeLensFrameRenderer.lensIds.contains(lensId) ||
             CreativeLensFrameRenderer.adornmentIds.contains(lensId) || creativeContext.hasOverlay || beautyEyes > 0 || beautySlim > 0)
    }

    func setEventSink(_ sink: FlutterEventSink?) {
        lock.lock(); eventSink = sink; let current = state; lock.unlock()
        emit(["type": "state", "state": current.rawValue])
    }

    func prepare() {
        lock.lock()
        if tracker != nil || preparationStarted { lock.unlock(); return }
        preparationStarted = true
        let generation = preparationGeneration
        state = .preparing
        lock.unlock()
        emitState(.preparing)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var selected: FaceLandmarkTracking?
            var selectedBackend = "vision"
#if canImport(MediaPipeTasksVision)
            if let path = self.modelPath {
                selected = try? MediaPipeFaceLandmarkTracker(modelPath: path)
                if selected != nil { selectedBackend = "mediapipe_tasks" }
            }
#endif
            if selected == nil { selected = VisionFaceLandmarkTracker() }
            self.lock.lock()
            guard generation == self.preparationGeneration else {
                self.lock.unlock()
                selected?.cancel()
                return
            }
            self.tracker = selected
            self.backend = selectedBackend
            self.preparationStarted = false
            let next: State
            if self.enabled {
                next = Self.operationalState(enabled: true, lensId: self.hasSelection && self.lensId == "none" ? "overlay" : self.lensId, trackerAvailable: true)
            } else {
                // `prepare` on its own reports ready; an explicit disable that
                // arrives while preparation is running remains disabled.
                next = self.state == .disabled ? .disabled : .ready
            }
            self.state = next
            self.lock.unlock()
            self.emitState(next)
        }
    }

    /// Report the writer's actual media-session origin in the detector clock.
    func recordingStarted(at timestamp: CMTime) {
        let seconds = CMTimeGetSeconds(timestamp)
        guard seconds.isFinite else { return }
        emit(["type": "recordingStarted", "timestampMs": Int((seconds * 1000).rounded())])
    }

    /// Camera switches and output rotation invalidate every in-flight pose.
    /// The model stays warm, while stale coordinates can never cross sessions.
    func resetTracking() {
        lock.lock()
        trackingGeneration &+= 1
        pose = nil; trackingInFlight = false; lastTrackingEvent = nil
        lastTrackingRequestMilliseconds = -1
        let current = state
        let timestamp = max(0, lastTimestampMilliseconds)
        lock.unlock()
        emit(["type": "pose", "state": current.rawValue, "faceTracked": false,
              "timestampMs": timestamp, "facePose": NSNull()])
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        if !value { pose = nil; lastTrackingEvent = nil }
        let needsTracker = beautyEyes > 0 || beautySlim > 0 || CreativeLensFrameRenderer.adornmentIds.contains(lensId)
        let trackerReady = tracker != nil || !needsTracker
        let next = Self.operationalState(enabled: value, lensId: hasSelection && lensId == "none" ? "overlay" : lensId, trackerAvailable: trackerReady)
        state = next
        lock.unlock()
        emitState(next)
        if !value { resetTracking() }
        if value && needsTracker { prepare() }
    }

    func setLens(
        id: String,
        intensity value: Double,
        languageCode: String = "en",
        countryCode: String = "",
        mirrorOutput: Bool = false,
        compositionId: String = "none",
        placeStyle: String = "none",
        placeName: String = "",
        beautyEyes: Double = 0,
        beautySlim: Double = 0
    ) throws {
        guard value.isFinite, beautyEyes.isFinite, beautySlim.isFinite,
              ["none", "postcard", "editorial", "stamp"].contains(placeStyle),
              compositionId == "none" || CreativeLensFrameRenderer.lensIds.contains(compositionId),
              id == "none" || CreativeLensFrameRenderer.lensIds.contains(id) || CreativeLensFrameRenderer.adornmentIds.contains(id) else {
            throw NSError(domain: "FaceAR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown lens id: \(id)"])
        }
        lock.lock()
        lensId = id
        intensity = CGFloat(max(0, min(1, value)))
        self.beautyEyes = CGFloat(max(0, min(1, beautyEyes)))
        self.beautySlim = CGFloat(max(0, min(1, beautySlim)))
        creativeContext = CreativeLensContext(
            languageCode: languageCode,
            countryCode: countryCode,
            mirrorOutput: mirrorOutput,
            compositionId: compositionId, placeStyle: placeStyle, placeName: placeName
        )
        let requiresTracker = self.beautyEyes > 0 || self.beautySlim > 0 || CreativeLensFrameRenderer.adornmentIds.contains(id)
        let next = Self.operationalState(
            enabled: enabled,
            lensId: hasSelection && id == "none" ? "overlay" : id,
            trackerAvailable: tracker != nil || !requiresTracker
        )
        state = next
        let needsPreparation = enabled && requiresTracker && tracker == nil
        lock.unlock()
        emitState(next)
        if needsPreparation { prepare() }
    }

    func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> CVPixelBuffer {
        lock.lock()
        let currentLensId = lensId
        let active = enabled && state == .active
        let tracksFace = beautyEyes > 0 || beautySlim > 0 || CreativeLensFrameRenderer.adornmentIds.contains(lensId)
        let currentPose = Date().timeIntervalSince(poseReceivedAt) <= 0.18 ? pose : nil
        let currentIntensity = intensity
        let currentCreativeContext = creativeContext
        let creativeActive = active && (creativeContext.hasOverlay ||
            CreativeLensFrameRenderer.lensIds.contains(lensId) || CreativeLensFrameRenderer.adornmentIds.contains(lensId))
        let seconds = CMTimeGetSeconds(timestamp)
        let candidate = seconds.isFinite ? Int((seconds * 1000).rounded()) : 0
        let millis = max(candidate, lastTimestampMilliseconds + 1)
        lastTimestampMilliseconds = millis
        // Cap tracking work independently of 30/60/120 Hz camera configuration.
        let due = lastTrackingRequestMilliseconds < 0 || millis - lastTrackingRequestMilliseconds >= 67
        let shouldTrack = active && tracksFace && tracker != nil && !trackingInFlight && due
        if shouldTrack { trackingInFlight = true; lastTrackingRequestMilliseconds = millis }
        let currentTracker = tracker
        let generation = trackingGeneration
        if creativeActive && creativeRenderer == nil { creativeRenderer = CreativeLensFrameRenderer() }
        let activeCreativeRenderer = creativeRenderer
        lock.unlock()

        if shouldTrack {
            currentTracker?.track(pixelBuffer: pixelBuffer, timestampMilliseconds: millis) { [weak self] detected in
                guard let self = self else { return }
                self.lock.lock()
                guard generation == self.trackingGeneration else { self.lock.unlock(); return }
                guard self.enabled && self.lensId == currentLensId && self.state == .active else {
                    self.pose = nil; self.trackingInFlight = false; self.lock.unlock(); return
                }
                self.pose = detected.map { self.pose?.smoothed(toward: $0, alpha: 0.38) ?? $0 }
                self.poseReceivedAt = Date()
                self.trackingInFlight = false
                let tracked = detected != nil
                self.lastTrackingEvent = tracked
                let eventPose = self.pose
                self.lock.unlock()
                self.emit(["type": "pose", "state": State.active.rawValue,
                           "faceTracked": tracked, "timestampMs": millis,
                           "facePose": eventPose.map { $0.normalizedTopLeftEyes as Any } ?? NSNull()])
            }
        }
        guard active else { return pixelBuffer }
        renderLock.lock(); defer { renderLock.unlock() }
        var output = pixelBuffer
        if creativeActive {
            let seconds = CMTimeGetSeconds(timestamp)
            output = activeCreativeRenderer?.render(input: output, lensId: currentLensId,
                intensity: currentIntensity, lensContext: currentCreativeContext, pose: currentPose,
                time: seconds.isFinite ? seconds.truncatingRemainder(dividingBy: 12) : 0) ?? output
        }
        return output
    }

    /// Photo buffers carry EXIF orientation independently of the live video
    /// connection. Normalize pixels before detecting or authoring upright text.
    /// A fresh photo pose avoids reusing the preview crop's coordinates in 4:3.
    func processPhoto(pixelBuffer: CVPixelBuffer, metadata: [String: Any]) -> CVPixelBuffer? {
        lock.lock()
        let currentLensId = lensId
        let active = enabled && state == .active
        let currentIntensity = intensity
        let currentContext = creativeContext
        let needsPose = beautyEyes > 0 || beautySlim > 0 || CreativeLensFrameRenderer.adornmentIds.contains(lensId)
        if creativeRenderer == nil { creativeRenderer = CreativeLensFrameRenderer() }
        let renderer = creativeRenderer
        lock.unlock()
        guard active else { return pixelBuffer }
        let orientation = (metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value ?? 1
        let source = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: Int32(orientation))
        let upright = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        var photoPose: FaceARPose?
        if needsPose {
            let request = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(ciImage: upright, orientation: .up, options: [:])
            try? handler.perform([request])
            photoPose = VisionFaceLandmarkTracker.pose(from: request.results?.first)
            emit(["type": "pose", "state": State.active.rawValue,
                  "faceTracked": photoPose != nil, "isPhoto": true,
                  "timestampMs": Int(ProcessInfo.processInfo.systemUptime * 1000),
                  "facePose": photoPose.map { $0.normalizedTopLeftEyes as Any } ?? NSNull()])
        }
        renderLock.lock(); defer { renderLock.unlock() }
        return renderer?.render(source: upright, lensId: currentLensId,
                                intensity: currentIntensity, lensContext: currentContext,
                                pose: photoPose, time: ProcessInfo.processInfo.systemUptime)
    }

    func jpegData(from buffer: CVPixelBuffer) -> Data? {
        lock.lock()
        let activeCreativeRenderer = creativeRenderer
        lock.unlock()
        renderLock.lock()
        defer { renderLock.unlock() }
        return activeCreativeRenderer?.jpegData(from: buffer)
    }

    func dispose() {
        lock.lock()
        let trackerToCancel = tracker
        tracker = nil; creativeRenderer = nil; pose = nil; enabled = false; lensId = "none"
        beautyEyes = 0; beautySlim = 0; lastTrackingRequestMilliseconds = -1
        trackingInFlight = false; lastTrackingEvent = nil; backend = "unprepared"; state = .disabled
        preparationStarted = false; preparationGeneration &+= 1; trackingGeneration &+= 1; lastTimestampMilliseconds = -1
        lock.unlock()
        trackerToCancel?.cancel()
        emitState(.disabled)
    }

    private func emitState(_ state: State) { emit(["type": "state", "state": state.rawValue, "faceReady": faceReady]) }

    private func emit(_ event: [String: Any]) {
        lock.lock(); let sink = eventSink; lock.unlock()
        if let sink = sink { DispatchQueue.main.async { sink(event) } }
    }
}

final class FaceARMethodHandler: NSObject, FlutterPlugin {
    private let coordinator: FaceARCoordinator
    init(coordinator: FaceARCoordinator) { self.coordinator = coordinator }
    static func register(with registrar: FlutterPluginRegistrar) {}

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCapabilities": result(coordinator.capabilities)
        case "prepare": coordinator.prepare(); result(["accepted": true])
        case "setEnabled":
            coordinator.setEnabled((call.arguments as? [String: Any])?["enabled"] as? Bool ?? false)
            result(["state": coordinator.runtimeState, "faceReady": coordinator.faceReady])
        case "setLens":
            let args = call.arguments as? [String: Any]
            do {
                try coordinator.setLens(
                    id: args?["lensId"] as? String ?? "none",
                    intensity: (args?["intensity"] as? NSNumber)?.doubleValue ?? 1,
                    languageCode: args?["languageCode"] as? String ?? "en",
                    countryCode: args?["countryCode"] as? String ?? "",
                    mirrorOutput: args?["mirrorOutput"] as? Bool ?? false,
                    compositionId: args?["compositionId"] as? String ?? "none",
                    placeStyle: args?["placeStyle"] as? String ?? "none",
                    placeName: args?["placeName"] as? String ?? "",
                    beautyEyes: (args?["beautyEyes"] as? NSNumber)?.doubleValue ?? 0,
                    beautySlim: (args?["beautySlim"] as? NSNumber)?.doubleValue ?? 0
                )
                result(nil)
            } catch {
                result(FlutterError(code: "INVALID_LENS", message: error.localizedDescription, details: nil))
            }
        case "dispose": coordinator.dispose(); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
    }
}

final class FaceAREventStreamHandler: NSObject, FlutterStreamHandler {
    private let coordinator: FaceARCoordinator
    init(coordinator: FaceARCoordinator) { self.coordinator = coordinator }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        coordinator.setEventSink(events); return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        coordinator.setEventSink(nil); return nil
    }
}
