package com.storyeditorpro

internal enum class CameraLens {
    BACK,
    FRONT,
}

/** Pure transaction plan: availability is established before CameraX is disturbed. */
internal data class CameraSwitchPlan(
    val previous: CameraLens,
    val target: CameraLens,
    val shouldUnbind: Boolean,
) {
    fun lensAfter(bindSucceeded: Boolean): CameraLens =
        if (shouldUnbind && bindSucceeded) target else previous
}

internal object CameraSwitchPolicy {
    fun plan(current: CameraLens, targetAvailable: Boolean): CameraSwitchPlan {
        val target = if (current == CameraLens.BACK) CameraLens.FRONT else CameraLens.BACK
        return CameraSwitchPlan(current, target, targetAvailable)
    }
}
