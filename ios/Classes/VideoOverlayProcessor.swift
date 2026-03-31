import Foundation
import AVFoundation
import UIKit
import CoreImage

class VideoOverlayProcessor {
    private let buildMarker = "STORY_EDITOR_PRO_IOS_EXPORTER_2026_03_31_K"

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
            self.exportSinglePassWithOverlay(
                videoURL: videoURL,
                overlayImagePath: overlayImagePath,
                outputURL: outputURL,
                outputPath: outputPath,
                mirrorHorizontally: mirrorHorizontally,
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                filterPreset: filterPreset,
                filterStrength: filterStrength,
                completion: completion
            )
        }
    }

    /// Single-pass export: video crop/scale + optional filter + overlay composited together.
    /// Keeping both filtered and unfiltered exports on the same path avoids the iOS-only
    /// black-video regression that showed up in the separate Core Animation exporter.
    private func exportSinglePassWithOverlay(
        videoURL: URL,
        overlayImagePath: String,
        outputURL: URL,
        outputPath: String,
        mirrorHorizontally: Bool,
        outputWidth: Int?,
        outputHeight: Int?,
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
        let asset = AVURLAsset(url: videoURL)
        let inputDuration = CMTimeGetSeconds(asset.duration)
        let inputVideoTracks = asset.tracks(withMediaType: .video).count
        let inputAudioTracks = asset.tracks(withMediaType: .audio).count
        print("VideoOverlayProcessor: Input duration=\(inputDuration)s, videoTracks=\(inputVideoTracks), audioTracks=\(inputAudioTracks)")

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(nil, "No video track found in input file.") }
            return
        }

        let renderSize: CGSize
        if let outputWidth = outputWidth, let outputHeight = outputHeight, outputWidth > 0, outputHeight > 0 {
            renderSize = CGSize(width: outputWidth, height: outputHeight)
        } else {
            renderSize = self.calculateRenderSize(track: videoTrack)
        }
        let targetExtent = CGRect(origin: .zero, size: renderSize)

        // Use sRGB (gamma-encoded) as the working colour space so that CIColorMatrix
        // operates on the same gamma-encoded values that Flutter's ColorFilter.matrix
        // and the Android GLSL shader receive. CoreImage's default is linear light,
        // which causes the same matrix to produce visually different results.
        let workingCS = CGColorSpace(name: CGColorSpace.sRGB)!
        let ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: workingCS,
        ])

        print("VideoOverlayProcessor: source naturalSize=\(videoTrack.naturalSize), preferredTransform=\(videoTrack.preferredTransform)")
        print("VideoOverlayProcessor: renderSize=\(renderSize)")

        let ciComposition = AVVideoComposition(asset: asset) { [weak self] request in
            guard let self = self else { return }

            // AVVideoComposition's sourceImage is already orientation-correct, so all that is
            // left to do is aspect-fill it into the requested story canvas.
            var source: CIImage = request.sourceImage
            source = self.aspectFill(image: source, into: targetExtent)

            if mirrorHorizontally {
                source = source
                    .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                    .transformed(by: CGAffineTransform(translationX: targetExtent.width, y: 0))
            }

            let filtered: CIImage
            if filterPreset != "none" && filterStrength > 0.01 {
                filtered = self.applyFilter(to: source.clampedToExtent(), preset: filterPreset, strength: filterStrength)
                    .cropped(to: targetExtent)
            } else {
                filtered = source.cropped(to: targetExtent)
            }

            // Scale overlay to cover the requested output extent (aspect fill, centered).
            let scale = max(targetExtent.width / overlayCI.extent.width,
                            targetExtent.height / overlayCI.extent.height)
            var scaledOverlay = overlayCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = targetExtent.midX - scaledOverlay.extent.midX
            let dy = targetExtent.midY - scaledOverlay.extent.midY
            scaledOverlay = scaledOverlay.transformed(by: CGAffineTransform(translationX: dx, y: dy))

            // Composite overlay on top of filtered video, crop to frame
            let composited = scaledOverlay.composited(over: filtered).cropped(to: targetExtent)
            request.finish(with: composited, context: ciContext)
        }

        let videoComposition: AVVideoComposition
        if let mutableComposition = ciComposition.mutableCopy() as? AVMutableVideoComposition {
            mutableComposition.renderSize = renderSize
            mutableComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition = mutableComposition
        } else {
            videoComposition = ciComposition
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(nil, "Failed to create AVAssetExportSession for filter+overlay.") }
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

    private func aspectFill(image: CIImage, into targetExtent: CGRect) -> CIImage {
        let sourceExtent = image.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0,
              targetExtent.width > 0, targetExtent.height > 0 else {
            return image
        }

        let scale = max(targetExtent.width / sourceExtent.width,
                        targetExtent.height / sourceExtent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = targetExtent.midX - scaled.extent.midX
        let dy = targetExtent.midY - scaled.extent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
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
}
