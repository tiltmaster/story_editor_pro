package com.storyeditorpro.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class FacePoseEstimatorTest {
    @Test
    fun eyeOrderingIsStableAcrossMirroredLandmarkSemantics() {
        val visualLeft = Point3f(0.30f, 0.42f, -0.05f)
        val visualRight = Point3f(0.70f, 0.46f, -0.04f)
        val nose = Point3f(0.54f, 0.58f, -0.12f)

        val forward = FacePoseEstimator.estimate(visualLeft, visualRight, nose, 1L)
        val reversed = FacePoseEstimator.estimate(visualRight, visualLeft, nose, 1L)

        assertEquals(forward.leftEye, reversed.leftEye)
        assertEquals(forward.rightEye, reversed.rightEye)
        assertEquals(forward.yawRadians, reversed.yawRadians, 0.0001f)
        assertTrue(forward.leftEye.x < forward.rightEye.x)
    }

    @Test
    fun rollAxisCannotJumpByPiWhenEyeLabelsReverse() {
        val pose = FacePoseEstimator.estimate(
            Point3f(0.75f, 0.48f, 0f),
            Point3f(0.25f, 0.40f, 0f),
            Point3f(0.50f, 0.60f, 0f),
            1L,
        )
        val roll = kotlin.math.atan2(
            pose.rightEye.y - pose.leftEye.y,
            pose.rightEye.x - pose.leftEye.x,
        )

        assertTrue(abs(roll) < Math.PI / 2)
    }

}
