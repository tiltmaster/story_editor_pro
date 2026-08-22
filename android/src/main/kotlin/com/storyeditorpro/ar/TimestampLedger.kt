package com.storyeditorpro.ar

internal data class TrackedFrame(val timestampNs: Long, val rotation: Int)

/** Bridges CameraX nanoseconds to MediaPipe's strictly increasing milliseconds. */
internal class TimestampLedger(private val capacity: Int = 12) {
    private val pending = LinkedHashMap<Long, TrackedFrame>()
    private var lastTimestampMs = -1L

    init {
        require(capacity > 0)
    }

    @Synchronized
    fun record(timestampNs: Long, rotation: Int): Long {
        var timestampMs = timestampNs / 1_000_000L
        if (timestampMs <= lastTimestampMs) timestampMs = lastTimestampMs + 1L
        lastTimestampMs = timestampMs
        pending[timestampMs] = TrackedFrame(timestampNs, rotation)
        while (pending.size > capacity) pending.remove(pending.entries.first().key)
        return timestampMs
    }

    @Synchronized
    fun take(timestampMs: Long): TrackedFrame? = pending.remove(timestampMs)

    @Synchronized
    fun clear() = pending.clear()

    @Synchronized
    fun size(): Int = pending.size
}
