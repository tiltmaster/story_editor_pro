import Flutter
import AVFoundation
import CoreMedia

/// Reads decoded video samples without rendering or processing audio.
final class FinalVideoValidator {
    private let lock = NSLock()
    private var jobs: [String: AVAssetReader?] = [:]
    private var cancelled = Set<String>()
    func cancelAll() {
        lock.lock()
        let ids = Array(jobs.keys)
        lock.unlock()
        for id in ids { cancel(id) }
    }
    func cancel(_ id: String) {
        lock.lock()
        if jobs.keys.contains(id) {
            cancelled.insert(id)
            if let entry = jobs[id], let reader = entry { reader.cancelReading() }
        }
        lock.unlock()
    }
    func validate(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              let id = args["requestId"] as? String, !id.isEmpty else {
            result(FlutterError(code: "video_invalid_args", message: "Missing final video", details: nil)); return
        }
        lock.lock()
        let busy = jobs.count >= 2 || jobs.keys.contains(id)
        if !busy { jobs.updateValue(nil, forKey: id) }
        lock.unlock()
        if busy { result(FlutterError(code: "video_validation_busy", message: "Validation unavailable", details: nil)); return }
        DispatchQueue.global(qos: .utility).async {
            let deadline = ProcessInfo.processInfo.systemUptime + 90
            var answer: [String: Any]?
            var failure = "video_decode_failed"
            func stopped() -> Bool {
                self.lock.lock(); let value = self.cancelled.contains(id); self.lock.unlock()
                return value || ProcessInfo.processInfo.systemUptime >= deadline
            }
            do {
                let asset = AVURLAsset(url: URL(fileURLWithPath: path))
                let tracks = asset.tracks(withMediaType: .video)
                guard tracks.count == 1, let track = tracks.first else { throw ProbeError.invalid }
                guard let descriptions = track.formatDescriptions as? [CMFormatDescription],
                      let description = descriptions.first else { throw ProbeError.invalid }
                let codec = CMFormatDescriptionGetMediaSubType(description)
                guard codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_HEVC else { throw ProbeError.invalid }
                let duration = track.timeRange.duration
                guard duration.isNumeric, CMTimeCompare(duration, CMTime(value: 2, timescale: 1)) >= 0,
                      CMTimeGetSeconds(duration) <= 3600 else {
                    failure = "video_too_short_or_unreadable"; throw ProbeError.invalid
                }
                let reader = try AVAssetReader(asset: asset)
                self.lock.lock()
                self.jobs.updateValue(reader, forKey: id)
                let wasCancelled = self.cancelled.contains(id)
                self.lock.unlock()
                if wasCancelled { reader.cancelReading(); throw ProbeError.invalid }
                let output = AVAssetReaderTrackOutput(track: track,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else { throw ProbeError.invalid }
                reader.add(output)
                reader.timeRange = track.timeRange
                guard reader.startReading() else { throw ProbeError.invalid }
                var frames = 0
                var intervals: [(CMTime, CMTime)] = []
                while let sample = output.copyNextSampleBuffer() {
                    if stopped() { reader.cancelReading(); failure = "video_validation_cancelled_or_timeout"; throw ProbeError.invalid }
                    guard CMSampleBufferDataIsReady(sample), CMSampleBufferGetImageBuffer(sample) != nil else { throw ProbeError.invalid }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    let sampleDuration = CMSampleBufferGetDuration(sample)
                    guard pts.isNumeric, sampleDuration.isNumeric, CMTimeCompare(sampleDuration, .zero) > 0 else {
                        failure = "video_presentation_unreadable"; throw ProbeError.invalid
                    }
                    let start = CMTimeMaximum(pts, track.timeRange.start)
                    let end = CMTimeMinimum(CMTimeAdd(pts, sampleDuration), CMTimeRangeGetEnd(track.timeRange))
                    if CMTimeCompare(end, start) > 0 { intervals.append((start, end)) }
                    frames += 1
                    guard frames <= 216000 else { reader.cancelReading(); throw ProbeError.invalid }
                }
                guard !stopped(), reader.status == .completed, frames > 0 else { throw ProbeError.invalid }
                intervals.sort { CMTimeCompare($0.0, $1.0) < 0 }
                var covered = CMTime.zero
                var start = CMTime.zero
                var end = CMTime.zero
                for interval in intervals {
                    if CMTimeCompare(interval.0, end) > 0 {
                        covered = CMTimeAdd(covered, CMTimeSubtract(end, start))
                        start = interval.0; end = interval.1
                    } else { end = CMTimeMaximum(end, interval.1) }
                }
                covered = CMTimeAdd(covered, CMTimeSubtract(end, start))
                guard CMTimeCompare(covered, CMTime(value: 2, timescale: 1)) >= 0 else {
                    failure = "video_too_short"; throw ProbeError.invalid
                }
                answer = ["decoded": true, "decodedFrames": frames,
                          "videoDurationUs": CMTimeConvertScale(covered, timescale: 1000000, method: .roundTowardZero).value,
                          "codec": codec == kCMVideoCodecType_H264 ? "video/avc" : "video/hevc"]
            } catch { /* Fail closed; never use asset/audio duration as fallback. */ }
            self.lock.lock(); self.jobs.removeValue(forKey: id); self.cancelled.remove(id); self.lock.unlock()
            DispatchQueue.main.async {
                if let answer = answer { result(answer) }
                else { result(FlutterError(code: failure, message: "Could not verify final video", details: nil)) }
            }
        }
    }
    private enum ProbeError: Error { case invalid }
}
