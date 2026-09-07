package com.storyeditorpro.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FacePoseSmootherTest {
    @Test
    fun smoothsAndClearsPose() {
        val smoother = FacePoseSmoother(alpha = 0.5f)
        smoother.update(
            FacePose(Point3f(0f, 0f, 0f), Point3f(1f, 0f, 0f), 0f, 1L),
        )
        val smoothed = smoother.update(
            FacePose(Point3f(1f, 1f, 0f), Point3f(2f, 1f, 0f), 1f, 2L),
        )!!
        assertEquals(0.5f, smoothed.leftEye.x)
        assertEquals(0.5f, smoothed.leftEye.y)
        assertEquals(0.5f, smoothed.yawRadians)
        assertNull(smoother.update(null))
    }
}
