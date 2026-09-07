package com.storyeditorpro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CameraSwitchPolicyTest {
    @Test
    fun unavailableOppositeLensNeverAllowsUnbind() {
        val plan = CameraSwitchPolicy.plan(CameraLens.BACK, targetAvailable = false)
        assertEquals(CameraLens.FRONT, plan.target)
        assertFalse(plan.shouldUnbind)
        assertEquals(CameraLens.BACK, plan.lensAfter(bindSucceeded = false))
        assertEquals(CameraLens.BACK, plan.lensAfter(bindSucceeded = true))
    }

    @Test
    fun successfulBindCommitsOppositeLens() {
        val plan = CameraSwitchPolicy.plan(CameraLens.BACK, targetAvailable = true)
        assertTrue(plan.shouldUnbind)
        assertEquals(CameraLens.FRONT, plan.lensAfter(bindSucceeded = true))
    }

    @Test
    fun failedBindRollsBackPreviousLensInBothDirections() {
        val backToFront = CameraSwitchPolicy.plan(CameraLens.BACK, targetAvailable = true)
        val frontToBack = CameraSwitchPolicy.plan(CameraLens.FRONT, targetAvailable = true)
        assertEquals(CameraLens.BACK, backToFront.lensAfter(bindSucceeded = false))
        assertEquals(CameraLens.FRONT, frontToBack.lensAfter(bindSucceeded = false))
        assertEquals(CameraLens.BACK, frontToBack.target)
    }
}
