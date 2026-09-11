package com.storyeditorpro.ar

import com.storyeditorpro.CameraViewportPolicy
import org.junit.Assert.*
import org.junit.Test

class OverlayGeometryTest {
    @Test fun nonZeroCropAndAllSensorRotationsPreserveEveryCornerAndCenter() {
        for (rotation in listOf(0, 90, 180, 270)) {
            val geometry = OverlayGeometry(420f, 180f, 1920f, 1080f, rotation)
            for ((x, y) in listOf(0f to 0f, 1f to 0f, 1f to 1f, 0f to 1f, .5f to .5f)) {
                val buffer = geometry.uprightToBuffer(x * geometry.width, y * geometry.height)
                assertTrue(buffer.x in 420f..2340f)
                assertTrue(buffer.y in 180f..1260f)
                val restored = geometry.bufferToUpright(buffer.x, buffer.y)
                assertEquals(x * geometry.width, restored.x, .0001f)
                assertEquals(y * geometry.height, restored.y, .0001f)
            }
        }
    }

    @Test fun portraitViewportDoesNotDependOnLandscapeSurfaceResolution() {
        assertFalse(CameraViewportPolicy.isLandscape(0))
        assertFalse(CameraViewportPolicy.isLandscape(2))
        assertTrue(CameraViewportPolicy.isLandscape(1))
        assertTrue(CameraViewportPolicy.isLandscape(3))
    }
}
