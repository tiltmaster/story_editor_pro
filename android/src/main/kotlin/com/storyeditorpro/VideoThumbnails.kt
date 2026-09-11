package com.storyeditorpro

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream

internal object VideoThumbnails {
    fun read(path: String, count: Int): List<ByteArray> {
        val reader = MediaMetadataRetriever()
        try {
            reader.setDataSource(path)
            val duration = (reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000
            require(duration > 0)
            return (0 until count).map { index ->
                val time = duration * index / count
                val frame = if (Build.VERSION.SDK_INT >= 27) reader.getScaledFrameAtTime(time,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 160, 280)
                    else reader.getFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                requireNotNull(frame)
                try { ByteArrayOutputStream().use { out ->
                    frame.compress(Bitmap.CompressFormat.JPEG, 75, out); out.toByteArray()
                } } finally { frame.recycle() }
            }
        } finally { reader.release() }
    }
}
