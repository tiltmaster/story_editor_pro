package com.storyeditorpro

import androidx.camera.core.ImageCapture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoCapturePolicyTest {
    @Test
    fun completionGateOnlyAllowsFirstTerminalCallback() {
        val gate = SingleCompletionGate()
        assertFalse(gate.isComplete())
        assertTrue(gate.tryComplete())
        assertTrue(gate.isComplete())
        assertFalse(gate.tryComplete())
    }

    @Test
    fun concurrentTimeoutAndCameraCallbackHaveExactlyOneWinner() {
        val gate = SingleCompletionGate()
        val ready = CountDownLatch(2)
        val start = CountDownLatch(1)
        val winners = AtomicInteger()
        val executor = Executors.newFixedThreadPool(2)
        repeat(2) {
            executor.execute {
                ready.countDown()
                start.await()
                if (gate.tryComplete()) winners.incrementAndGet()
            }
        }
        assertTrue(ready.await(1, TimeUnit.SECONDS))
        start.countDown()
        executor.shutdown()
        assertTrue(executor.awaitTermination(1, TimeUnit.SECONDS))
        assertEquals(1, winners.get())
    }

    @Test
    fun timeoutIsBoundedForInteractiveStoryCapture() {
        assertTrue(PhotoCapturePolicy.TIMEOUT_MS >= 5_000L)
        assertTrue(PhotoCapturePolicy.TIMEOUT_MS <= 10_000L)
    }

    @Test
    fun nativeCaptureDefaultsToFlashOff() {
        assertEquals(ImageCapture.FLASH_MODE_OFF, PhotoCapturePolicy.DEFAULT_FLASH_MODE)
    }
}
