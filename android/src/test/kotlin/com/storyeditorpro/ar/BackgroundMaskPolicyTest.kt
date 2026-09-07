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

    @Test fun staleAndFutureMasksAreNeverReused() {
        assertTrue(BackgroundMaskPolicy.isFresh(1000, 1250))
        assertFalse(BackgroundMaskPolicy.isFresh(1000, 1251))
        assertFalse(BackgroundMaskPolicy.isFresh(1001, 1000))
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
