package com.storyeditorpro

import org.junit.Assert.*
import org.junit.Test

class MediaTransformTest {
    @Test fun identityFillsCanvas() {
        assertArrayEquals(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f),
            MediaTransform.vertices(1.0, 0.0, 0.0), .0001f)
    }

    @Test fun scalingAroundCenterThenTranslatingKeepsCanvasUnits() {
        // 50% width/height media moved right 25% and down 10%.
        assertArrayEquals(floatArrayOf(0f, -.7f, 1f, -.7f, 0f, .3f, 1f, .3f),
            MediaTransform.vertices(.5, .25, .1), .0001f)
    }

    @Test fun enlargedMediaCropsAtViewportWithoutClampingTextureEdges() {
        assertArrayEquals(floatArrayOf(-2f, -2f, 2f, -2f, -2f, 2f, 2f, 2f),
            MediaTransform.vertices(2.0, 0.0, 0.0), .0001f)
        assertArrayEquals(MediaTransform.vertices(5.0, 0.0, 0.0),
            MediaTransform.vertices(99.0, 0.0, 0.0), .0001f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun nonfinitePositionNeverReachesGpu() {
        MediaTransform.vertices(1.0, Double.NaN, 0.0)
    }
}
