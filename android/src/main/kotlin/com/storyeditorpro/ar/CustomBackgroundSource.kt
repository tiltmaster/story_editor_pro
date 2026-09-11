package com.storyeditorpro.ar

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.SystemClock
import androidx.exifinterface.media.ExifInterface

/** Decoding stays on the segmentation worker, never the camera or GL thread. */
internal class CustomBackgroundSource {
    @Volatile private var requested = "" to false
    @Volatile private var started = SystemClock.elapsedRealtime()
    private var loaded = "" to false
    private var retriever: MediaMetadataRetriever? = null
    private var image: Bitmap? = null
    private var durationMs = 1L
    @Volatile private var bucket = -1L

    fun select(path: String, video: Boolean) { requested = path to video; restart() }
    fun restart() { started = SystemClock.elapsedRealtime(); bucket = -1 }

    fun frame(): Bitmap? {
        val target = requested
        if (target.first.isEmpty()) return null
        if (target != loaded) {
            close()
            if (target.second) {
                val reader = MediaMetadataRetriever()
                try {
                    reader.setDataSource(target.first)
                    durationMs = (reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0).coerceAtLeast(1)
                    retriever = reader
                } catch (error: Exception) { reader.release(); throw error }
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(target.first, bounds)
                val options = BitmapFactory.Options().apply {
                    var sample = 1
                    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1920) sample *= 2
                    inSampleSize = sample
                }
                val decoded = requireNotNull(BitmapFactory.decodeFile(target.first, options))
                val exif = ExifInterface(target.first)
                val transform = Matrix().apply {
                    if (exif.isFlipped) postScale(-1f, 1f)
                    postRotate(exif.rotationDegrees.toFloat())
                }
                image = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, transform, true)
                if (image !== decoded) decoded.recycle()
            }
            loaded = target; bucket = -1
        }
        val reader = retriever ?: return image
        val elapsed = (SystemClock.elapsedRealtime() - started).coerceAtLeast(0) % durationMs
        val nextBucket = elapsed / 100
        if (bucket != nextBucket) {
            val frame = if (Build.VERSION.SDK_INT >= 27) reader.getScaledFrameAtTime(elapsed * 1000,
                MediaMetadataRetriever.OPTION_CLOSEST, 720, 1280)
                else reader.getFrameAtTime(elapsed * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
            if (frame != null) { image = frame; bucket = nextBucket }
        }
        return image
    }

    fun close() { retriever?.release(); retriever = null; image = null; loaded = "" to false }
}
