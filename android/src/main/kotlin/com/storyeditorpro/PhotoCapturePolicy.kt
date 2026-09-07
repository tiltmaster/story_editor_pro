package com.storyeditorpro

import androidx.camera.core.ImageCapture
import java.util.concurrent.atomic.AtomicBoolean

internal object PhotoCapturePolicy {
    // A story-camera shutter should fail fast enough to unblock UI, while allowing slower
    // devices several frames for Camera2 and the capture effect pipeline.
    const val TIMEOUT_MS = 8_000L
    const val DEFAULT_FLASH_MODE = ImageCapture.FLASH_MODE_OFF
}

/** Guarantees that timeout, error, and success race to one platform-channel reply. */
internal class SingleCompletionGate {
    private val completed = AtomicBoolean(false)

    fun tryComplete(): Boolean = completed.compareAndSet(false, true)

    fun isComplete(): Boolean = completed.get()
}
