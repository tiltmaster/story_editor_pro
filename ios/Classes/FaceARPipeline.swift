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

    init(center: CGPoint, eyeDistance: CGFloat, rollRadians: CGFloat, yawNormalized: CGFloat = 0) {
        self.center = center
        self.eyeDistance = eyeDistance
        self.rollRadians = rollRadians
        self.yawNormalized = yawNormalized
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
            yawNormalized: yawNormalized + (next.yawNormalized - yawNormalized) * t
        )
    }
}

enum FaceARPoseGeometry {
    /// Converts detector-semantic eye points into a stable screen-space axis.
    /// Anatomical left/right labels can reverse their X ordering under mirror
    /// transforms; roll must always follow visual left-to-right ordering.
    static func make(firstEye: CGPoint, secondEye: CGPoint, nose: CGPoint?) -> FaceARPose? {
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
            yawNormalized: yaw
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
              landmarks.count > 263 else {
            callback?(nil)
            return
        }
        // MediaPipe Face Mesh outer eye-corner landmarks.
        let left = landmarks[33]
        let right = landmarks[263]
        // MediaPipe image coordinates use a top-left origin. Core Image uses a
        // bottom-left origin, so invert Y once at the provider boundary.
        let leftY = 1 - CGFloat(left.y)
        let rightY = 1 - CGFloat(right.y)
        callback?(FaceARPoseGeometry.make(
            firstEye: CGPoint(x: CGFloat(left.x), y: leftY),
            secondEye: CGPoint(x: CGFloat(right.x), y: rightY),
            nose: CGPoint(x: CGFloat(landmarks[1].x), y: 1 - CGFloat(landmarks[1].y))
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

    private static func pose(from observation: VNFaceObservation?) -> FaceARPose? {
        guard let observation = observation,
              let left = center(of: observation.landmarks?.leftEye, in: observation.boundingBox),
              let right = center(of: observation.landmarks?.rightEye, in: observation.boundingBox) else { return nil }
        let nose = center(of: observation.landmarks?.nose, in: observation.boundingBox)
        return FaceARPoseGeometry.make(firstEye: left, secondEye: right, nose: nose)
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

final class FaceARFrameRenderer {
    private let context: CIContext
    private let glassesImage: CIImage
    let usesRuntimeMesh: Bool
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    init(meshPath: String?) {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
        }
        let asset = Self.makeClassicGlasses(meshPath: meshPath)
        glassesImage = asset.image
        usesRuntimeMesh = asset.usesRuntimeMesh
    }

    func render(input: CVPixelBuffer, pose: FaceARPose, intensity: CGFloat) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        guard let output = outputBuffer(width: width, height: height) else { return nil }
        let source = CIImage(cvPixelBuffer: input)
        let extent = source.extent
        let center = CGPoint(x: pose.center.x * extent.width, y: pose.center.y * extent.height)
        let targetWidth = max(pose.eyeDistance * extent.width * 2.55, 48)
        let scale = targetWidth / glassesImage.extent.width
        var overlay = glassesImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Nose displacement relative to the eye axis is a stable yaw proxy.
        // Compress the far side and offset toward the near side. Because the
        // authored XYZ mesh is rasterized during preparation, this is an
        // honest 2.5D perspective approximation rather than claimed full 3D.
        let yaw = max(-1, min(1, pose.yawNormalized))
        overlay = overlay.transformed(by: CGAffineTransform(scaleX: 1 - abs(yaw) * 0.34, y: 1))
        overlay = overlay.transformed(by: CGAffineTransform(translationX: -overlay.extent.midX, y: -overlay.extent.midY))
        overlay = overlay.transformed(by: CGAffineTransform(rotationAngle: pose.rollRadians))
        overlay = overlay.transformed(by: CGAffineTransform(
            translationX: center.x + yaw * targetWidth * 0.13,
            y: center.y + targetWidth * 0.015
        ))

        if intensity < 0.999, let alpha = CIFilter(name: "CIColorMatrix") {
            alpha.setValue(overlay, forKey: kCIInputImageKey)
            alpha.setValue(CIVector(x: 0, y: 0, z: 0, w: max(0, min(1, intensity))), forKey: "inputAVector")
            overlay = alpha.outputImage ?? overlay
        }
        context.render(
            overlay.composited(over: source).cropped(to: extent),
            to: output,
            bounds: extent,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return output
    }

    func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92)
    }

    private func outputBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let size = CGSize(width: width, height: height)
        if pool == nil || poolSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var newPool: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool) == kCVReturnSuccess else { return nil }
            pool = newPool
            poolSize = size
        }
        var buffer: CVPixelBuffer?
        guard let pool = pool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }

    /// Rasterizes the Blender-authored runtime mesh once, off the frame path.
    /// Core Image then transforms that immutable overlay on the GPU per frame.
    /// This preserves the authored silhouette/material split without a GLB
    /// dependency or repeated JSON parsing.
    private static func makeClassicGlasses(meshPath: String?) -> (image: CIImage, usesRuntimeMesh: Bool) {
        if let meshPath = meshPath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: meshPath)),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawVertices = root["vertices"] as? [[NSNumber]],
           let rawTriangles = root["triangles"] as? [[NSNumber]],
           let materialIds = root["triangle_material_ids"] as? [NSNumber],
           !rawVertices.isEmpty, !rawTriangles.isEmpty {
            let vertices = rawVertices.compactMap { values -> (x: CGFloat, y: CGFloat, z: CGFloat)? in
                guard values.count >= 3 else { return nil }
                return (CGFloat(truncating: values[0]), CGFloat(truncating: values[1]), CGFloat(truncating: values[2]))
            }
            if vertices.count == rawVertices.count {
                let size = CGSize(width: 640, height: 240)
                let rasterizer = UIGraphicsImageRenderer(size: size)
                let image = rasterizer.image { output in
                    output.cgContext.setShouldAntialias(true)
                    let scale: CGFloat = 275
                    let projected = vertices.map { vertex -> CGPoint in
                        // Shallow perspective preserves the authored temple
                        // depth in the frontal tracking view.
                        let perspective = 1 / (1 + max(-0.25, vertex.z) * 0.07)
                        return CGPoint(x: size.width * 0.5 + vertex.x * scale * perspective,
                                       y: size.height * 0.5 - vertex.y * scale * perspective)
                    }
                    let ordered = rawTriangles.enumerated().sorted { lhs, rhs in
                        func depth(_ item: (offset: Int, element: [NSNumber])) -> CGFloat {
                            let indexes = item.element.prefix(3).map { $0.intValue }
                            guard indexes.count == 3, indexes.allSatisfy({ vertices.indices.contains($0) }) else { return 0 }
                            return indexes.reduce(0) { $0 + vertices[$1].z } / 3
                        }
                        return depth(lhs) > depth(rhs)
                    }
                    for (triangleIndex, rawTriangle) in ordered {
                        let indexes = rawTriangle.prefix(3).map { $0.intValue }
                        guard indexes.count == 3, indexes.allSatisfy({ projected.indices.contains($0) }) else { continue }
                        let path = UIBezierPath()
                        path.move(to: projected[indexes[0]])
                        path.addLine(to: projected[indexes[1]])
                        path.addLine(to: projected[indexes[2]])
                        path.close()
                        let material = triangleIndex < materialIds.count ? materialIds[triangleIndex].intValue : 0
                        (material == 1
                            ? UIColor(red: 0.012, green: 0.045, blue: 0.060, alpha: 0.48)
                            : UIColor(red: 0.006, green: 0.008, blue: 0.012, alpha: 1)).setFill()
                        path.fill()
                    }
                }
                if let ciImage = CIImage(image: image) { return (ciImage, true) }
            }
        }

        // Deterministic fallback if an application omits the optional mesh.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 190))
        let image = renderer.image { context in
            context.cgContext.setShouldAntialias(true)
            UIColor(white: 0.05, alpha: 0.20).setFill()
            UIBezierPath(roundedRect: CGRect(x: 34, y: 34, width: 180, height: 118), cornerRadius: 48).fill()
            UIBezierPath(roundedRect: CGRect(x: 298, y: 34, width: 180, height: 118), cornerRadius: 48).fill()
            UIColor(white: 0.04, alpha: 0.97).setStroke()
            let frames = UIBezierPath()
            frames.lineWidth = 18
            frames.append(UIBezierPath(roundedRect: CGRect(x: 28, y: 28, width: 192, height: 130), cornerRadius: 54))
            frames.append(UIBezierPath(roundedRect: CGRect(x: 292, y: 28, width: 192, height: 130), cornerRadius: 54))
            frames.move(to: CGPoint(x: 220, y: 79))
            frames.addCurve(to: CGPoint(x: 292, y: 79), controlPoint1: CGPoint(x: 242, y: 57), controlPoint2: CGPoint(x: 270, y: 57))
            frames.move(to: CGPoint(x: 28, y: 72)); frames.addLine(to: CGPoint(x: 0, y: 52))
            frames.move(to: CGPoint(x: 484, y: 72)); frames.addLine(to: CGPoint(x: 512, y: 52))
            frames.stroke()
        }
        return (CIImage(image: image) ?? CIImage.empty(), false)
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
    private let meshPaths: [String: String]
    private let lock = NSLock()
    private var renderers: [String: FaceARFrameRenderer] = [:]
    private var tracker: FaceLandmarkTracking?
    private var backend = "unprepared"
    private var state: State = .disabled
    private var enabled = false
    private var lensId = "none"
    private var intensity: CGFloat = 1
    private var pose: FaceARPose?
    private var frameIndex = 0
    private var trackingInFlight = false
    private var lastTrackingEvent: Bool?
    private var eventSink: FlutterEventSink?
    private var preparationStarted = false
    private var preparationGeneration: UInt = 0
    private var lastTimestampMilliseconds = -1

    init(modelPath: String?, meshPaths: [String: String]) {
        self.modelPath = modelPath
        self.meshPaths = meshPaths
    }

    var capabilities: [String: Any] {
        lock.lock(); let currentBackend = backend; lock.unlock()
        let supported = !meshPaths.isEmpty
        return ["supported": supported, "backend": currentBackend, "maxFaces": 1,
                "supports3D": false, "supportsRecording": supported,
                "faceTracking": supported, "preview": supported, "recording": supported,
                "lensIds": Array(meshPaths.keys).sorted()]
    }

    var hasActiveEffect: Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && lensId != "none" && renderers[lensId] != nil && state == .active
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
            // Mesh parsing/rasterization is part of asynchronous preparation,
            // never camera startup or the first preview frame.
            let preparedRenderers = self.meshPaths.mapValues {
                FaceARFrameRenderer(meshPath: $0)
            }
            self.lock.lock()
            guard generation == self.preparationGeneration else {
                self.lock.unlock()
                selected?.cancel()
                return
            }
            self.tracker = selected
            self.renderers = preparedRenderers
            self.backend = selectedBackend
            self.preparationStarted = false
            let next: State
            if self.enabled {
                next = Self.operationalState(enabled: true, lensId: self.lensId, trackerAvailable: true)
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

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        if !value { pose = nil; lastTrackingEvent = nil }
        let next = Self.operationalState(enabled: value, lensId: lensId, trackerAvailable: tracker != nil)
        state = next
        lock.unlock()
        emitState(next)
        if value { prepare() }
    }

    func setLens(id: String, intensity value: Double) throws {
        guard id == "none" || meshPaths[id] != nil else {
            throw NSError(domain: "FaceAR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown lens id: \(id)"])
        }
        lock.lock()
        lensId = id
        intensity = CGFloat(max(0, min(1, value)))
        let next = Self.operationalState(enabled: enabled, lensId: id, trackerAvailable: tracker != nil)
        state = next
        let needsPreparation = enabled && tracker == nil
        lock.unlock()
        emitState(next)
        if needsPreparation { prepare() }
    }

    func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> CVPixelBuffer {
        lock.lock()
        let currentRenderer = renderers[lensId]
        let active = enabled && lensId != "none" && currentRenderer != nil && state == .active
        let currentPose = pose
        let currentIntensity = intensity
        frameIndex &+= 1
        let shouldTrack = active && tracker != nil && !trackingInFlight && frameIndex % 2 == 0
        if shouldTrack { trackingInFlight = true }
        let currentTracker = tracker
        lock.unlock()

        if shouldTrack {
            let seconds = CMTimeGetSeconds(timestamp)
            let candidate = seconds.isFinite ? Int((seconds * 1000).rounded()) : 0
            lock.lock()
            let millis = max(candidate, lastTimestampMilliseconds + 1)
            lastTimestampMilliseconds = millis
            lock.unlock()
            currentTracker?.track(pixelBuffer: pixelBuffer, timestampMilliseconds: millis) { [weak self] detected in
                guard let self = self else { return }
                self.lock.lock()
                guard self.enabled && self.lensId != "none" &&
                      self.renderers[self.lensId] != nil && self.state == .active else {
                    self.pose = nil
                    self.trackingInFlight = false
                    self.lock.unlock()
                    return
                }
                self.pose = detected.map { self.pose?.smoothed(toward: $0, alpha: 0.38) ?? $0 }
                self.trackingInFlight = false
                let tracked = detected != nil
                let notify = self.lastTrackingEvent != tracked
                self.lastTrackingEvent = tracked
                self.lock.unlock()
                if notify { self.emit(["type": "tracking", "state": State.active.rawValue, "faceTracked": tracked]) }
            }
        }
        guard active, let currentPose = currentPose else { return pixelBuffer }
        return currentRenderer?.render(
            input: pixelBuffer,
            pose: currentPose,
            intensity: currentIntensity
        ) ?? pixelBuffer
    }

    func jpegData(from buffer: CVPixelBuffer) -> Data? {
        lock.lock(); let renderer = renderers[lensId]; lock.unlock()
        return renderer?.jpegData(from: buffer)
    }

    func dispose() {
        lock.lock()
        let trackerToCancel = tracker
        tracker = nil; renderers.removeAll(); pose = nil; enabled = false; lensId = "none"
        trackingInFlight = false; lastTrackingEvent = nil; backend = "unprepared"; state = .disabled
        preparationStarted = false; preparationGeneration &+= 1; lastTimestampMilliseconds = -1
        lock.unlock()
        trackerToCancel?.cancel()
        emitState(.disabled)
    }

    private func emitState(_ state: State) { emit(["type": "state", "state": state.rawValue]) }

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
            coordinator.setEnabled((call.arguments as? [String: Any])?["enabled"] as? Bool ?? false); result(nil)
        case "setLens":
            let args = call.arguments as? [String: Any]
            do {
                try coordinator.setLens(id: args?["lensId"] as? String ?? "none",
                                        intensity: (args?["intensity"] as? NSNumber)?.doubleValue ?? 1)
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
