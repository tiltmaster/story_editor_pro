import Foundation
import AVFoundation
import UIKit
import CoreImage

/// Native Boomerang işlemcisi (FFmpeg'siz)
/// AVAssetReader ile TÜM frame'leri decode eder
class BoomerangProcessor {

    /// Boomerang video oluşturur
    func createBoomerang(
        inputPath: String,
        outputPath: String,
        loopCount: Int = 3,
        fps: Int = 30,
        completion: @escaping (String?) -> Void
    ) {
        print("BoomerangProcessor: Starting boomerang creation")
        print("Input: \(inputPath)")
        print("Output: \(outputPath)")

        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        // Mevcut output dosyasını sil
        try? FileManager.default.removeItem(at: outputURL)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 1. TÜM frame'leri decode et
            let frames = self.decodeAllFrames(from: inputURL)
            guard !frames.isEmpty else {
                print("BoomerangProcessor: No frames decoded")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            print("BoomerangProcessor: Decoded \(frames.count) frames")

            // 2. Boomerang sırası oluştur
            let boomerangFrames = self.createBoomerangSequence(frames: frames, loopCount: loopCount)
            print("BoomerangProcessor: Boomerang sequence: \(boomerangFrames.count) frames")

            // 3. Video olarak encode et
            self.encodeFramesToVideo(frames: boomerangFrames, outputURL: outputURL, fps: fps) { success in
                DispatchQueue.main.async {
                    if success {
                        print("BoomerangProcessor: Success!")
                        completion(outputPath)
                    } else {
                        print("BoomerangProcessor: Encoding failed")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// AVAssetReader ile TÜM frame'leri decode eder
    private func decodeAllFrames(from url: URL) -> [CGImage] {
        var frames: [CGImage] = []

        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        print("BoomerangProcessor: Video duration: \(duration)s")

        // Video track'i al
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("BoomerangProcessor: No video track found")
            return frames
        }

        let naturalSize = videoTrack.naturalSize
        let transform = videoTrack.preferredTransform
        print("BoomerangProcessor: Video size: \(naturalSize), transform: \(transform)")

        // Reader output settings
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        do {
            let reader = try AVAssetReader(asset: asset)

            let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false

            if reader.canAdd(trackOutput) {
                reader.add(trackOutput)
            }

            reader.startReading()

            var frameCount = 0
            let context = CIContext(options: nil)

            while reader.status == .reading {
                autoreleasepool {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                       let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {

                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

                        // Transform uygula (rotation/flip fix)
                        let transformedImage = ciImage.transformed(by: self.transformForTrack(videoTrack))

                        let width = Int(transformedImage.extent.width)
                        let height = Int(transformedImage.extent.height)

                        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                            frames.append(cgImage)
                            frameCount += 1

                            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            let timeMs = Int(CMTimeGetSeconds(pts) * 1000)
                            print("BoomerangProcessor: Frame \(frameCount) decoded at \(timeMs)ms")
                        }
                    }
                }
            }

            if reader.status == .completed {
                print("BoomerangProcessor: Reader completed, total frames: \(frames.count)")
            } else if reader.status == .failed {
                print("BoomerangProcessor: Reader failed: \(reader.error?.localizedDescription ?? "unknown")")
            }

        } catch {
            print("BoomerangProcessor: Reader creation failed: \(error)")
        }

        return frames
    }

    /// Video track transform'unu hesapla (rotation fix)
    private func transformForTrack(_ track: AVAssetTrack) -> CGAffineTransform {
        let transform = track.preferredTransform
        let size = track.naturalSize

        // Rotation'ı tespit et ve düzelt
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            // 90 derece saat yönünde
            return CGAffineTransform(translationX: size.height, y: 0).rotated(by: .pi / 2)
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            // 90 derece saat yönünün tersine
            return CGAffineTransform(translationX: 0, y: size.width).rotated(by: -.pi / 2)
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            // 180 derece
            return CGAffineTransform(translationX: size.width, y: size.height).rotated(by: .pi)
        }

        return .identity
    }

    /// Boomerang frame sırası: ileri + geri (son frame hariç) * loopCount
    private func createBoomerangSequence(frames: [CGImage], loopCount: Int) -> [CGImage] {
        guard !frames.isEmpty else { return [] }

        print("BoomerangProcessor: Creating boomerang sequence from \(frames.count) frames, loopCount=\(loopCount)")

        var forwardBackward: [CGImage] = []

        // İleri
        forwardBackward.append(contentsOf: frames)
        print("BoomerangProcessor: Forward: \(frames.count) frames")

        // Geri (ilk ve son frame hariç)
        if frames.count > 2 {
            let reversed = Array(frames[1..<(frames.count - 1)].reversed())
            forwardBackward.append(contentsOf: reversed)
            print("BoomerangProcessor: Backward: \(reversed.count) frames (reversed middle)")
        } else {
            print("BoomerangProcessor: Not enough frames for backward sequence (need >2, have \(frames.count))")
        }

        print("BoomerangProcessor: One cycle: \(forwardBackward.count) frames (forward + backward)")

        // Loop
        var result: [CGImage] = []
        for _ in 0..<loopCount {
            result.append(contentsOf: forwardBackward)
        }

        print("BoomerangProcessor: Final sequence: \(result.count) frames (\(loopCount) loops)")
        return result
    }

    /// JPEG frame'lerden boomerang video oluşturur (Instagram tarzı)
    func createBoomerangFromFrames(
        frameDir: String,
        outputPath: String,
        fps: Int = 30,
        loopCount: Int = 3,
        completion: @escaping (String?) -> Void
    ) {
        print("BoomerangProcessor: Creating boomerang from frames")
        print("Frame dir: \(frameDir)")
        print("Output: \(outputPath)")

        let outputURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: outputURL)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Frame dosyalarını oku
            let frameDirURL = URL(fileURLWithPath: frameDir)
            guard let frameFiles = try? FileManager.default.contentsOfDirectory(at: frameDirURL, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension.lowercased() == "jpg" })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else {
                print("BoomerangProcessor: No frame files found")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if frameFiles.isEmpty {
                print("BoomerangProcessor: Frame files empty")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            print("BoomerangProcessor: Found \(frameFiles.count) frame files")

            // Frame'leri CGImage olarak yükle
            var frames: [CGImage] = []
            for fileURL in frameFiles {
                if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                   let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                    frames.append(cgImage)
                }
            }

            if frames.isEmpty {
                print("BoomerangProcessor: No frames decoded")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            print("BoomerangProcessor: Loaded \(frames.count) frames")

            // Frame'ler zaten forward+backward sırasında, sadece loop uygula
            var boomerangFrames: [CGImage] = []
            for _ in 0..<loopCount {
                boomerangFrames.append(contentsOf: frames)
            }

            print("BoomerangProcessor: Boomerang sequence: \(boomerangFrames.count) frames")

            // Video olarak encode et
            self.encodeFramesToVideo(frames: boomerangFrames, outputURL: outputURL, fps: fps) { success in
                DispatchQueue.main.async {
                    if success {
                        print("BoomerangProcessor: Boomerang from frames created successfully!")
                        completion(outputPath)
                    } else {
                        print("BoomerangProcessor: Encoding failed")
                        completion(nil)
                    }
                }
            }
        }
    }

    /// CGImage listesini video olarak encode eder
    private func encodeFramesToVideo(
        frames: [CGImage],
        outputURL: URL,
        fps: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard let firstFrame = frames.first else {
            completion(false)
            return
        }

        let width = firstFrame.width
        let height = firstFrame.height

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            print("BoomerangProcessor: Failed to create writer")
            completion(false)
            return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        var frameCount = 0

        let queue = DispatchQueue(label: "videoEncodingQueue")

        writerInput.requestMediaDataWhenReady(on: queue) { [weak self] in
            while writerInput.isReadyForMoreMediaData && frameCount < frames.count {
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameCount))

                if let pixelBuffer = self?.pixelBuffer(from: frames[frameCount], width: width, height: height) {
                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                }

                frameCount += 1
            }

            if frameCount >= frames.count {
                writerInput.markAsFinished()
                writer.finishWriting {
                    completion(writer.status == .completed)
                }
            }
        }
    }

    /// CGImage'dan CVPixelBuffer oluşturur
    private func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}
