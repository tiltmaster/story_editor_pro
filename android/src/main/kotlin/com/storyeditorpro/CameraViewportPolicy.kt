package com.storyeditorpro

/** Android Surface rotations: 0/2 portrait, 1/3 landscape. */
internal object CameraViewportPolicy {
    fun isLandscape(surfaceRotation: Int): Boolean = surfaceRotation == 1 || surfaceRotation == 3
}
