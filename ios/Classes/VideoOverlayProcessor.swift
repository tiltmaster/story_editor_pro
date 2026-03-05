import Foundation
import AVFoundation
import UIKit
import CoreImage

class VideoOverlayProcessor {
    private let buildMarker = "STORY_EDITOR_PRO_IOS_EXPORTER_2026_03_06_J"

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
            // When a filter is requested use a single CI pass: apply filter + composite
            // overlay in the AVVideoComposition block. This avoids the two-pass approach
            // whose intermediate file has uncertain orientation metadata (Apple's block-based
            // CI compositor bakes the rotation into pixels but the output track may still
            // carry the original preferredTransform, causing a double-rotation → black video).
            if filterPreset != "none" && filterStrength > 0.01 {
                self.exportSinglePassFilteredWithOverlay(
                    videoURL: videoURL,
                    overlayImagePath: overlayImagePath,
                    outputURL: outputURL,
                    outputPath: outputPath,
                    mirrorHorizontally: mirrorHorizontally,
                    filterPreset: filterPreset,
                    filterStrength: filterStrength,
                    completion: completion
                )
                return
            }

            let asset = AVAsset(url: videoURL)
            let inputDuration = CMTimeGetSeconds(asset.duration)
            let inputVideoTracks = asset.tracks(withMediaType: .video).count
            let inputAudioTracks = asset.tracks(withMediaType: .audio).count
            print("VideoOverlayProcessor: Input duration=\(inputDuration)s, videoTracks=\(inputVideoTracks), audioTracks=\(inputAudioTracks)")

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

            // 4. Calculate render size from the actual source track (filtered or original).
            // When a filter is applied, AVVideoComposition(asset:applyingCIFiltersWithHandler:)
            // bakes the rotation into pixels and outputs a portrait naturalSize with identity
            // preferredTransform. Using videoTrack here handles both cases correctly:
            //   - no filter: original track (e.g. 1920x1080, 90° rotation) → makeVideoTransform rotates → portrait ✓
            //   - filtered:  filtered track (e.g. 1080x1920, identity)      → makeVideoTransform identity → portrait ✓
            let renderSize: CGSize
            if let outputWidth = outputWidth, let outputHeight = outputHeight, outputWidth > 0, outputHeight > 0 {
                renderSize = CGSize(width: outputWidth, height: outputHeight)
            } else {
                renderSize = self.calculateRenderSize(track: videoTrack)
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
                track: videoTrack,
                renderSize: renderSize
            )
            print("VideoOverlayProcessor: source naturalSize=\(videoTrack.naturalSize), preferredTransform=\(videoTrack.preferredTransform)")
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

    /// Single-pass export: CI filter + overlay composited together.
    /// AVVideoComposition(asset:applyingCIFiltersWithHandler:) always provides a
    /// pre-oriented sourceImage, so there is no orientation ambiguity.
    private func exportSinglePassFilteredWithOverlay(
        videoURL: URL,
        overlayImagePath: String,
        outputURL: URL,
        outputPath: String,
        mirrorHorizontally: Bool,
        filterPreset: String,
        filterStrength: Double,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard let overlayUIImage = UIImage(contentsOfFile: overlayImagePath),
              let overlayCGImage = overlayUIImage.cgImage else {
            DispatchQueue.main.async { completion(nil, "Failed to load overlay image from path: \(overlayImagePath)") }
            return
        }

        let overlayCI = CIImage(cgImage: overlayCGImage)
        let asset = AVAsset(url: videoURL)

        // Use sRGB (gamma-encoded) as the working colour space so that CIColorMatrix
        // operates on the same gamma-encoded values that Flutter's ColorFilter.matrix
        // and the Android GLSL shader receive. CoreImage's default is linear light,
        // which causes the same matrix to produce visually different results.
        let workingCS = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: workingCS,
        ])

        let ciComposition = AVVideoComposition(asset: asset) { [weak self] request in
            guard let self = self else { return }
            let sourceExtent = request.sourceImage.extent

            // Optionally mirror the video frame before filtering
            var source: CIImage = request.sourceImage
            if mirrorHorizontally {
                source = source
                    .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                    .transformed(by: CGAffineTransform(translationX: sourceExtent.width, y: 0))
            }

            // Apply CI filter
            let filtered = self.applyFilter(to: source.clampedToExtent(), preset: filterPreset, strength: filterStrength)
                .cropped(to: sourceExtent)

            // Scale overlay to cover source extent (aspect fill, centered)
            let scale = max(sourceExtent.width / overlayCI.extent.width,
                            sourceExtent.height / overlayCI.extent.height)
            var scaledOverlay = overlayCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = sourceExtent.midX - scaledOverlay.extent.midX
            let dy = sourceExtent.midY - scaledOverlay.extent.midY
            scaledOverlay = scaledOverlay.transformed(by: CGAffineTransform(translationX: dx, y: dy))

            // Composite overlay on top of filtered video, crop to frame
            let composited = scaledOverlay.composited(over: filtered).cropped(to: sourceExtent)
            request.finish(with: composited, context: ciContext)
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            DispatchQueue.main.async { completion(nil, "Failed to create AVAssetExportSession for filter+overlay.") }
            return
        }

        exporter.videoComposition = ciComposition
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                if exporter.status == .completed {
                    do {
                        let attrs = try FileManager.default.attributesOfItem(atPath: outputPath)
                        let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
                        let outAsset = AVAsset(url: outputURL)
                        let outDuration = CMTimeGetSeconds(outAsset.duration)
                        let outVideoTracks = outAsset.tracks(withMediaType: .video).count
                        print("VideoOverlayProcessor: SinglePass output size=\(fileSize) bytes, duration=\(outDuration)s, videoTracks=\(outVideoTracks)")
                        if outVideoTracks == 0 || outDuration <= 0.05 || fileSize < 1024 {
                            let diag = "Invalid output (size=\(fileSize), duration=\(outDuration), tracks=\(outVideoTracks))"
                            completion(nil, "Export produced invalid video: \(diag)")
                            return
                        }
                    } catch {
                        print("VideoOverlayProcessor: Could not inspect output file: \(error)")
                    }
                    print("VideoOverlayProcessor: SinglePass export completed successfully")
                    completion(outputPath, nil)
                } else {
                    let msg = exporter.error?.localizedDescription ?? "unknown"
                    print("VideoOverlayProcessor: SinglePass export failed: \(msg)")
                    completion(nil, "AVAssetExportSession (filter+overlay) failed: \(msg)")
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
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let composition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage.clampedToExtent()
            let filtered = self.applyFilter(to: source, preset: preset, strength: strength)
            request.finish(with: filtered.cropped(to: request.sourceImage.extent), context: ciContext)
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
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

    /// Applies a colour filter using the exact same 5×4 matrix that Flutter's
    /// ColorFilter.matrix() produces. This guarantees the exported video is
    /// pixel-accurate to what the user saw in the editor preview.
    ///
    /// Flutter formula (0–255 space, same additive bias for every channel):
    ///   bOffset = brightness × 255 + (1 − contrast) × 128
    ///   out_R = r0·R + r1·G + r2·B + bOffset   (likewise for G and B rows)
    ///
    /// CIColorMatrix works in 0–1 normalised space, so the bias becomes:
    ///   bias = brightness + (1 − contrast) × 0.5
    private func applyFilter(to image: CIImage, preset: String, strength: Double) -> CIImage {
        let t = max(0.0, min(1.0, strength))
        if t < 0.001 { return image }
        let p = resolveFilterParams(preset: preset, strength: t)

        let c = p.contrast
        let s = p.saturation
        // BT.709 luminance weights — same as Flutter
        let rLum = 0.2126, gLum = 0.7152, bLum = 0.0722
        let sr = (1.0 - s) * rLum
        let sg = (1.0 - s) * gLum
        let sb = (1.0 - s) * bLum

        let r0 = (sr + s) * c * p.red;   let r1 = sg * c * p.red;   let r2 = sb * c * p.red
        let g0 = sr * c * p.green;        let g1 = (sg + s) * c * p.green; let g2 = sb * c * p.green
        let b0 = sr * c * p.blue;         let b1 = sg * c * p.blue; let b2 = (sb + s) * c * p.blue
        let bias = p.brightness + (1.0 - c) * 0.5

        guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
        matrix.setValue(image,                                   forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: r0, y: r1, z: r2, w: 0),   forKey: "inputRVector")
        matrix.setValue(CIVector(x: g0, y: g1, z: g2, w: 0),   forKey: "inputGVector")
        matrix.setValue(CIVector(x: b0, y: b1, z: b2, w: 0),   forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0,  y: 0,  z: 0,  w: 1),   forKey: "inputAVector")
        matrix.setValue(CIVector(x: bias, y: bias, z: bias, w: 0), forKey: "inputBiasVector")
        var output = matrix.outputImage ?? image

        // S-curve tone mapping via CIToneCurve.
        // Control points pull shadows down and lift highlights, matching the
        // GLSL smoothstep pass on Android and the contrast approximation in Flutter.
        // d = sCurve × 0.094 maps exactly to the GLSL smoothstep shadow drop.
        if p.sCurve > 0.001,
           let toneCurve = CIFilter(name: "CIToneCurve") {
            let d = p.sCurve * 0.094
            toneCurve.setValue(output,                                forKey: kCIInputImageKey)
            toneCurve.setValue(CIVector(x: 0.0,  y: 0.0),           forKey: "inputPoint0")
            toneCurve.setValue(CIVector(x: 0.25, y: 0.25 - d),      forKey: "inputPoint1")
            toneCurve.setValue(CIVector(x: 0.5,  y: 0.5),           forKey: "inputPoint2")
            toneCurve.setValue(CIVector(x: 0.75, y: 0.75 + d),      forKey: "inputPoint3")
            toneCurve.setValue(CIVector(x: 1.0,  y: 1.0),           forKey: "inputPoint4")
            if let result = toneCurve.outputImage { output = result }
        }

        // CIVignette intensity is calibrated to be visually equivalent to the
        // Flutter RadialGradient / Android GLSL vignette at the same preset.
        // CIVignette uses a different internal curve, so intensity ≈ vigAmount × 1.78.
        if p.vignette > 0.001,
           let vignette = CIFilter(name: "CIVignette") {
            let extent = output.extent
            let radius = min(extent.width, extent.height) * 0.45
            vignette.setValue(output, forKey: kCIInputImageKey)
            vignette.setValue(p.vignette, forKey: kCIInputIntensityKey)
            vignette.setValue(radius,     forKey: kCIInputRadiusKey)
            if let result = vignette.outputImage { output = result }
        }

        return output
    }

    private func resolveFilterParams(preset: String, strength: Double) -> (brightness: Double, contrast: Double, saturation: Double, red: Double, green: Double, blue: Double, vignette: Double, sCurve: Double, warpMode: Int, warpAmount: Double) {
        let neutral = (brightness: 0.0, contrast: 1.0, saturation: 1.0, red: 1.0, green: 1.0, blue: 1.0, vignette: 0.0, sCurve: 0.0, warpMode: 0, warpAmount: 0.0)
        let target: (brightness: Double, contrast: Double, saturation: Double, red: Double, green: Double, blue: Double, vignette: Double, sCurve: Double, warpMode: Int, warpAmount: Double)

        // Tuple order: (brightness, contrast, saturation, red, green, blue, vignette, sCurve, warpMode, warpAmount)
        // vignette: iOS CIVignette intensity, calibrated to match Android GLSL visually (≈ androidValue × 1.78 for vignette-heavy presets)
        // sCurve: 0–1 strength for CIToneCurve; d = sCurve × 0.094 is the shadow/highlight pull
        switch preset {
        case "vivid":       target = (0.02,  1.25, 1.50, 1.04, 1.02, 1.02, 0.0,  0.45, 0, 0.0)
        case "warm":        target = (0.02,  1.10, 1.15, 1.25, 1.05, 0.78, 0.0,  0.25, 0, 0.0)
        case "cool":        target = (0.0,   1.08, 1.10, 0.80, 1.02, 1.28, 0.0,  0.25, 0, 0.0)
        case "sunset":      target = (0.03,  1.15, 1.30, 1.28, 1.02, 0.75, 0.0,  0.40, 0, 0.0)
        case "fade":        target = (0.08,  0.82, 0.68, 1.0,  1.0,  1.0,  0.0,  0.0,  0, 0.0)
        case "mono":        target = (0.0,   1.10, 0.0,  1.0,  1.0,  1.0,  0.0,  0.40, 0, 0.0)
        case "noir":        target = (-0.04, 1.45, 0.0,  1.0,  1.0,  1.0,  0.0,  0.65, 0, 0.0)
        case "dream":       target = (0.07,  0.88, 1.18, 1.10, 1.02, 1.08, 0.0,  0.0,  0, 0.0)
        case "vignette":    target = (-0.02, 1.15, 1.05, 1.01, 1.0,  0.99, 1.1,  0.25, 0, 0.0)
        case "retro2044":   target = (0.02,  1.22, 1.42, 1.20, 0.95, 1.18, 0.42, 0.45, 0, 0.0)
        case "cinematic":   target = (-0.02, 1.30, 0.72, 1.06, 1.01, 0.90, 0.65, 0.65, 0, 0.0)
        case "tealorange":  target = (0.01,  1.22, 1.18, 1.20, 1.01, 1.18, 0.32, 0.45, 0, 0.0)
        case "portraitpop": target = (0.03,  1.18, 1.15, 1.14, 1.03, 0.92, 0.16, 0.30, 0, 0.0)
        case "nightneon":   target = (-0.03, 1.38, 1.38, 0.94, 1.10, 1.28, 0.40, 0.60, 0, 0.0)
        case "productcrisp":target = (0.01,  1.28, 1.22, 1.04, 1.04, 1.04, 0.08, 0.45, 0, 0.0)
        case "filmicfade":  target = (0.02,  1.05, 0.72, 1.06, 1.01, 0.90, 0.52, 0.25, 0, 0.0)
        case "pastelmist":  target = (0.06,  0.88, 0.88, 1.06, 1.02, 1.08, 0.22, 0.0,  0, 0.0)
        default:            target = neutral
        }

        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            a + (b - a) * t
        }

        return (
            brightness: lerp(neutral.brightness, target.brightness, strength),
            contrast:   lerp(neutral.contrast,   target.contrast,   strength),
            saturation: lerp(neutral.saturation, target.saturation, strength),
            red:        lerp(neutral.red,        target.red,        strength),
            green:      lerp(neutral.green,      target.green,      strength),
            blue:       lerp(neutral.blue,       target.blue,       strength),
            vignette:   lerp(neutral.vignette,   target.vignette,   strength),
            sCurve:     lerp(neutral.sCurve,     target.sCurve,     strength),
            warpMode:   target.warpMode,
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
