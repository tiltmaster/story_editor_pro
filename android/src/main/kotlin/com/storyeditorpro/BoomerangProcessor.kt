package com.storyeditorpro

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.*
import android.util.Log
import java.io.File

/**
 * Native Boomerang işlemcisi (FFmpeg'siz)
 * MediaMetadataRetriever ile frame çıkarma (güvenilir)
 */
class BoomerangProcessor {

    companion object {
        private const val TAG = "BoomerangProcessor"
        private const val TIMEOUT_US = 10000L
    }

    fun createBoomerang(
        inputPath: String,
        outputPath: String,
        loopCount: Int = 3,
        fps: Int = 30,
        onProgress: ((Double) -> Unit)? = null
    ): String? {
        Log.d(TAG, "========================================")
        Log.d(TAG, "Starting boomerang creation")
        Log.d(TAG, "Input: $inputPath")
        Log.d(TAG, "========================================")

        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            Log.e(TAG, "Input file does not exist")
            return null
        }

        try {
            onProgress?.invoke(0.1)

            // Frame'leri çıkar (daha az frame = daha hızlı)
            // 10 fps = saniyede 10 frame, boomerang için yeterli
            val frames = extractFrames(inputPath, targetFps = 10, maxFrames = 40)
            if (frames.isEmpty()) {
                Log.e(TAG, "No frames extracted")
                return null
            }

            Log.d(TAG, "Extracted ${frames.size} frames")
            onProgress?.invoke(0.4)

            // Boomerang sequence oluştur
            val boomerangFrames = createBoomerangSequence(frames, loopCount)
            Log.d(TAG, "Boomerang sequence: ${boomerangFrames.size} frames")
            onProgress?.invoke(0.5)

            // Video olarak encode et
            val success = encodeFramesToVideo(boomerangFrames, outputPath, fps) { progress ->
                onProgress?.invoke(0.5 + progress * 0.5)
            }

            // Cleanup
            frames.forEach { it.recycle() }

            if (success) {
                Log.d(TAG, "Boomerang created successfully!")
                onProgress?.invoke(1.0)
                return outputPath
            }

            Log.e(TAG, "Failed to encode video")
            return null

        } catch (e: Exception) {
            Log.e(TAG, "Boomerang creation failed", e)
            return null
        }
    }

    /**
     * MediaMetadataRetriever ile frame çıkar
     */
    private fun extractFrames(videoPath: String, targetFps: Int, maxFrames: Int = 40): List<Bitmap> {
        val frames = mutableListOf<Bitmap>()
        val retriever = MediaMetadataRetriever()

        try {
            retriever.setDataSource(videoPath)

            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val durationMs = durationStr?.toLongOrNull() ?: 0L

            Log.d(TAG, "Video duration: ${durationMs}ms")

            if (durationMs <= 0) {
                Log.e(TAG, "Invalid duration")
                return frames
            }

            // Frame aralığı (ms)
            val frameIntervalMs = 1000L / targetFps
            val durationUs = durationMs * 1000

            var timeUs = 0L
            var count = 0

            while (timeUs < durationUs && count < maxFrames) {
                val bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                if (bitmap != null) {
                    frames.add(bitmap.copy(Bitmap.Config.ARGB_8888, false))
                    count++
                }
                timeUs += frameIntervalMs * 1000 // ms to us
            }

            Log.d(TAG, "Extracted $count frames")

        } catch (e: Exception) {
            Log.e(TAG, "Frame extraction failed", e)
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {}
        }

        return frames
    }

    private fun createBoomerangSequence(frames: List<Bitmap>, loopCount: Int): List<Bitmap> {
        if (frames.isEmpty()) return emptyList()

        Log.d(TAG, "Creating boomerang: ${frames.size} frames x $loopCount loops")

        val sequence = mutableListOf<Bitmap>()

        // Forward
        sequence.addAll(frames)

        // Backward (ilk ve son hariç)
        if (frames.size > 2) {
            val reversed = frames.subList(1, frames.size - 1).reversed()
            sequence.addAll(reversed)
            Log.d(TAG, "Forward: ${frames.size}, Backward: ${reversed.size}")
        }

        // Loop
        val result = mutableListOf<Bitmap>()
        repeat(loopCount) {
            result.addAll(sequence)
        }

        Log.d(TAG, "Final: ${result.size} frames")
        return result
    }

    /**
     * JPEG frame'lerden boomerang video oluşturur (Instagram tarzı)
     * Frame'ler zaten sıralı olarak frameDir içinde bulunur
     */
    fun createBoomerangFromFrames(
        frameDir: String,
        outputPath: String,
        fps: Int = 30,
        loopCount: Int = 3,
        onProgress: ((Double) -> Unit)? = null
    ): String? {
        Log.d(TAG, "========================================")
        Log.d(TAG, "Creating boomerang from frames")
        Log.d(TAG, "Frame dir: $frameDir")
        Log.d(TAG, "Output: $outputPath")
        Log.d(TAG, "========================================")

        val frameDirFile = File(frameDir)
        if (!frameDirFile.exists() || !frameDirFile.isDirectory) {
            Log.e(TAG, "Frame directory does not exist")
            return null
        }

        try {
            onProgress?.invoke(0.1)

            // Frame dosyalarını sıralı oku
            val frameFiles = frameDirFile.listFiles { file ->
                file.isFile && file.name.endsWith(".jpg")
            }?.sortedBy { it.name } ?: emptyList()

            if (frameFiles.isEmpty()) {
                Log.e(TAG, "No frame files found")
                return null
            }

            Log.d(TAG, "Found ${frameFiles.size} frame files")

            // Frame'leri Bitmap olarak yükle
            val frames = mutableListOf<Bitmap>()
            for (file in frameFiles) {
                val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                if (bitmap != null) {
                    frames.add(bitmap)
                }
            }

            if (frames.isEmpty()) {
                Log.e(TAG, "No frames decoded")
                return null
            }

            Log.d(TAG, "Loaded ${frames.size} frames")
            onProgress?.invoke(0.3)

            // Boomerang sequence oluştur (loop uygula)
            val boomerangFrames = createBoomerangSequenceFromFrames(frames, loopCount)
            Log.d(TAG, "Boomerang sequence: ${boomerangFrames.size} frames")
            onProgress?.invoke(0.4)

            // Video olarak encode et
            val success = encodeFramesToVideo(boomerangFrames, outputPath, fps) { progress ->
                onProgress?.invoke(0.4 + progress * 0.6)
            }

            // Cleanup - sadece orijinal frame'leri recycle et
            frames.forEach { it.recycle() }

            if (success) {
                Log.d(TAG, "Boomerang from frames created successfully!")
                onProgress?.invoke(1.0)
                return outputPath
            }

            Log.e(TAG, "Failed to encode video")
            return null

        } catch (e: Exception) {
            Log.e(TAG, "Boomerang from frames creation failed", e)
            return null
        }
    }

    /**
     * Frame listesinden boomerang sequence oluşturur
     * Frames zaten forward+backward sırasında gelebilir, bu durumda sadece loop uygula
     */
    private fun createBoomerangSequenceFromFrames(frames: List<Bitmap>, loopCount: Int): List<Bitmap> {
        if (frames.isEmpty()) return emptyList()

        Log.d(TAG, "Creating boomerang sequence from ${frames.size} frames, loopCount=$loopCount")

        // Frame'ler zaten forward+backward sırasında (BoomerangRecorder'dan geliyor)
        // Sadece loop uygula
        val result = mutableListOf<Bitmap>()
        repeat(loopCount) {
            result.addAll(frames)
        }

        Log.d(TAG, "Final sequence: ${result.size} frames")
        return result
    }

    private fun encodeFramesToVideo(
        frames: List<Bitmap>,
        outputPath: String,
        fps: Int,
        onProgress: ((Double) -> Unit)?
    ): Boolean {
        if (frames.isEmpty()) return false

        // Video boyutunu ilk frame'den al
        val firstBitmap = frames[0]
        // 16'nın katı olması gerekiyor (codec gereksinimleri)
        val width = (firstBitmap.width / 16) * 16
        val height = (firstBitmap.height / 16) * 16

        Log.d(TAG, "Encoding ${frames.size} frames, original: ${firstBitmap.width}x${firstBitmap.height}, adjusted: ${width}x${height}")

        if (width <= 0 || height <= 0) {
            Log.e(TAG, "Invalid dimensions")
            return false
        }

        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var trackIndex = -1
        var muxerStarted = false

        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, 8_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }

            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

            val inputSurface = encoder.createInputSurface()
            encoder.start()

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val bufferInfo = MediaCodec.BufferInfo()

            for ((index, bitmap) in frames.withIndex()) {
                val canvas = inputSurface.lockCanvas(null)
                canvas.drawColor(Color.BLACK)

                // Bitmap'i canvas boyutuna ölçekle
                val scaleX = width.toFloat() / bitmap.width
                val scaleY = height.toFloat() / bitmap.height
                val scale = minOf(scaleX, scaleY)

                val scaledWidth = (bitmap.width * scale).toInt()
                val scaledHeight = (bitmap.height * scale).toInt()
                val left = (width - scaledWidth) / 2f
                val top = (height - scaledHeight) / 2f

                val destRect = android.graphics.RectF(left, top, left + scaledWidth, top + scaledHeight)
                canvas.drawBitmap(bitmap, null, destRect, null)

                inputSurface.unlockCanvasAndPost(canvas)

                // Drain encoder
                while (true) {
                    val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                    when {
                        outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> break
                        outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                trackIndex = muxer.addTrack(encoder.outputFormat)
                                muxer.start()
                                muxerStarted = true
                            }
                        }
                        outputIndex >= 0 -> {
                            val data = encoder.getOutputBuffer(outputIndex)!!
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                                bufferInfo.size = 0
                            }
                            if (bufferInfo.size > 0 && muxerStarted) {
                                data.position(bufferInfo.offset)
                                data.limit(bufferInfo.offset + bufferInfo.size)
                                muxer.writeSampleData(trackIndex, data, bufferInfo)
                            }
                            encoder.releaseOutputBuffer(outputIndex, false)
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                        }
                    }
                }

                onProgress?.invoke(index.toDouble() / frames.size)
            }

            // Signal end
            encoder.signalEndOfInputStream()

            // Final drain
            while (true) {
                val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                if (outputIndex >= 0) {
                    val data = encoder.getOutputBuffer(outputIndex)!!
                    if (bufferInfo.size > 0 && muxerStarted) {
                        data.position(bufferInfo.offset)
                        data.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(trackIndex, data, bufferInfo)
                    }
                    encoder.releaseOutputBuffer(outputIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                } else if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    continue
                }
            }

            Log.d(TAG, "Encoding complete!")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Encode failed", e)
            return false
        } finally {
            try {
                encoder?.stop()
                encoder?.release()
                if (muxerStarted) muxer?.stop()
                muxer?.release()
            } catch (e: Exception) {}
        }
    }
}
