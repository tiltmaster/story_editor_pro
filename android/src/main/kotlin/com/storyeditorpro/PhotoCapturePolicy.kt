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

/** A terminal reply and ownership of the JPEG are separate: timeout may reply
 * immediately, but must leave the file alone while orientation correction runs. */
internal class PhotoCaptureCompletionGate {
    private enum class Terminal { PENDING, SUCCESS, FAILURE }
    private var terminal = Terminal.PENDING
    private var processing = false

    @Synchronized
    fun tryBeginProcessing(): Boolean {
        if (terminal != Terminal.PENDING || processing) return false
        processing = true
        return true
    }

    @Synchronized
    fun finishProcessing() {
        processing = false
    }

    @Synchronized
    fun trySucceed(): Boolean {
        if (terminal != Terminal.PENDING || processing) return false
        terminal = Terminal.SUCCESS
        return true
    }

    @Synchronized
    fun tryFail(): Boolean {
        if (terminal != Terminal.PENDING) return false
        terminal = Terminal.FAILURE
        return true
    }

    @Synchronized
    fun cleanupIfFailed(cleanup: () -> Unit) {
        if (terminal == Terminal.FAILURE && !processing) cleanup()
    }
}
