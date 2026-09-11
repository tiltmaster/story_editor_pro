package com.storyeditorpro.ar

import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Person confidence is supplied by the bundled neural segmentation model. */
internal object BackgroundMaskPolicy {
    // Allow a slow inference during encoder startup without toggling capture
    // readiness on every frame. Display continuity is managed separately.
    const val MAX_AGE_MS = 1000L
    fun isFresh(capturedMs: Long, nowMs: Long): Boolean = nowMs - capturedMs in 0..MAX_AGE_MS

    fun backgroundAlpha(personConfidence: Float): Int {
        if (!personConfidence.isFinite()) return 0
        // Soft matte edges keep hair detail without a hard cutout border.
        val p = ((personConfidence - .15f) / .7f).coerceIn(0f, 1f)
        return ((1f - p * p * (3f - 2f * p)) * 255f).roundToInt()
    }

    fun color(style: Int, x: Float, y: Float): Int {
        // Custom media supplies the RGB image; this bitmap contributes alpha only.
        if (style == 5) return 0xFFFFFF
        require(style in 1..3)
        val radius = sqrt((x - .5f) * (x - .5f) * .65f + (y - .35f) * (y - .35f))
        val glow = (1f - radius / .85f).coerceIn(0f, 1f)
        val top: Int
        val bottom: Int
        when (style) {
            1 -> { top = 0x484553; bottom = 0x24272E }
            2 -> { top = 0x905274; bottom = 0xF1B88D }
            else -> { top = 0x10213F; bottom = 0x1B3863 }
        }
        fun component(shift: Int): Int {
            val a = (top shr shift) and 255
            val b = (bottom shr shift) and 255
            val light = if (style == 1) 52f else if (style == 2) 18f else 22f
            return (a + (b - a) * y.coerceIn(0f, 1f) + light * glow * glow).roundToInt().coerceIn(0, 255)
        }
        return (component(16) shl 16) or (component(8) shl 8) or component(0)
    }
}
