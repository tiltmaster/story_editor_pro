import ImageIO
import AVFoundation
import CoreImage
import Foundation

/// At most one video frame decode is queued; the camera receives the last
/// completed frame immediately. Background-video audio is intentionally muted.
final class CustomBackgroundSource {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "story_editor_pro.custom_background", qos: .userInitiated)
    private var generation = 0
    private var generator: AVAssetImageGenerator?
    private var image: CIImage?
    private var duration = 0.0
    private var started = ProcessInfo.processInfo.systemUptime
    private var busy = false
    private var lastTime = -1.0

    func select(path: String, video: Bool) {
        lock.lock(); generation += 1; let expected = generation
        image = nil; generator = nil; duration = 0; busy = true
        started = ProcessInfo.processInfo.systemUptime; lastTime = -1
        lock.unlock()
        queue.async { [weak self] in
            guard let self = self else { return }
            let url = URL(fileURLWithPath: path)
            var result: CIImage?
            var decoder: AVAssetImageGenerator?
            var length = 0.0
            if video {
                let asset = AVURLAsset(url: url)
                length = CMTimeGetSeconds(asset.duration)
                let reader = AVAssetImageGenerator(asset: asset)
                reader.appliesPreferredTrackTransform = true
                reader.requestedTimeToleranceBefore = .zero
                reader.requestedTimeToleranceAfter = .zero
                reader.maximumSize = CGSize(width: 720, height: 1280)
                if let frame = try? reader.copyCGImage(at: .zero, actualTime: nil) { result = CIImage(cgImage: frame) }
                decoder = reader
            } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1920
                ] as CFDictionary) { result = CIImage(cgImage: thumbnail) }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.generation == expected else { return }
            self.image = result; self.generator = decoder
            self.duration = length.isFinite ? length : 0; self.busy = false
        }
    }

    func restart() {
        lock.lock(); started = ProcessInfo.processInfo.systemUptime; lastTime = -1
        if generator != nil { generation += 1; busy = false; image = nil }; lock.unlock()
    }

    func frame() -> CIImage? {
        lock.lock()
        let current = image
        let time = duration > 0 ? (ProcessInfo.processInfo.systemUptime - started).truncatingRemainder(dividingBy: duration) : 0
        guard let reader = generator, !busy, abs(time - lastTime) >= 0.1 else { lock.unlock(); return current }
        busy = true; lastTime = time; let expected = generation
        lock.unlock()
        queue.async { [weak self] in
            let frame = try? reader.copyCGImage(at: CMTime(seconds: max(0, time), preferredTimescale: 600), actualTime: nil)
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.generation == expected else { return }
            if let frame = frame { self.image = CIImage(cgImage: frame) }
            self.busy = false
        }
        return current
    }
}
