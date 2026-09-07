package com.storyeditorpro.ar

/** CameraX applies crop, clockwise rotation, then output mirroring, in that order. */
internal data class OverlayGeometry(
    val left: Float,
    val top: Float,
    val cropWidth: Float,
    val cropHeight: Float,
    val rotationDegrees: Int,
) {
    private val rotation = ((rotationDegrees % 360) + 360) % 360
    val width: Float get() = if (rotation % 180 == 0) cropWidth else cropHeight
    val height: Float get() = if (rotation % 180 == 0) cropHeight else cropWidth

    fun bufferToUpright(x: Float, y: Float): Point3f {
        val localX = x - left
        val localY = y - top
        return when (rotation) {
            90 -> Point3f(cropHeight - localY, localX, 0f)
            180 -> Point3f(cropWidth - localX, cropHeight - localY, 0f)
            270 -> Point3f(localY, cropWidth - localX, 0f)
            else -> Point3f(localX, localY, 0f)
        }
    }

    fun uprightToBuffer(x: Float, y: Float): Point3f = when (rotation) {
        90 -> Point3f(left + y, top + cropHeight - x, 0f)
        180 -> Point3f(left + cropWidth - x, top + cropHeight - y, 0f)
        270 -> Point3f(left + cropWidth - y, top + x, 0f)
        else -> Point3f(left + x, top + y, 0f)
    }

    companion object {
        fun shouldPreMirror(frameMirroring: Boolean, requestedOutputMirroring: Boolean): Boolean =
            frameMirroring != requestedOutputMirroring
    }
}
