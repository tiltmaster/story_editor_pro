import AVFoundation
import AudioToolbox

struct FaceARRecordingContract {
    static let framesPerSecond = 30
    static let audioSampleRate = 44_100
    static let audioChannelCount = 1
    static let audioBitRate = 96_000

    static func videoBitRate(width: Int, height: Int) -> Int {
        max(2_500_000, min(10_000_000, width * height * 5))
    }

    static func dimensionsAreValid(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width.isMultiple(of: 2) && height.isMultiple(of: 2)
    }
}

/// Writes the exact pixel buffers handed to Flutter's preview texture. This is
/// deliberately downstream of FaceARCoordinator so recorded video and preview
/// cannot diverge when a lens is enabled.
final class FaceARVideoRecorder {
    private enum State { case idle, armed, writing, finishing }

    private let lock = NSLock()
    private var state: State = .idle
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputPath: String?

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return state != .idle
    }

    func start(outputPath: String, width: Int, height: Int) -> Error? {
        lock.lock(); defer { lock.unlock() }
        guard state == .idle else {
            return NSError(domain: "FaceARVideoRecorder", code: 1,
                           userInfo: [NSLocalizedDescriptionKey: "Recording is already active"])
        }
        guard FaceARRecordingContract.dimensionsAreValid(width: width, height: height) else {
            return NSError(domain: "FaceARVideoRecorder", code: 7,
                           userInfo: [NSLocalizedDescriptionKey: "Recording dimensions must be positive"])
        }
        do {
            let url = URL(fileURLWithPath: outputPath)
            guard !FileManager.default.fileExists(atPath: outputPath) else {
                return NSError(domain: "FaceARVideoRecorder", code: 5,
                               userInfo: [NSLocalizedDescriptionKey: "Recording output already exists"])
            }
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let bitrate = FaceARRecordingContract.videoBitRate(width: width, height: height)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoExpectedSourceFrameRateKey: FaceARRecordingContract.framesPerSecond,
                    AVVideoMaxKeyFrameIntervalKey: FaceARRecordingContract.framesPerSecond
                ]
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            videoInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput) else {
                return NSError(domain: "FaceARVideoRecorder", code: 2,
                               userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }
            writer.add(videoInput)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: FaceARRecordingContract.audioSampleRate,
                AVNumberOfChannelsKey: FaceARRecordingContract.audioChannelCount,
                AVEncoderBitRateKey: FaceARRecordingContract.audioBitRate
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(audioInput) else {
                return NSError(domain: "FaceARVideoRecorder", code: 6,
                               userInfo: [NSLocalizedDescriptionKey: "Cannot add microphone audio input"])
            }
            writer.add(audioInput)
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: attributes
            )
            self.outputPath = outputPath
            state = .armed
            return nil
        } catch {
            resetLocked()
            return error
        }
    }

    func appendVideo(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock(); defer { lock.unlock() }
        guard state == .armed || state == .writing,
              let writer = writer,
              let videoInput = videoInput,
              let adaptor = adaptor else { return }
        if state == .armed {
            guard writer.startWriting() else { resetLocked(); return }
            writer.startSession(atSourceTime: presentationTime)
            state = .writing
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        _ = adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }

    func appendAudio(sampleBuffer: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        // The first video frame establishes the movie session so the output
        // dimensions and visible start match preview. Audio arriving slightly
        // earlier is intentionally dropped rather than creating A/V lead-in.
        guard state == .writing, let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData else { return }
        _ = audioInput.append(sampleBuffer)
    }

    func stop(completion: @escaping (String?, Error?) -> Void) {
        lock.lock()
        guard state == .armed || state == .writing,
              let writer = writer,
              let videoInput = videoInput,
              let path = outputPath else {
            lock.unlock()
            completion(nil, NSError(domain: "FaceARVideoRecorder", code: 3,
                                    userInfo: [NSLocalizedDescriptionKey: "No active recording"]))
            return
        }
        let wasWriting = state == .writing
        state = .finishing
        if wasWriting {
            videoInput.markAsFinished()
            audioInput?.markAsFinished()
        }
        lock.unlock()

        guard wasWriting else {
            writer.cancelWriting()
            lock.lock(); resetLocked(); lock.unlock()
            completion(nil, NSError(domain: "FaceARVideoRecorder", code: 4,
                                    userInfo: [NSLocalizedDescriptionKey: "No video frames were recorded"]))
            return
        }
        writer.finishWriting { [weak self] in
            let error = writer.status == .completed ? nil : writer.error
            self?.lock.lock(); self?.resetLocked(); self?.lock.unlock()
            completion(error == nil ? path : nil, error)
        }
    }

    func cancel() {
        lock.lock()
        writer?.cancelWriting()
        resetLocked()
        lock.unlock()
    }

    private func resetLocked() {
        state = .idle
        writer = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        outputPath = nil
    }
}
