package com.storyeditorpro.ar

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class FaceExpressionInteractionTest {
    @Test fun neutralAndBothEyeBlinkDoNotTriggerGestures() {
        val policy = FaceExpressionInteraction()
        assertEquals(ExpressionReaction(0f, 0f), policy.update(FaceExpression(), 0L, 0L))
        assertEquals(ExpressionReaction(0f, 0f), policy.update(FaceExpression(0f, .05f, .05f), 100L, 300L))
    }

    @Test fun heldMouthDoesNotRetriggerAndFastRepeatedGestureIsSuppressed() {
        val policy = FaceExpressionInteraction()
        val open = FaceExpression(.4f)
        policy.update(open, 0L, 0L)
        assertEquals(1f, policy.update(open, 0L, 375L).mouthBurst, .0001f)
        policy.update(FaceExpression(), 100L, 100L)
        policy.update(open, 200L, 200L) // Refractory period: no new event.
        policy.update(open, 500L, 500L)
        assertEquals(0f, policy.update(open, 800L, 800L).mouthBurst, .0001f)
        policy.update(FaceExpression(), 900L, 900L)
        policy.update(open, 1000L, 1000L)
        assertEquals(1f, policy.update(open, 1000L, 1375L).mouthBurst, .0001f)
    }

    @Test fun unilateralWinkCreatesOneVisibleFlutterEnvelope() {
        val policy = FaceExpressionInteraction()
        val wink = FaceExpression(0f, .08f, .27f)
        policy.update(wink, 0L, 0L)
        assertEquals(1f, policy.update(wink, 0L, 325L).winkBurst, .0001f)
        policy.update(wink, 300L, 300L)
        policy.update(wink, 600L, 600L)
        assertEquals(0f, policy.update(wink, 900L, 900L).winkBurst, .0001f)
        policy.update(FaceExpression(), 1000L, 1000L)
        policy.update(FaceExpression(0f, .27f, .08f), 1100L, 1100L)
        assertEquals(1f, policy.update(wink, 1100L, 1425L).winkBurst, .0001f)
    }

    @Test fun invalidLandmarksNeverCreateClosureOrMouthReactions() {
        val invalid = FaceExpression.fromLandmarks { Point3f(0f, 0f, 0f) }
        assertFalse(invalid.valid)
        assertEquals(ExpressionReaction(0f, 0f), FaceExpressionInteraction().update(invalid, 0L, 300L))
    }

    @Test fun measuredRatiosAreInvariantToPixelScaleTranslationAndRoll() {
        val points = mapOf(
            61 to p(0f, 50f), 291 to p(100f, 50f), 13 to p(50f, 40f), 14 to p(50f, 60f),
            33 to p(0f, 0f), 133 to p(20f, 0f), 159 to p(5f, -3f), 145 to p(5f, 3f), 158 to p(15f, -3f), 153 to p(15f, 3f),
            362 to p(60f, 0f), 263 to p(80f, 0f), 386 to p(65f, -1f), 374 to p(65f, 1f), 385 to p(75f, -1f), 380 to p(75f, 1f),
        )
        val expression = FaceExpression.fromLandmarks { points.getValue(it) }
        val transformed = FaceExpression.fromLandmarks { points.getValue(it).let { pt ->
            p((pt.x * cos(.7f) - pt.y * sin(.7f)) * 2.8f + 30f,
                (pt.x * sin(.7f) + pt.y * cos(.7f)) * 2.8f - 50f)
        } }
        assertTrue(transformed.valid)
        assertEquals(.2f, expression.mouthOpenRatio, .0001f)
        assertEquals(.3f, expression.leftEyeOpenRatio, .0001f)
        assertEquals(.1f, expression.rightEyeOpenRatio, .0001f)
        assertEquals(expression.mouthOpenRatio, transformed.mouthOpenRatio, .0001f)
        assertEquals(expression.leftEyeOpenRatio, transformed.leftEyeOpenRatio, .0001f)
        assertEquals(expression.rightEyeOpenRatio, transformed.rightEyeOpenRatio, .0001f)
    }

    private fun p(x: Float, y: Float) = Point3f(x, y, 0f)
}
