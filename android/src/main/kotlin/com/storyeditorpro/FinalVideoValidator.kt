package com.storyeditorpro

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** No rendering, audio, network, camera or normalization. Decode the final file. */
class FinalVideoValidator {
    private val jobs = ConcurrentHashMap<String, AtomicBoolean>()
    private val handler = Handler(Looper.getMainLooper())
    fun cancel(id: String?) { if (id != null) jobs[id]?.set(true) }
    fun cancelAll() { jobs.values.forEach { it.set(true) } }
    fun validate(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("requestId")
        val path = call.argument<String>("path")
        if (id.isNullOrBlank() || path.isNullOrBlank() || jobs.size >= 2) {
            result.error("video_validation_busy", "Video validation unavailable", null)
            return
        }
        val cancelled = AtomicBoolean(false)
        if (jobs.putIfAbsent(id, cancelled) != null) {
            result.error("video_validation_duplicate", "Duplicate validation", null)
            return
        }
        Thread {
            val extractor = MediaExtractor()
            var decoder: MediaCodec? = null
            var answer: Map<String, Any>? = null
            var failure: String? = null
            val deadline = SystemClock.elapsedRealtime() + 90000L
            fun check() {
                check(!cancelled.get()) { "video_validation_cancelled" }
                check(SystemClock.elapsedRealtime() < deadline) { "video_validation_timeout" }
            }
            try {
                val file = File(path)
                check(file.isFile && file.length() > 0) { "video_source_missing" }
                val timing = VideoSampleTiming.read(file)
                extractor.setDataSource(file.absolutePath)
                val videoTracks = (0 until extractor.trackCount).filter {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
                }
                check(videoTracks.size == 1) { "video_track_unreadable" }
                val index = videoTracks.single()
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: error("video_codec_unreadable")
                check(mime == "video/avc" || mime == "video/hevc") { "video_codec_unsupported" }
                check(format.containsKey(MediaFormat.KEY_DURATION)) { "video_duration_unreadable" }
                // This is the selected VIDEO track's duration, never retriever/movie/audio duration.
                val durationUs = format.getLong(MediaFormat.KEY_DURATION)
                check(durationUs >= 2000000L) { "video_too_short" }
                check(durationUs <= 3600000000L) { "video_validation_limit" }
                extractor.selectTrack(index)
                decoder = MediaCodec.createDecoderByType(mime)
                decoder.configure(format, null, null, 0)
                decoder.start()
                val codec = decoder
                val info = MediaCodec.BufferInfo()
                var inputEnded = false
                var outputEnded = false
                var samples = 0L
                val presentationPts = mutableListOf<Long>()
                val decodedPts = mutableListOf<Long>()
                var frames = 0L
                var firstPts = Long.MAX_VALUE
                var lastPts = Long.MIN_VALUE
                while (!outputEnded) {
                    check()
                    if (!inputEnded) {
                        val input = codec.dequeueInputBuffer(10000)
                        if (input >= 0) {
                            val buffer = codec.getInputBuffer(input) ?: error("video_decode_failed")
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                codec.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputEnded = true
                            } else {
                                check(extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_ENCRYPTED == 0) {
                                    "video_encrypted_unsupported"
                                }
                                codec.queueInputBuffer(input, 0, size, extractor.sampleTime, 0)
                                presentationPts.add(extractor.sampleTime)
                                samples++
                                extractor.advance()
                            }
                        }
                    }
                    val output = codec.dequeueOutputBuffer(info, 10000)
                    if (output >= 0) {
                        if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            frames++
                            decodedPts.add(info.presentationTimeUs)
                            firstPts = minOf(firstPts, info.presentationTimeUs)
                            lastPts = maxOf(lastPts, info.presentationTimeUs)
                        }
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        codec.releaseOutputBuffer(output, false)
                    }
                }
                check()
                check(samples > 0 && frames == samples) { "video_decode_incomplete" }
                check(decodedPts.sorted() == presentationPts.sorted()) { "video_decode_presentation_mismatch" }
                // A still sample held for >=2s is valid; long audio with a short video track is not.
                check(lastPts >= 0L && lastPts < durationUs) {
                    "video_presentation_unreadable"
                }
                val coveredUs = timing.coveredMicroseconds(presentationPts, durationUs)
                answer = mapOf("decoded" to true, "decodedFrames" to frames,
                    "videoDurationUs" to coveredUs, "codec" to mime)
            } catch (e: Exception) {
                failure = e.message?.takeIf { it.startsWith("video_") } ?: "video_decode_failed"
            } finally {
                try { decoder?.stop() } catch (_: Exception) {}
                try { decoder?.release() } catch (_: Exception) {}
                extractor.release()
                jobs.remove(id)
            }
            handler.post {
                if (failure != null) result.error(failure, "Could not verify final video", null)
                else result.success(answer)
            }
        }.start()
    }
}
