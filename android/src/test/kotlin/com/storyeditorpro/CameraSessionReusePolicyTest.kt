package com.storyeditorpro

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraSessionReusePolicyTest {
    @Test
    fun activeSameFacingPrewarmIsReusable() {
        assertTrue(
            CameraSessionReusePolicy.shouldReuse(
                currentLens = CameraLens.BACK,
                requestedLens = CameraLens.BACK,
                hasCamera = true,
                hasTexture = true,
                hasRequiredUseCases = true,
                executorRunning = true,
            ),
        )
    }

    @Test
    fun differentFacingAlwaysRequiresInitialization() {
        assertFalse(
            CameraSessionReusePolicy.shouldReuse(
                CameraLens.BACK,
                CameraLens.FRONT,
                hasCamera = true,
                hasTexture = true,
                hasRequiredUseCases = true,
                executorRunning = true,
            ),
        )
    }

    @Test
    fun disposedOrIncompleteSessionIsNeverReused() {
        val complete = booleanArrayOf(true, true, true, true)
        for (missingIndex in complete.indices) {
            val state = complete.copyOf().also { it[missingIndex] = false }
            assertFalse(
                CameraSessionReusePolicy.shouldReuse(
                    CameraLens.FRONT,
                    CameraLens.FRONT,
                    hasCamera = state[0],
                    hasTexture = state[1],
                    hasRequiredUseCases = state[2],
                    executorRunning = state[3],
                ),
            )
        }
    }
}
