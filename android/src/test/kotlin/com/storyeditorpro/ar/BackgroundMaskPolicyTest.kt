package com.storyeditorpro.ar

import org.junit.Assert.*
import org.junit.Test

class BackgroundMaskPolicyTest {
    @Test fun confidentPersonPixelsRemainTransparentAndBackgroundIsOpaque() {
        assertEquals(0, BackgroundMaskPolicy.backgroundAlpha(1f))
        assertEquals(255, BackgroundMaskPolicy.backgroundAlpha(0f))
        assertEquals(128, BackgroundMaskPolicy.backgroundAlpha(.5f))
        assertTrue(BackgroundMaskPolicy.backgroundAlpha(.3f) > BackgroundMaskPolicy.backgroundAlpha(.7f))
    }

    @Test fun corruptConfidenceNeverPaintsOverCameraSubject() {
        assertEquals(0, BackgroundMaskPolicy.backgroundAlpha(Float.NaN))
        assertEquals(0, BackgroundMaskPolicy.backgroundAlpha(Float.POSITIVE_INFINITY))
    }

    @Test fun captureReadinessRejectsStaleAndFutureMasks() {
        assertTrue(BackgroundMaskPolicy.isFresh(1000, 2000))
        assertFalse(BackgroundMaskPolicy.isFresh(1000, 2001))
        assertFalse(BackgroundMaskPolicy.isFresh(1001, 1000))
    }

    @Test fun slowInferenceDoesNotRemoveVisibleSceneButBlocksStaleCapture() {
        val cache = BackgroundMaskCache<String>()
        cache.update("sunset matte", 1000, 2, 7)
        assertTrue(cache.isReady(2, 7, 1500))
        assertFalse(cache.isReady(2, 7, 5000))
        assertEquals("sunset matte", cache.current(2, 7))
        cache.update("new matte", 4900, 2, 7)
        assertTrue(cache.isReady(2, 7, 5000))
        assertEquals("new matte", cache.current(2, 7))
    }

    @Test fun heldMatteCannotCrossCameraOrStyleChangesAndOffClearsIt() {
        val cache = BackgroundMaskCache<String>()
        cache.update("old camera", 1000, 2, 7)
        assertNull(cache.current(2, 8))
        assertNull(cache.current(3, 7))
        assertFalse(cache.isReady(2, 8, 1100))
        cache.clear()
        assertNull(cache.current(2, 7))
        assertFalse(cache.isReady(2, 7, 1100))
    }

    @Test fun eachAuthoredBackgroundUsesAnOpaqueRgbGradient() {
        for (style in 1..3) {
            val top = BackgroundMaskPolicy.color(style, .5f, 0f)
            val bottom = BackgroundMaskPolicy.color(style, .5f, 1f)
            assertNotEquals(top, bottom)
            assertEquals(0, top ushr 24)
            assertEquals(0, bottom ushr 24)
        }
    }
}
