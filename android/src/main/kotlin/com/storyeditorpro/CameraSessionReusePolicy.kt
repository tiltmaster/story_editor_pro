package com.storyeditorpro

/** Pure predicate used to keep a prewarmed CameraX session alive across Flutter adoption. */
internal object CameraSessionReusePolicy {
    fun shouldReuse(
        currentLens: CameraLens,
        requestedLens: CameraLens,
        hasCamera: Boolean,
        hasTexture: Boolean,
        hasRequiredUseCases: Boolean,
        executorRunning: Boolean,
    ): Boolean =
        currentLens == requestedLens &&
            hasCamera &&
            hasTexture &&
            hasRequiredUseCases &&
            executorRunning
}
