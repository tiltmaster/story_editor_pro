import CoreImage
import CoreVideo
import Foundation
import Vision

/// A real Vision person mask is the only input to background replacement.
/// Capture frames are already upright and unmirrored, so source and mask share
/// a coordinate space before the final Flutter presentation mirror.
final class PersonBackgroundProcessor {
    static let maximumMaskAge: TimeInterval = 0.35
    static let minimumRequestInterval: TimeInterval = 0.10

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "story_editor_pro.person_segmentation", qos: .userInitiated)
    private var enabled = false
    private var generation: UInt = 0
    private var busy = false
    private var lastRequestAt: TimeInterval = -.infinity
    private var mask: CIImage?
    private var maskSourceSize = CGSize.zero
    private var maskSourceTime: TimeInterval = -.infinity
    private var reportedReady = false
    private var lastFailure: String?
    // This stateful Vision request is created and used only by `queue`.
    private var request: VNGeneratePersonSegmentationRequest?
    private var requestGeneration: UInt?
    private let onStatus: (Bool, String?) -> Void

    init(onStatus: @escaping (Bool, String?) -> Void) { self.onStatus = onStatus }

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && mask != nil && ProcessInfo.processInfo.systemUptime - maskSourceTime <= Self.maximumMaskAge
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        guard enabled != value else { lock.unlock(); return }
        enabled = value
        generation &+= 1; busy = false; mask = nil
        lastRequestAt = -.infinity; reportedReady = false; lastFailure = nil
        let currentGeneration = generation
        lock.unlock()
        report(message: nil, generation: currentGeneration)
    }

    func invalidate() {
        lock.lock()
        generation &+= 1; busy = false; mask = nil
        lastRequestAt = -.infinity; reportedReady = false; lastFailure = nil
        let notify = enabled
        let currentGeneration = generation
        lock.unlock()
        if notify { report(message: nil, generation: currentGeneration) }
    }

    func submit(_ pixelBuffer: CVPixelBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard enabled, !busy, now - lastRequestAt >= Self.minimumRequestInterval else { lock.unlock(); return }
        busy = true; lastRequestAt = now
        let submittedGeneration = generation
        let sourceSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        lock.unlock()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let valid = self.enabled && self.generation == submittedGeneration
            self.lock.unlock()
            guard valid else { return }
            var generated: CIImage?
            var failure: String?
            do {
                if self.request == nil || self.requestGeneration != submittedGeneration {
                    let request = VNGeneratePersonSegmentationRequest()
                    request.qualityLevel = .balanced
                    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                    self.request = request
                    self.requestGeneration = submittedGeneration
                }
                guard let request = self.request else { return }
                try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]).perform([request])
                if let buffer = request.results?.first?.pixelBuffer {
                    generated = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
                } else {
                    failure = "Person segmentation returned no mask."
                }
            } catch { failure = error.localizedDescription }
            self.lock.lock()
            guard self.enabled && self.generation == submittedGeneration else { self.lock.unlock(); return }
            self.busy = false
            self.mask = generated
            self.maskSourceSize = sourceSize
            self.maskSourceTime = now
            let ready = generated != nil && ProcessInfo.processInfo.systemUptime - now <= Self.maximumMaskAge
            let changed = ready != self.reportedReady || failure != self.lastFailure
            self.reportedReady = ready; self.lastFailure = failure
            self.lock.unlock()
            if changed { self.report(message: failure, generation: submittedGeneration) }
        }
    }

    func latestMask(sourceSize: CGSize) -> CIImage? {
        lock.lock()
        let valid = enabled && sourceSize == maskSourceSize &&
            ProcessInfo.processInfo.systemUptime - maskSourceTime <= Self.maximumMaskAge
        let image = valid ? mask : nil
        let expired = !valid && reportedReady
        if expired { reportedReady = false }
        let currentGeneration = generation
        lock.unlock()
        if expired { report(message: nil, generation: currentGeneration) }
        return image
    }

    // Validate again when delivering: a completed old-camera request must not
    // unlock the shutter after a newer configuration has invalidated its mask.
    private func report(message: String?, generation expected: UInt) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let current = self.generation == expected
            let currentlyReady = self.enabled && self.mask != nil &&
                ProcessInfo.processInfo.systemUptime - self.maskSourceTime <= Self.maximumMaskAge
            self.lock.unlock()
            guard current else { return }
            // Camera expiry and worker completion can race. Deliver the current
            // state rather than letting a delayed false event hide a fresh mask.
            self.onStatus(currentlyReady, message)
        }
    }

    /// Stills get their own accurate mask from the normalized full-resolution
    /// photo, never a stretched preview mask from a different crop.
    static func photoMask(for source: CIImage) throws -> CIImage {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(ciImage: source, orientation: .up, options: [:]).perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else {
            throw NSError(domain: "StoryEditorPro.Background", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Person segmentation returned no photo mask."])
        }
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }
}

enum PersonBackgroundCompositor {
    static func isValidStyle(_ style: Int) -> Bool { (0...4).contains(style) }

    static func alignedMask(_ mask: CIImage, to extent: CGRect) -> CIImage? {
        guard mask.extent.width > 0, mask.extent.height > 0,
              extent.width > 0, extent.height > 0 else { return nil }
        return mask
            .transformed(by: CGAffineTransform(translationX: -mask.extent.minX, y: -mask.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                              y: extent.height / mask.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    static func composite(source: CIImage, mask: CIImage, style: Int, scene: CIImage? = nil) -> CIImage {
        guard style != 0, isValidStyle(style), let aligned = alignedMask(mask, to: source.extent) else { return source }
        let extent = source.extent
        let background: CIImage
        if let scene = scene, style == 2 || style == 3 {
            let scale = max(extent.width / scene.extent.width, extent.height / scene.extent.height)
            let scaled = scene.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            background = scaled.transformed(by: CGAffineTransform(
                translationX: extent.midX - scaled.extent.midX,
                y: extent.midY - scaled.extent.midY)).cropped(to: extent)
        } else if style == 4 {
            let radius = min(28, max(10, min(extent.width, extent.height) * 0.024))
            background = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: extent)
        } else {
            let top: CIColor, bottom: CIColor
            switch style {
            case 1:
                top = CIColor(red: 0.90, green: 0.88, blue: 0.85)
                bottom = CIColor(red: 0.46, green: 0.50, blue: 0.57)
            case 2:
                top = CIColor(red: 0.99, green: 0.78, blue: 0.62)
                bottom = CIColor(red: 0.49, green: 0.24, blue: 0.38)
            default:
                top = CIColor(red: 0.10, green: 0.17, blue: 0.30)
                bottom = CIColor(red: 0.015, green: 0.025, blue: 0.07)
            }
            background = CIFilter(name: "CISmoothLinearGradient", parameters: [
                "inputPoint0": CIVector(x: extent.midX, y: extent.maxY),
                "inputPoint1": CIVector(x: extent.midX, y: extent.minY),
                "inputColor0": top, "inputColor1": bottom
            ])?.outputImage?.cropped(to: extent) ?? CIImage(color: bottom).cropped(to: extent)
        }
        // Vision's mask is a linear confidence channel. Keep its white person
        // pixels sharp and replace only its black background pixels.
        return source.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: aligned
        ]).cropped(to: extent)
    }
}
