package com.storyeditorpro.ar

internal object FaceArContract {
    const val METHOD_CHANNEL = "story_editor_pro/ar"
    const val EVENT_CHANNEL = "story_editor_pro/ar_events"
    const val BACKEND = "mediapipe_camerax_overlay"
    const val LENS_NONE = "none"
    const val LENS_GLASSES_CLASSIC = "glasses_classic"
    val lensIds = setOf(LENS_NONE, LENS_GLASSES_CLASSIC)
}

internal enum class FaceArState(val wire: String) {
    DISABLED("disabled"),
    PREPARING("preparing"),
    READY("ready"),
    ACTIVE("active"),
    UNAVAILABLE("unavailable"),
}

internal data class FaceArSettings(val lensId: String, val intensity: Float) {
    companion object {
        fun validated(lensId: String, intensity: Number): FaceArSettings {
            require(lensId in FaceArContract.lensIds) { "Unsupported lensId" }
            val value = intensity.toFloat()
            require(value.isFinite()) { "intensity must be finite" }
            return FaceArSettings(lensId, value.coerceIn(0f, 1f))
        }
    }
}

internal data class PrepareDecision(
    val accepted: Boolean,
    val startWork: Boolean,
    val state: FaceArState,
)

/** Pure state machine kept independent of Android so it can be unit tested. */
internal class FaceArStateMachine(private val supported: Boolean) {
    private var prepared = false
    private var preparing = false
    private var enabled = false
    private var explicitlyDisabled = false
    private var disposed = false

    @Volatile
    var state: FaceArState = if (supported) FaceArState.DISABLED else FaceArState.UNAVAILABLE
        private set

    @Synchronized
    fun beginPrepare(): PrepareDecision {
        if (!supported || disposed) {
            state = FaceArState.UNAVAILABLE
            return PrepareDecision(false, false, state)
        }
        explicitlyDisabled = false
        if (prepared) {
            state = if (enabled) FaceArState.ACTIVE else FaceArState.READY
            return PrepareDecision(true, false, state)
        }
        if (preparing) return PrepareDecision(true, false, state)
        preparing = true
        state = FaceArState.PREPARING
        return PrepareDecision(true, true, state)
    }

    @Synchronized
    fun setEnabled(value: Boolean): PrepareDecision {
        if (!supported || disposed) {
            state = FaceArState.UNAVAILABLE
            return PrepareDecision(false, false, state)
        }
        enabled = value
        explicitlyDisabled = !value
        if (!value) {
            state = FaceArState.DISABLED
            return PrepareDecision(true, false, state)
        }
        if (prepared) {
            state = FaceArState.ACTIVE
            return PrepareDecision(true, false, state)
        }
        val start = !preparing
        if (start) preparing = true
        state = FaceArState.PREPARING
        return PrepareDecision(true, start, state)
    }

    @Synchronized
    fun markReady(): FaceArState {
        if (disposed) return FaceArState.UNAVAILABLE.also { state = it }
        prepared = true
        preparing = false
        state = when {
            enabled -> FaceArState.ACTIVE
            explicitlyDisabled -> FaceArState.DISABLED
            else -> FaceArState.READY
        }
        return state
    }

    @Synchronized
    fun markUnavailable(): FaceArState {
        prepared = false
        preparing = false
        state = FaceArState.UNAVAILABLE
        return state
    }

    @Synchronized
    fun isActive(): Boolean = state == FaceArState.ACTIVE

    @Synchronized
    fun reset(): FaceArState {
        if (disposed || !supported) {
            state = FaceArState.UNAVAILABLE
            return state
        }
        prepared = false
        preparing = false
        enabled = false
        explicitlyDisabled = true
        return FaceArState.DISABLED.also { state = it }
    }

    @Synchronized
    fun dispose(): FaceArState {
        disposed = true
        prepared = false
        preparing = false
        enabled = false
        return FaceArState.DISABLED.also { state = it }
    }
}
