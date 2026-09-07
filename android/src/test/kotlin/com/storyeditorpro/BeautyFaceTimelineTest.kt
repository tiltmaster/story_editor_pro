package com.storyeditorpro

import org.junit.Assert.*
import org.junit.Test

class BeautyFaceTimelineTest {
    private fun sample(timeMs: Long, leftX: Double = .3): Map<String, Any?> = mapOf(
        "timeMs" to timeMs, "leftX" to leftX, "leftY" to .35, "rightX" to .6, "rightY" to .35,
    )

    @Test fun chronologicalSamplingSupportsTrimWithoutMovingFaceKeyframes() {
        val timeline = BeautyFaceTimeline(listOf(sample(1000, .2), sample(0), sample(1100, .4)))
        assertNull(timeline.at(-1))
        assertEquals(.3f, timeline.at(0)!!.leftX, .00001f)
        assertEquals(.2f, timeline.at(1099)!!.leftX, .00001f)
        assertEquals(.4f, timeline.at(1100)!!.leftX, .00001f)
    }

    @Test fun faceLossAndStaleSamplesImmediatelyStopWarp() {
        val timeline = BeautyFaceTimeline(listOf(sample(0), mapOf("timeMs" to 100), sample(200)))
        assertNotNull(timeline.at(99))
        assertNull(timeline.at(100))
        assertNotNull(timeline.at(450))
        assertNull(timeline.at(451))
    }

    @Test fun malformedNonfiniteAndOutOfFrameLandmarksNeverReachShader() {
        for (x in listOf(Double.NaN, Double.POSITIVE_INFINITY, -.01, 1.01)) {
            assertNull(BeautyFaceTimeline(listOf(sample(0, x))).at(0))
        }
        assertNull(BeautyFaceTimeline(listOf(mapOf("timeMs" to Double.NaN))).at(0))
    }
}
