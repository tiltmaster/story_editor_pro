import Foundation
import AVFoundation
import UIKit
import CoreImage

class VideoOverlayProcessor {
    private let buildMarker = "STORY_EDITOR_PRO_IOS_EXPORTER_2026_03_04_D"

    /// Compose overlay PNG on top of video and export as new MP4
    func exportVideoWithOverlay(
        videoPath: String,
        overlayImagePath: String,
        outputPath: String,
        mirrorHorizontally: Bool = false,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil,
        filterPreset: String = "none",
        filterStrength: Double = 1.0,
        completion: @escaping (String?, String?) -> Void
    ) {
        print("VideoOverlayProcessor: BuildMarker=\(buildMarker)")
        let videoURL = URL(fileURLWithPath: videoPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        // Remove existing output
        try? FileManager.default.removeItem(at: outputURL)

        DispatchQueue.global(qos: .userInitiated).async {
            var sourceVideoURL = videoURL
            var tempFilteredURL: URL?

            if filterPreset != "none" && filterStrength > 0.01 {
                let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let filteredURL = tempDir.appendingPathComponent("filtered_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
                let semaphore = DispatchSemaphore(value: 0)
                var filterError: String?

                self.exportFilteredVideo(
                    inputURL: videoURL,
                    outputURL: filteredURL,
                    preset: filterPreset,
                    strength: filterStrength
                ) { success, message in
                    if success {
                        sourceVideoURL = filteredURL
                        tempFilteredURL = filteredURL
                    } else {
                        filterError = message ?? "Failed to apply filter"
                    }
                    semaphore.signal()
                }

                semaphore.wait()
                if let filterError = filterError {
                    DispatchQueue.main.async { completion(nil, filterError) }
                    return
                }
            }

            let asset = AVAsset(url: sourceVideoURL)
            let inputDuration = CMTimeGetSeconds(asset.duration)
            let inputVideoTracks = asset.tracks(withMediaType: .video).count
            let inputAudioTracks = asset.tracks(withMediaType: .audio).count
            print("VideoOverlayProcessor: Input duration=\(inputDuration)s, videoTracks=\(inputVideoTracks), audioTracks=\(inputAudioTracks), filtered=\(tempFilteredURL != nil)")

            // Always load the ORIGINAL video track for orientation/transform calculations.
            // exportFilteredVideo (AVVideoComposition block-based) pre-orients pixel content
            // but the output track still carries the original preferredTransform metadata,
            // which would cause makeVideoTransform to double-rotate → off-canvas → black video.
            let originalAsset = AVAsset(url: videoURL)
            guard let orientationTrack = originalAsset.tracks(withMediaType: .video).first else {
                print("VideoOverlayProcessor: No video track found in original file")
                DispatchQueue.main.async { completion(nil, "No video track found in original file.") }
                return
            }

            // 1. Create mutable composition
            let composition = AVMutableComposition()

            // 2. Add video track
            guard let videoTrack = asset.tracks(withMediaType: .video).first,
                  let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                print("VideoOverlayProcessor: No video track found")
                DispatchQueue.main.async { completion(nil, "No video track found in input file.") }
                return
            }

            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)

            do {
                try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
            } catch {
                print("VideoOverlayProcessor: Failed to insert video track: \(error)")
                DispatchQueue.main.async { completion(nil, "Failed to insert video track: \(error.localizedDescription)") }
                return
            }

            // 3. Add audio track (if exists)
            if let audioTrack = asset.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                 withMediaType: .audio,
                 preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            }

            // 4. Calculate render size using original track (not filtered) to avoid
            //    orientation metadata mismatch after the filter pre-pass.
            let renderSize: CGSize
            if let outputWidth = outputWidth, let outputHeight = outputHeight, outputWidth > 0, outputHeight > 0 {
                renderSize = CGSize(width: outputWidth, height: outputHeight)
            } else {
                renderSize = self.calculateRenderSize(track: orientationTrack)
            }

            // 5. Create video composition
            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.renderSize = renderSize

            // 6. Create layer instruction for proper video orientation
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionVideoTrack
            )
            var transform = self.makeVideoTransform(
                track: orientationTrack,
                renderSize: renderSize
            )
            print("VideoOverlayProcessor: source naturalSize=\(orientationTrack.naturalSize), preferredTransform=\(orientationTrack.preferredTransform)")
            print("VideoOverlayProcessor: renderSize=\(renderSize), computedTransform=\(transform)")
            if mirrorHorizontally {
                let mirror = CGAffineTransform(translationX: renderSize.width, y: 0).scaledBy(x: -1, y: 1)
                transform = transform.concatenating(mirror)
            }
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]

            // 7. Create overlay layer from PNG
            guard let overlayImage = UIImage(contentsOfFile: overlayImagePath) else {
                print("VideoOverlayProcessor: Failed to load overlay image")
                DispatchQueue.main.async { completion(nil, "Failed to load overlay image from path: \(overlayImagePath)") }
                return
            }

            let parentLayer = CALayer()
            let videoLayer = CALayer()
            let overlayLayer = CALayer()

            parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.masksToBounds = true
            // AVVideoCompositionCoreAnimationTool composites in AVFoundation's y-up coordinate system.
            // isGeometryFlipped = true on the parent makes the CALayer coordinate system match,
            // which is required to prevent video frames from being rendered off-canvas (black video).
            parentLayer.isGeometryFlipped = true
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            overlayLayer.contents = overlayImage.cgImage
            // isGeometryFlipped = true on the overlay counteracts the parent flip so that the
            // UIKit PNG image (y-down / top-left origin) appears in its correct orientation.
            overlayLayer.isGeometryFlipped = true

            // Scale overlay to cover renderSize while preserving aspect ratio (center crop)
            let overlayAspect = overlayImage.size.width / overlayImage.size.height
            let renderAspect = renderSize.width / renderSize.height
            let overlayFrame: CGRect
            if overlayAspect > renderAspect {
                // Overlay is wider: match height, crop width
                let scaledWidth = renderSize.height * overlayAspect
                let offsetX = (renderSize.width - scaledWidth) / 2
                overlayFrame = CGRect(x: offsetX, y: 0, width: scaledWidth, height: renderSize.height)
            } else {
                // Overlay is taller: match width, crop height
                let scaledHeight = renderSize.width / overlayAspect
                let offsetY = (renderSize.height - scaledHeight) / 2
                overlayFrame = CGRect(x: 0, y: offsetY, width: renderSize.width, height: scaledHeight)
            }
            overlayLayer.frame = overlayFrame
            overlayLayer.contentsGravity = .resize

            parentLayer.addSublayer(videoLayer)
            parentLayer.addSublayer(overlayLayer)

            // 8. Apply animation tool
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )

            // 9. Export
            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                print("VideoOverlayProcessor: Failed to create export session")
                DispatchQueue.main.async { completion(nil, "Failed to create AVAssetExportSession.") }
                return
            }

            exporter.videoComposition = videoComposition
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true

            exporter.exportAsynchronously {
                DispatchQueue.main.async {
                    if let tempFilteredURL = tempFilteredURL {
                        try? FileManager.default.removeItem(at: tempFilteredURL)
                    }
                    if exporter.status == .completed {
                        do {
                            let attrs = try FileManager.default.attributesOfItem(atPath: outputPath)
                            let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
                            let outAsset = AVAsset(url: outputURL)
                            let outDuration = CMTimeGetSeconds(outAsset.duration)
                            let outVideoTracks = outAsset.tracks(withMediaType: .video).count
                            print("VideoOverlayProcessor: Output size=\(fileSize) bytes, duration=\(outDuration)s, videoTracks=\(outVideoTracks)")

                            if outVideoTracks == 0 || outDuration <= 0.05 || fileSize < 1024 {
                                let diag = "Invalid output (size=\(fileSize), duration=\(outDuration), tracks=\(outVideoTracks))"
                                print("VideoOverlayProcessor: Export validation failed: \(diag)")
                                completion(nil, "Export produced invalid video: \(diag)")
                                return
                            }
                        } catch {
                            print("VideoOverlayProcessor: Could not inspect output file: \(error)")
                        }
                        print("VideoOverlayProcessor: Export completed successfully")
                        completion(outputPath, nil)
                    } else {
                        let message = exporter.error?.localizedDescription ?? "unknown"
                        print("VideoOverlayProcessor: Export failed: \(message)")
                        completion(nil, "AVAssetExportSession failed: \(message)")
                    }
                }
            }
        }
    }

    private func exportFilteredVideo(
        inputURL: URL,
        outputURL: URL,
        preset: String,
        strength: Double,
        completion: @escaping (Bool, String?) -> Void
    ) {
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVAsset(url: inputURL)
        let composition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage.clampedToExtent()
            let filtered = self.applyFilter(to: source, preset: preset, strength: strength)
            request.finish(with: filtered.cropped(to: request.sourceImage.extent), context: nil)
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(false, "Failed to create filter export session.")
            return
        }

        exporter.videoComposition = composition
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.exportAsynchronously {
            if exporter.status == .completed {
                completion(true, nil)
            } else {
                completion(false, "Filter export failed: \(exporter.error?.localizedDescription ?? "unknown")")
            }
        }
    }

    private func applyFilter(to image: CIImage, preset: String, strength: Double) -> CIImage {
        let t = max(0.0, min(1.0, strength))
        let p = self.resolveFilterParams(preset: preset, strength: t)

        var output = image
        let extent = output.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let radius = min(extent.width, extent.height) * 0.45

        if let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(output, forKey: kCIInputImageKey)
            controls.setValue(p.saturation, forKey: kCIInputSaturationKey)
            controls.setValue(p.brightness, forKey: kCIInputBrightnessKey)
            controls.setValue(p.contrast, forKey: kCIInputContrastKey)
            if let result = controls.outputImage {
                output = result
            }
        }

        if let matrix = CIFilter(name: "CIColorMatrix") {
            matrix.setValue(output, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: p.red, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: p.green, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: p.blue, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let result = matrix.outputImage {
                output = result
            }
        }

        if p.vignette > 0.001, let vignette = CIFilter(name: "CIVignette") {
            vignette.setValue(output, forKey: kCIInputImageKey)
            vignette.setValue(p.vignette, forKey: kCIInputIntensityKey)
            vignette.setValue(radius * 0.9, forKey: kCIInputRadiusKey)
            if let result = vignette.outputImage {
                output = result
            }
        }

        if p.warpMode == 1, let bulge = CIFilter(name: "CIBumpDistortion") {
            bulge.setValue(output, forKey: kCIInputImageKey)
            bulge.setValue(CIVector(cgPoint: center), forKey: kCIInputCenterKey)
            bulge.setValue(radius, forKey: kCIInputRadiusKey)
            bulge.setValue(p.warpAmount, forKey: kCIInputScaleKey)
            if let result = bulge.outputImage {
                output = result
            }
        } else if p.warpMode == 2, let twirl = CIFilter(name: "CITwirlDistortion") {
            twirl.setValue(output, forKey: kCIInputImageKey)
            twirl.setValue(CIVector(cgPoint: center), forKey: kCIInputCenterKey)
            twirl.setValue(radius, forKey: kCIInputRadiusKey)
            twirl.setValue(p.warpAmount, forKey: kCIInputAngleKey)
            if let result = twirl.outputImage {
                output = result
            }
        }

        if preset == "retro2044", let hue = CIFilter(name: "CIHueAdjust") {
            hue.setValue(output, forKey: kCIInputImageKey)
            hue.setValue(NSNumber(value: 0.18 * t), forKey: kCIInputAngleKey)
            if let result = hue.outputImage {
                output = result
            }
        }

        if preset == "productcrisp", let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(output, forKey: kCIInputImageKey)
            sharpen.setValue(NSNumber(value: 0.35 * t), forKey: kCIInputSharpnessKey)
            if let result = sharpen.outputImage {
                output = result
            }
        }

        if preset == "nightneon", let hue = CIFilter(name: "CIHueAdjust") {
            hue.setValue(output, forKey: kCIInputImageKey)
            hue.setValue(NSNumber(value: -0.12 * t), forKey: kCIInputAngleKey)
            if let result = hue.outputImage {
                output = result
            }
        }

        return output
    }

    private func resolveFilterParams(preset: String, strength: Double) -> (brightness: Double, contrast: Double, saturation: Double, red: Double, green: Double, blue: Double, vignette: Double, warpMode: Int, warpAmount: Double) {
        let neutral = (brightness: 0.0, contrast: 1.0, saturation: 1.0, red: 1.0, green: 1.0, blue: 1.0, vignette: 0.0, warpMode: 0, warpAmount: 0.0)
        let target: (brightness: Double, contrast: Double, saturation: Double, red: Double, green: Double, blue: Double, vignette: Double, warpMode: Int, warpAmount: Double)

        switch preset {
        case "vivid":
            target = (0.02, 1.15, 1.22, 1.02, 1.02, 1.02, 0.0, 0, 0.0)
        case "warm":
            target = (0.015, 1.08, 1.08, 1.11, 1.02, 0.92, 0.0, 0, 0.0)
        case "cool":
            target = (0.0, 1.06, 1.05, 0.94, 1.01, 1.11, 0.0, 0, 0.0)
        case "sunset":
            target = (0.03, 1.10, 1.16, 1.14, 1.0, 0.9, 0.0, 0, 0.0)
        case "fade":
            target = (0.03, 0.88, 0.86, 1.0, 1.0, 1.0, 0.0, 0, 0.0)
        case "mono":
            target = (0.01, 1.04, 0.0, 1.0, 1.0, 1.0, 0.0, 0, 0.0)
        case "noir":
            target = (-0.02, 1.22, 0.18, 1.0, 1.0, 1.0, 0.0, 0, 0.0)
        case "dream":
            target = (0.04, 0.94, 1.08, 1.06, 1.0, 1.05, 0.0, 0, 0.0)
        case "vignette":
            target = (-0.01, 1.12, 1.02, 1.01, 1.0, 0.99, 1.1, 0, 0.0)
        case "retro2044":
            target = (0.02, 1.18, 1.28, 1.12, 0.98, 1.14, 0.42, 0, 0.0)
        case "cinematic":
            target = (-0.01, 1.16, 0.92, 1.03, 1.0, 0.96, 0.65, 0, 0.0)
        case "tealorange":
            target = (0.01, 1.20, 1.08, 1.12, 1.0, 1.12, 0.32, 0, 0.0)
        case "portraitpop":
            target = (0.03, 1.12, 1.08, 1.08, 1.02, 0.96, 0.16, 0, 0.0)
        case "nightneon":
            target = (-0.02, 1.30, 1.24, 0.98, 1.08, 1.20, 0.40, 0, 0.0)
        case "productcrisp":
            target = (0.01, 1.25, 1.12, 1.03, 1.03, 1.03, 0.08, 0, 0.0)
        case "filmicfade":
            target = (0.005, 1.06, 0.78, 1.04, 1.0, 0.93, 0.52, 0, 0.0)
        case "pastelmist":
            target = (0.045, 0.86, 0.92, 1.04, 1.01, 1.06, 0.22, 0, 0.0)
        default:
            target = neutral
        }

        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            a + (b - a) * t
        }

        return (
            brightness: lerp(neutral.brightness, target.brightness, strength),
            contrast: lerp(neutral.contrast, target.contrast, strength),
            saturation: lerp(neutral.saturation, target.saturation, strength),
            red: lerp(neutral.red, target.red, strength),
            green: lerp(neutral.green, target.green, strength),
            blue: lerp(neutral.blue, target.blue, strength),
            vignette: lerp(neutral.vignette, target.vignette, strength),
            warpMode: target.warpMode,
            warpAmount: lerp(neutral.warpAmount, target.warpAmount, strength)
        )
    }

    /// Calculate proper render size from video track (handles rotation)
    private func calculateRenderSize(track: AVAssetTrack) -> CGSize {
        let transform = track.preferredTransform
        let size = track.naturalSize

        // Determine rotation angle from the transform matrix
        let angle = atan2(transform.b, transform.a)
        let degrees = abs(angle * 180.0 / .pi)

        // If video is rotated 90 or 270 degrees, swap width/height
        if abs(degrees - 90) < 1 || abs(degrees - 270) < 1 {
            return CGSize(width: size.height, height: size.width)
        }
        return size
    }

    /// Build a stable transform that:
    /// 1) applies track orientation,
    /// 2) normalizes to positive origin,
    /// 3) scales with aspect-fill into renderSize,
    /// 4) centers content in output frame.
    private func makeVideoTransform(track: AVAssetTrack, renderSize: CGSize) -> CGAffineTransform {
        let naturalRect = CGRect(origin: .zero, size: track.naturalSize)
        var preferred = track.preferredTransform
        var orientedRect = naturalRect.applying(preferred)

        // Normalize origin to (0,0) to avoid off-canvas rendering.
        preferred = preferred.translatedBy(x: -orientedRect.origin.x, y: -orientedRect.origin.y)
        orientedRect = naturalRect.applying(preferred)

        let orientedSize = CGSize(
            width: abs(orientedRect.width),
            height: abs(orientedRect.height)
        )

        guard orientedSize.width > 0, orientedSize.height > 0 else {
            return preferred
        }

        let scale = max(
            renderSize.width / orientedSize.width,
            renderSize.height / orientedSize.height
        )
        let scaledWidth = orientedSize.width * scale
        let scaledHeight = orientedSize.height * scale
        let tx = (renderSize.width - scaledWidth) / 2.0
        let ty = (renderSize.height - scaledHeight) / 2.0
        
        // Avoid scaling translation terms, which can push content fully off-canvas
        // on some iOS exports and result in black video with audio-only playback.
        var scaled = preferred
        scaled.a *= scale
        scaled.b *= scale
        scaled.c *= scale
        scaled.d *= scale
        scaled.tx += tx
        scaled.ty += ty
        return scaled
    }
}
