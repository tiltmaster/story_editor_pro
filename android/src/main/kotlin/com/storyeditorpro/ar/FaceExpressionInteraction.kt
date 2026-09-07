package com.storyeditorpro.ar

import kotlin.math.PI
import kotlin.math.hypot
import kotlin.math.sin

internal data class FaceExpression(
    val mouthOpenRatio: Float = 0f,
    val leftEyeOpenRatio: Float = .3f,
    val rightEyeOpenRatio: Float = .3f,
    val valid: Boolean = true,
) {
    companion object {
        /** All landmarks must use the same pixel space, not unequal x/y normalization. */
        fun fromLandmarks(point: (Int) -> Point3f): FaceExpression {
            fun distance(a: Int, b: Int): Float = point(a).let { first -> point(b).let { second ->
                hypot(first.x - second.x, first.y - second.y)
            } }
            fun ratio(opening: Float, width: Float): Float =
                if (opening.isFinite() && width.isFinite() && width > .0001f) opening / width else Float.NaN
            val mouth = ratio(distance(13, 14), distance(61, 291))
            val left = ratio((distance(159, 145) + distance(158, 153)) * .5f, distance(33, 133))
            val right = ratio((distance(386, 374) + distance(385, 380)) * .5f, distance(362, 263))
            return if (mouth.isFinite() && left.isFinite() && right.isFinite()) FaceExpression(mouth, left, right)
                else FaceExpression(valid = false)
        }
    }
}

internal data class ExpressionReaction(val mouthBurst: Float, val winkBurst: Float)

/** Hysteresis and refractory periods turn measured expressions into deliberate gestures. */
internal class FaceExpressionInteraction {
    private var mouthArmed = true
    private var winkArmed = true
    private var mouthTriggerMs = -10_000L
    private var winkTriggerMs = -10_000L
    private var lastPoseMs = -1L

    fun update(expression: FaceExpression, poseMs: Long, nowMs: Long): ExpressionReaction {
        if (lastPoseMs >= 0L && (poseMs < lastPoseMs || poseMs - lastPoseMs > 350L)) reset()
        if (expression.valid && poseMs > lastPoseMs) {
            lastPoseMs = poseMs
            if (expression.mouthOpenRatio <= .14f) mouthArmed = true
            if (expression.mouthOpenRatio >= .22f) {
                if (mouthArmed && poseMs - mouthTriggerMs >= 650L) mouthTriggerMs = poseMs
                mouthArmed = false
            }
            val left = expression.leftEyeOpenRatio
            val right = expression.rightEyeOpenRatio
            if (left >= .20f && right >= .20f) winkArmed = true
            val wink = (left <= .13f && right >= .20f) || (right <= .13f && left >= .20f)
            if (wink) {
                if (winkArmed && poseMs - winkTriggerMs >= 650L) winkTriggerMs = poseMs
                winkArmed = false
            }
        }
        fun envelope(start: Long, duration: Long): Float {
            val age = nowMs - start
            return if (age in 0..duration) sin(PI * age / duration).toFloat() else 0f
        }
        return ExpressionReaction(envelope(mouthTriggerMs, 750L), envelope(winkTriggerMs, 650L))
    }

    fun reset() {
        mouthArmed = true; winkArmed = true
        mouthTriggerMs = -10_000L; winkTriggerMs = -10_000L; lastPoseMs = -1L
    }
}
