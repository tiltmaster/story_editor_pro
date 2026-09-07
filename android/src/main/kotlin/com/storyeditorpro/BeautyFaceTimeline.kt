package com.storyeditorpro

internal data class BeautyFacePose(val leftX: Float, val leftY: Float, val rightX: Float, val rightY: Float)

/** Recording-relative coordinates; loss markers and stale samples disable deformation. */
internal class BeautyFaceTimeline(entries: List<Map<String, Any?>>) {
    private data class Sample(val timeMs: Long, val pose: BeautyFacePose?)
    private val samples = entries.mapNotNull { entry ->
        val rawTime = (entry["timeMs"] as? Number)?.toDouble() ?: return@mapNotNull null
        if (!rawTime.isFinite() || rawTime < 0.0) return@mapNotNull null
        val values = listOf("leftX", "leftY", "rightX", "rightY").map { (entry[it] as? Number)?.toFloat() }
        val pose = if (values.all { it != null && it.isFinite() && it in 0f..1f }) {
            BeautyFacePose(values[0]!!, values[1]!!, values[2]!!, values[3]!!)
        } else null
        Sample(rawTime.toLong(), pose)
    }.sortedBy { it.timeMs }

    fun at(timeMs: Long): BeautyFacePose? {
        var low = 0
        var high = samples.size - 1
        var index = -1
        while (low <= high) {
            val middle = (low + high).ushr(1)
            if (samples[middle].timeMs <= timeMs) { index = middle; low = middle + 1 }
            else high = middle - 1
        }
        if (index < 0) return null
        val sample = samples[index]
        return sample.pose?.takeIf { timeMs - sample.timeMs <= 250L }
    }
}
