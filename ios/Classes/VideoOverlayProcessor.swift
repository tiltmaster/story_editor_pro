import Foundation
import AVFoundation
import UIKit
import CoreImage
import ImageIO

class VideoOverlayProcessor {
    private let buildMarker = "STORY_EDITOR_PRO_IOS_EXPORTER_2026_03_31_K"
    // One deterministic lightweight pass matching the Flutter and Android
    // color-grade/procedural renderer.
    private let parityFilterKernel: CIKernel? = CIKernel(source: """
        kernel vec4 storyParityFilter(
            sampler image,
            float width, float height,
            float r0, float r1, float r2,
            float g0, float g1, float g2,
            float b0, float b1, float b2,
            float bias, float sCurve, float vignette, float beauty,
            float tape, float bloom, float grainAmount, float halation,
            float splitTone, float chroma
        ) {
            vec2 size = vec2(max(width, 1.0), max(height, 1.0));
            vec2 d = destCoord();
            vec2 uv = d / size;
            // Flutter's fragment origin is top-left while Core Image uses
            // bottom-left. Procedural bands/grain must share Flutter's phase.
            vec2 proceduralUv = vec2(uv.x, 1.0 - uv.y);
            vec2 transformed = samplerTransform(image, d);
            vec4 pixel = sample(image, transformed);
            vec3 source = pixel.rgb;
            if (tape > 0.001 || chroma > 0.001) {
                vec2 virtualFrag = proceduralUv * vec2(720.0, 1280.0);
                float band = virtualFrag.y / 64.0;
                float bandIndex = floor(band);
                float bandMix = smoothstep(0.0, 1.0, fract(band));
                float noiseA = fract(sin(bandIndex * 91.3458) * 47453.5453) - 0.5;
                float noiseB = fract(sin((bandIndex + 1.0) * 91.3458) * 47453.5453) - 0.5;
                float bandNoise = mix(noiseA, noiseB, bandMix);
                float sourceLuma = dot(source, vec3(0.2126, 0.7152, 0.0722));
                source = mix(source, vec3(sourceLuma), 0.08 * tape);
                source += vec3(0.018, 0.002, -0.014) * bandNoise * tape;
                float edge = distance(proceduralUv, vec2(0.5));
                source += vec3(0.012, -0.004, -0.010)
                    * (0.35 + edge) * chroma;
            }

            if (beauty > 0.001) {
                // Edge-aware bilateral smoothing; no full-frame blur or skin whitening.
                vec3 original = pixel.rgb;
                vec3 total = original;
                float totalWeight = 1.0;
                vec3 n0 = sample(image, samplerTransform(image, d + size * vec2(1.0000, 0.0000) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff0 = n0 - original;
                float w0 = exp(-dot(diff0, diff0) * 180.0);
                total += n0 * w0; totalWeight += w0;
                vec3 n1 = sample(image, samplerTransform(image, d + size * vec2(-1.0000, 0.0000) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff1 = n1 - original;
                float w1 = exp(-dot(diff1, diff1) * 180.0);
                total += n1 * w1; totalWeight += w1;
                vec3 n2 = sample(image, samplerTransform(image, d + size * vec2(0.0000, 1.0000) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff2 = n2 - original;
                float w2 = exp(-dot(diff2, diff2) * 180.0);
                total += n2 * w2; totalWeight += w2;
                vec3 n3 = sample(image, samplerTransform(image, d + size * vec2(0.0000, -1.0000) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff3 = n3 - original;
                float w3 = exp(-dot(diff3, diff3) * 180.0);
                total += n3 * w3; totalWeight += w3;
                vec3 n4 = sample(image, samplerTransform(image, d + size * vec2(0.7070, 0.7070) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff4 = n4 - original;
                float w4 = exp(-dot(diff4, diff4) * 180.0);
                total += n4 * w4; totalWeight += w4;
                vec3 n5 = sample(image, samplerTransform(image, d + size * vec2(-0.7070, 0.7070) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff5 = n5 - original;
                float w5 = exp(-dot(diff5, diff5) * 180.0);
                total += n5 * w5; totalWeight += w5;
                vec3 n6 = sample(image, samplerTransform(image, d + size * vec2(0.7070, -0.7070) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff6 = n6 - original;
                float w6 = exp(-dot(diff6, diff6) * 180.0);
                total += n6 * w6; totalWeight += w6;
                vec3 n7 = sample(image, samplerTransform(image, d + size * vec2(-0.7070, -0.7070) * vec2(2.2 / 720.0, 2.2 / 1280.0))).rgb;
                vec3 diff7 = n7 - original;
                float w7 = exp(-dot(diff7, diff7) * 180.0);
                total += n7 * w7; totalWeight += w7;
                float luma = dot(original, vec3(0.2126, 0.7152, 0.0722));
                float cb = 0.5 + dot(original, vec3(-0.168736, -0.331264, 0.5));
                float cr = 0.5 + dot(original, vec3(0.5, -0.418688, -0.081312));
                float skin = smoothstep(0.49, 0.55, cr) * (1.0 - smoothstep(0.67, 0.77, cr))
                    * smoothstep(0.20, 0.30, cb) * (1.0 - smoothstep(0.51, 0.58, cb))
                    * smoothstep(0.015, 0.10, luma);
                source += (total / totalWeight - original) * skin * beauty * 0.82;
            }

            if (bloom > 0.001 || halation > 0.001) {
                float highlight = smoothstep(0.62, 0.94,
                    dot(source, vec3(0.2126, 0.7152, 0.0722)));
                source += source * highlight * (0.16 * bloom);
                source += highlight * vec3(0.055, 0.016, -0.008) * halation;
            }

            vec3 color = vec3(
                dot(vec3(r0, r1, r2), source) + bias,
                dot(vec3(g0, g1, g2), source) + bias,
                dot(vec3(b0, b1, b2), source) + bias
            );
            if (sCurve > 0.001) {
                vec3 curved = color * color * (3.0 - 2.0 * color);
                color = mix(color, curved, sCurve);
            }
            if (abs(splitTone) > 0.001) {
                float amount = abs(splitTone);
                float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
                float shadows = 1.0 - smoothstep(0.12, 0.58, luma);
                float highlights = smoothstep(0.52, 0.92, luma);
                vec3 warmSplit = vec3(-0.022, 0.012, 0.030) * shadows
                    + vec3(0.070, 0.030, -0.018) * highlights;
                vec3 coolSplit = vec3(0.035, -0.010, 0.055) * shadows
                    + vec3(0.008, 0.028, 0.042) * highlights;
                color += (splitTone > 0.0 ? warmSplit : coolSplit) * amount;
            }
            if (grainAmount > 0.001) {
                vec2 grainCell = mod(
                    floor(proceduralUv * vec2(720.0, 1280.0) * 0.72),
                    vec2(64.0)
                );
                float noise = fract(sin(dot(grainCell, vec2(12.9898, 78.233)))
                    * 43758.5453) - 0.5;
                float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
                color += vec3(noise * (0.020 + (1.0 - luma) * 0.018) * grainAmount);
            }
            if (vignette > 0.001) {
                float dist = distance(uv, vec2(0.5));
                color *= 1.0 - smoothstep(0.35, 0.82, dist) * vignette;
            }
            return vec4(clamp(color, 0.0, 1.0), pixel.a);
        }
        """)

    /// Compose overlay PNG on top of video and export as new MP4
    func exportVideoWithOverlay(
        videoPath: String,
        overlayImagePath: String,
        outputPath: String,
        animatedStickers: [[String: Any]] = [],
        mirrorHorizontally: Bool = false,
        outputWidth: Int? = nil,
        outputHeight: Int? = nil,
        filterPreset: String = "none",
        filterStrength: Double = 1.0,
        beautyStrength: Double = 0.0,
        shouldMuteAudio: Bool = false,
        trimStartMs: Int64 = 0,
        trimEndMs: Int64 = 0,
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
                animatedStickers: animatedStickers,
                mirrorHorizontally: mirrorHorizontally,
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                filterPreset: filterPreset,
                filterStrength: filterStrength,
                beautyStrength: beautyStrength,
                shouldMuteAudio: shouldMuteAudio,
                trimStartMs: trimStartMs,
                trimEndMs: trimEndMs,
                completion: completion
            )
        }
    }

    /// One animated GIF sticker layer: pre-decoded frames plus its rect in
    /// output pixels (bottom-left origin, Core Image space).
    private struct AnimatedStickerLayer {
        let frames: [CIImage]
        let frameStarts: [Double]
        let duration: Double
        let rect: CGRect
    }

    /// Decode animated sticker GIFs and map their rects (normalized to the
    /// overlay PNG, top-left origin) into output space using the exact same
    /// cover-fill transform the static overlay gets.
    private func loadAnimatedStickers(
        _ descriptors: [[String: Any]],
        overlayExtent: CGRect,
        targetExtent: CGRect
    ) -> [AnimatedStickerLayer] {
        guard !descriptors.isEmpty else { return [] }
        var layers: [AnimatedStickerLayer] = []
        let ovW = overlayExtent.width
        let ovH = overlayExtent.height
        guard ovW > 0, ovH > 0 else { return [] }
        let scale = max(targetExtent.width / ovW, targetExtent.height / ovH)
        let dx0 = (targetExtent.width - ovW * scale) / 2
        let dy0 = (targetExtent.height - ovH * scale) / 2

        for d in descriptors {
            guard let path = d["path"] as? String,
                  let l = (d["left"] as? NSNumber)?.doubleValue,
                  let t = (d["top"] as? NSNumber)?.doubleValue,
                  let w = (d["width"] as? NSNumber)?.doubleValue,
                  let h = (d["height"] as? NSNumber)?.doubleValue,
                  w > 0, h > 0 else { continue }
            let url = URL(fileURLWithPath: path)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
            let count = min(CGImageSourceGetCount(source), 240)
            guard count > 0 else { continue }

            var frames: [CIImage] = []
            var starts: [Double] = []
            var total: Double = 0
            for i in 0..<count {
                guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                frames.append(CIImage(cgImage: cg))
                starts.append(total)
                total += VideoOverlayProcessor.gifFrameDelay(source: source, index: i)
            }
            guard !frames.isEmpty else { continue }

            let wOut = CGFloat(w) * ovW * scale
            let hOut = CGFloat(h) * ovH * scale
            let x = CGFloat(l) * ovW * scale + dx0
            let yFromTop = CGFloat(t) * ovH * scale + dy0
            let y = targetExtent.height - yFromTop - hOut

            layers.append(AnimatedStickerLayer(
                frames: frames,
                frameStarts: starts,
                duration: max(total, 0.01),
                rect: CGRect(x: x, y: y, width: wOut, height: hOut)
            ))
            print("VideoOverlayProcessor: Animated sticker ready (\(frames.count) frames, \(total)s loop)")
        }
        return layers
    }

    private static func gifFrameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0
        let clamped = (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0
        let delay = unclamped > 0 ? unclamped : clamped
        return delay > 0.011 ? delay : 0.1
    }

    /// Pick the GIF frame for a video timestamp (loops).
    private func stickerFrame(_ layer: AnimatedStickerLayer, at time: Double) -> CIImage {
        if layer.frames.count == 1 { return layer.frames[0] }
        let t = time.truncatingRemainder(dividingBy: layer.duration)
        var index = 0
        for (i, start) in layer.frameStarts.enumerated() {
            if start <= t { index = i } else { break }
        }
        return layer.frames[index]
    }

    /// Single-pass export: video crop/scale + optional filter + overlay composited together.
    /// Keeping both filtered and unfiltered exports on the same path avoids the iOS-only
    /// black-video regression that showed up in the separate Core Animation exporter.
    private func exportSinglePassWithOverlay(
        videoURL: URL,
        overlayImagePath: String,
        outputURL: URL,
        outputPath: String,
        animatedStickers: [[String: Any]] = [],
        mirrorHorizontally: Bool,
        outputWidth: Int?,
        outputHeight: Int?,
        filterPreset: String,
        filterStrength: Double,
        beautyStrength: Double,
        shouldMuteAudio: Bool = false,
        trimStartMs: Int64 = 0,
        trimEndMs: Int64 = 0,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard let overlayUIImage = UIImage(contentsOfFile: overlayImagePath),
              let overlayCGImage = overlayUIImage.cgImage else {
            DispatchQueue.main.async { completion(nil, "Failed to load the overlay image.") }
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
        let trimStartSeconds = max(0, Double(trimStartMs) / 1000.0)
        let requestedTrimEndSeconds = trimEndMs > 0
            ? Double(trimEndMs) / 1000.0
            : inputDuration
        let trimEndSeconds = min(inputDuration, requestedTrimEndSeconds)
        guard trimStartSeconds < trimEndSeconds else {
            DispatchQueue.main.async { completion(nil, "The video trim range is outside the input duration.") }
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

        // Animated GIF stickers — decoded once, composited per frame below so
        // they stay animated in the exported video.
        let animatedLayers = loadAnimatedStickers(
            animatedStickers,
            overlayExtent: overlayCI.extent,
            targetExtent: targetExtent
        )

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
            if (filterPreset != "none" && filterStrength > 0.01) || beautyStrength > 0 {
                guard let renderedFilter = self.applyFilter(
                    to: source.clampedToExtent(),
                    extent: targetExtent,
                    preset: filterPreset,
                    strength: filterStrength,
                    beautyStrength: beautyStrength
                ) else {
                    request.finish(with: NSError(
                        domain: "StoryEditorPro.Filter",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The iOS parity filter kernel is unavailable."]
                    ))
                    return
                }
                filtered = renderedFilter.cropped(to: targetExtent)
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
            var composited = scaledOverlay.composited(over: filtered).cropped(to: targetExtent)

            // Animated GIF stickers on top, advanced to this frame's timestamp
            if !animatedLayers.isEmpty {
                let seconds = max(0, request.compositionTime.seconds - trimStartSeconds)
                for layer in animatedLayers {
                    let frame = self.stickerFrame(layer, at: seconds)
                    let extent = frame.extent
                    guard extent.width > 0, extent.height > 0 else { continue }
                    let transform = CGAffineTransform(translationX: layer.rect.minX, y: layer.rect.minY)
                        .scaledBy(x: layer.rect.width / extent.width,
                                  y: layer.rect.height / extent.height)
                    composited = frame.transformed(by: transform)
                        .composited(over: composited)
                        .cropped(to: targetExtent)
                }
            }

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
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStartSeconds, preferredTimescale: 600),
            duration: CMTime(
                seconds: trimEndSeconds - trimStartSeconds,
                preferredTimescale: 600
            )
        )

        // Mute: silence the audio track in the exported file.
        if shouldMuteAudio, let audioTrack = asset.tracks(withMediaType: .audio).first {
            let audioMix = AVMutableAudioMix()
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.setVolume(0.0, at: .zero)
            audioMix.inputParameters = [params]
            exporter.audioMix = audioMix
        }

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
                    let code = (exporter.error as NSError?)?.code ?? -1
                    print("VideoOverlayProcessor: SinglePass export failed (code=\(code))")
                    completion(nil, "AVAssetExportSession failed (code=\(code)).")
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
            guard let filtered = self.applyFilter(
                to: source,
                extent: request.sourceImage.extent,
                preset: preset,
                strength: strength
            ) else {
                request.finish(with: NSError(
                    domain: "StoryEditorPro.Filter",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The iOS parity filter kernel is unavailable."]
                ))
                return
            }
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
    private func applyFilter(
        to image: CIImage,
        extent renderExtent: CGRect,
        preset: String,
        strength: Double,
        beautyStrength: Double = 0
    ) -> CIImage? {
        let t = strength.isFinite ? max(0.0, min(1.0, strength)) : 0.0
        if t < 0.001 && beautyStrength <= 0 { return image }
        let p = resolveFilterParams(preset: preset, strength: t)

        if let parityFilterKernel = parityFilterKernel {
            let c = p.contrast
            let s = p.saturation
            let rLum = 0.2126, gLum = 0.7152, bLum = 0.0722
            let sr = (1.0 - s) * rLum
            let sg = (1.0 - s) * gLum
            let sb = (1.0 - s) * bLum
            let r0 = (sr + s) * c * p.red
            let r1 = sg * c * p.red
            let r2 = sb * c * p.red
            let g0 = sr * c * p.green
            let g1 = (sg + s) * c * p.green
            let g2 = sb * c * p.green
            let b0 = sr * c * p.blue
            let b1 = sg * c * p.blue
            let b2 = (sb + s) * c * p.blue
            let bias = p.brightness + (1.0 - c) * 0.5
            if let result = parityFilterKernel.apply(
                extent: renderExtent,
                roiCallback: { _, rect in
                    rect.insetBy(dx: -renderExtent.width * 2.2 / 720.0,
                                 dy: -renderExtent.height * 2.2 / 1280.0)
                },
                arguments: [
                    image.clampedToExtent(),
                    renderExtent.width,
                    renderExtent.height,
                    r0, r1, r2,
                    g0, g1, g2,
                    b0, b1, b2,
                    bias,
                    p.sCurve,
                    p.vignette,
                    beautyStrength.isFinite ? max(0, min(1, beautyStrength)) : 0,
                    p.vhs,
                    p.bloom,
                    p.grain,
                    p.halation,
                    p.splitTone,
                    p.chroma,
                ]
            ) {
                return result
            }
        }

        // Do not silently substitute Core Image filters with different math.
        // A missing/failed parity kernel must fail the export explicitly.
        return nil
    }

    private func resolveFilterParams(preset: String, strength: Double) -> (brightness: Double, contrast: Double, saturation: Double, red: Double, green: Double, blue: Double, vignette: Double, sCurve: Double, warpMode: Int, warpAmount: Double, beauty: Double, vhs: Double, bloom: Double, grain: Double, halation: Double, splitTone: Double, chroma: Double) {
        let neutral = (brightness: 0.0, contrast: 1.0, saturation: 1.0, red: 1.0, green: 1.0, blue: 1.0, vignette: 0.0, sCurve: 0.0, warpMode: 0, warpAmount: 0.0)
        let target: (brightness: Double, contrast: Double, saturation: Double, red: Double, green: Double, blue: Double, vignette: Double, sCurve: Double, warpMode: Int, warpAmount: Double)

        // Tuple order: (brightness, contrast, saturation, red, green, blue, vignette, sCurve, warpMode, warpAmount)
        // vignette: shared normalized strength used by Flutter/Android/iOS.
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
        case "vignette":    target = (-0.02, 1.15, 1.05, 1.01, 1.0,  0.99, 0.62, 0.25, 0, 0.0)
        case "retro2044":   target = (0.02,  1.22, 1.42, 1.20, 0.95, 1.18, 0.22, 0.45, 0, 0.0)
        case "cinematic":   target = (-0.02, 1.30, 0.72, 1.06, 1.01, 0.90, 0.35, 0.65, 0, 0.0)
        case "tealorange":  target = (0.01,  1.22, 1.18, 1.20, 1.01, 1.18, 0.18, 0.45, 0, 0.0)
        case "portraitpop": target = (0.03,  1.18, 1.15, 1.14, 1.03, 0.92, 0.16, 0.30, 0, 0.0)
        case "nightneon":   target = (-0.03, 1.38, 1.38, 0.94, 1.10, 1.28, 0.40, 0.60, 0, 0.0)
        case "productcrisp":target = (0.01,  1.28, 1.22, 1.04, 1.04, 1.04, 0.08, 0.45, 0, 0.0)
        case "filmicfade":  target = (0.02,  1.05, 0.72, 1.06, 1.01, 0.90, 0.52, 0.25, 0, 0.0)
        case "pastelmist":  target = (0.06,  0.88, 0.88, 1.06, 1.02, 1.08, 0.22, 0.0,  0, 0.0)
        case "goldenhour":  target = (0.05,  1.08, 1.22, 1.22, 1.08, 0.72, 0.14, 0.20, 0, 0.0)
        case "arctic":      target = (0.06,  1.12, 0.85, 0.86, 1.00, 1.30, 0.0,  0.0,  0, 0.0)
        case "sepia":       target = (0.03,  1.05, 0.35, 1.22, 1.05, 0.78, 0.12, 0.35, 0, 0.0)
        case "emerald":     target = (0.0,   1.12, 1.12, 0.85, 1.20, 0.95, 0.0,  0.25, 0, 0.0)
        case "rosegold":    target = (0.05,  1.02, 1.10, 1.20, 0.98, 1.02, 0.0,  0.0,  0, 0.0)
        case "moody":       target = (-0.06, 1.28, 0.82, 0.98, 0.98, 1.06, 0.20, 0.55, 0, 0.0)
        case "bleach":      target = (0.08,  1.35, 0.55, 1.02, 1.02, 1.00, 0.24, 0.0,  0, 0.0)
        case "velvet":      target = (-0.02, 1.15, 1.30, 1.10, 0.88, 1.14, 0.16, 0.40, 0, 0.0)
        case "softbeauty":  target = (0.045, 0.96, 1.04, 1.06, 1.015,0.985,0.0,  0.0,  0, 0.0)
        case "cleanglow":   target = (0.065, 1.02, 1.08, 1.035,1.02, 1.0,  0.0,  0.12, 0, 0.0)
        case "vhs1993":     target = (0.010, 0.94, 0.82, 1.055,1.0,  0.935,0.15, 0.08, 0, 0.0)
        case "kuwaitgold":  target = (0.012, 1.07, 1.04, 1.065,1.010,0.940,0.12, 0.26, 0, 0.0)
        case "daytime":     target = (0.035, 0.98, 0.95, 1.045,1.015,0.965,0.06, 0.08, 0, 0.0)
        case "timefocus":   target = (0.025, 1.02, 0.96, 1.025,1.010,0.995,0.08, 0.10, 0, 0.0)
        case "retrodate":   target = (0.018, 0.96, 0.88, 1.060,1.005,0.940,0.18, 0.06, 0, 0.0)
        default:            target = neutral
        }

        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            a + (b - a) * t
        }
        let beautyTarget = 0.0
        let vhsTarget = preset == "vhs1993" ? 0.68 : 0.0
        let bloomTarget: Double = ["vhs1993": 0.08, "daytime": 0.46, "timefocus": 0.22, "kuwaitgold": 0.32, "retrodate": 0.30][preset] ?? 0.0
        let grainTarget: Double = ["vhs1993": 0.72, "daytime": 0.05, "kuwaitgold": 0.12, "retrodate": 0.36][preset] ?? 0.0
        let halationTarget: Double = ["vhs1993": 0.12, "daytime": 0.42, "timefocus": 0.12, "kuwaitgold": 0.30, "retrodate": 0.34][preset] ?? 0.0
        let splitToneTarget: Double = ["vhs1993": 0.08, "daytime": 0.15, "timefocus": -0.04, "kuwaitgold": 0.42, "retrodate": -0.38][preset] ?? 0.0
        let chromaTarget: Double = ["vhs1993": 0.62, "daytime": 0.04, "kuwaitgold": 0.07, "retrodate": 0.24][preset] ?? 0.0

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
            warpAmount: lerp(neutral.warpAmount, target.warpAmount, strength),
            beauty:     beautyTarget * strength,
            vhs:        vhsTarget * strength,
            bloom:      bloomTarget * strength,
            grain:      grainTarget * strength,
            halation:   halationTarget * strength,
            splitTone:  splitToneTarget * strength,
            chroma:     chromaTarget * strength
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
