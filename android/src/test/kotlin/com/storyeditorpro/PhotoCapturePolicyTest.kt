package com.storyeditorpro

import androidx.camera.core.ImageCapture
import java.io.File
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

    @Test
    fun timedOutPhotoNeverStartsLateImageProcessing() {
        val gate = PhotoCaptureCompletionGate()
        val file = File.createTempFile("capture-late", ".jpg")
        try {
            file.writeText("captured")
            assertTrue(gate.tryFail())
            gate.cleanupIfFailed { file.delete() }
            assertFalse(gate.tryBeginProcessing())
            assertFalse(gate.trySucceed())
            assertFalse(file.exists())
        } finally { file.delete() }
    }

    @Test
    fun timeoutDuringProcessingRepliesOnceAndDefersCleanupUntilOwnerFinishes() {
        val gate = PhotoCaptureCompletionGate()
        val file = File.createTempFile("capture-processing", ".jpg")
        val entered = CountDownLatch(1)
        val finish = CountDownLatch(1)
        val done = CountDownLatch(1)
        val failures = AtomicInteger()
        val replies = AtomicInteger()
        val executor = Executors.newSingleThreadExecutor()
        try {
            file.writeText("original")
            executor.execute {
                try {
                    if (!gate.tryBeginProcessing()) { failures.incrementAndGet(); return@execute }
                    entered.countDown()
                    if (!finish.await(2, TimeUnit.SECONDS) || !file.exists()) failures.incrementAndGet()
                    file.writeText("corrected")
                    gate.finishProcessing()
                    gate.cleanupIfFailed { file.delete() }
                    if (gate.trySucceed()) replies.incrementAndGet()
                } catch (_: Exception) { failures.incrementAndGet() }
                finally { done.countDown() }
            }
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            if (gate.tryFail()) replies.incrementAndGet()
            gate.cleanupIfFailed { file.delete() }
            assertTrue("Timeout must not delete the file owned by correction", file.exists())
            assertFalse(gate.tryFail())
            finish.countDown()
            assertTrue(done.await(2, TimeUnit.SECONDS))
            assertEquals(0, failures.get())
            assertEquals(1, replies.get())
            assertFalse("Timed-out output is cleaned after correction", file.exists())
        } finally { finish.countDown(); executor.shutdownNow(); file.delete() }
    }

    @Test
    fun successfulPhotoCannotBeDeletedByLateErrorOrDuplicateCallback() {
        val gate = PhotoCaptureCompletionGate()
        val file = File.createTempFile("capture-success", ".jpg")
        try {
            file.writeText("valid photo")
            assertTrue(gate.tryBeginProcessing())
            assertFalse(gate.trySucceed())
            gate.finishProcessing()
            assertTrue(gate.trySucceed())
            assertFalse(gate.tryFail())
            assertFalse(gate.tryBeginProcessing())
            gate.cleanupIfFailed { file.delete() }
            assertEquals("valid photo", file.readText())
        } finally { file.delete() }
    }

    @Test
    fun captureErrorAfterProcessingCleansRejectedOutputWithoutSuccess() {
        val gate = PhotoCaptureCompletionGate()
        val file = File.createTempFile("capture-invalid", ".jpg")
        try {
            assertTrue(gate.tryBeginProcessing())
            gate.finishProcessing()
            assertTrue(gate.tryFail())
            gate.cleanupIfFailed { file.delete() }
            assertFalse(gate.trySucceed())
            assertFalse(file.exists())
        } finally { file.delete() }
    }
}
