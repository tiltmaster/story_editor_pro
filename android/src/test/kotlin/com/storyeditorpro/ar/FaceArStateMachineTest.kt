package com.storyeditorpro.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FaceArStateMachineTest {
    @Test
    fun prepareIsIdempotentAndNonBlocking() {
        val machine = FaceArStateMachine(true)
        val first = machine.beginPrepare()
        val second = machine.beginPrepare()
        assertTrue(first.accepted)
        assertTrue(first.startWork)
        assertTrue(second.accepted)
        assertFalse(second.startWork)
        assertEquals(FaceArState.PREPARING, second.state)
    }

    @Test
    fun enableBeforeReadyBecomesActive() {
        val machine = FaceArStateMachine(true)
        assertTrue(machine.setEnabled(true).startWork)
        assertEquals(FaceArState.ACTIVE, machine.markReady())
    }

    @Test
    fun explicitDisableSurvivesAsyncPreparationCompletion() {
        val machine = FaceArStateMachine(true)
        machine.beginPrepare()
        machine.setEnabled(false)
        assertEquals(FaceArState.DISABLED, machine.markReady())
    }

    @Test
    fun readyPreparationIsIdempotentAndEnableCanToggle() {
        val machine = FaceArStateMachine(true)
        machine.beginPrepare()
        assertEquals(FaceArState.READY, machine.markReady())
        val secondPrepare = machine.beginPrepare()
        assertTrue(secondPrepare.accepted)
        assertFalse(secondPrepare.startWork)
        assertEquals(FaceArState.READY, secondPrepare.state)
        assertEquals(FaceArState.ACTIVE, machine.setEnabled(true).state)
        assertTrue(machine.isActive())
        assertEquals(FaceArState.DISABLED, machine.setEnabled(false).state)
        assertFalse(machine.isActive())
        assertEquals(FaceArState.ACTIVE, machine.setEnabled(true).state)
    }

    @Test
    fun resetAllowsACompleteNewPreparationCycle() {
        val machine = FaceArStateMachine(true)
        machine.setEnabled(true)
        machine.markReady()
        assertEquals(FaceArState.DISABLED, machine.reset())
        val next = machine.beginPrepare()
        assertTrue(next.accepted)
        assertTrue(next.startWork)
        assertEquals(FaceArState.PREPARING, next.state)
    }

    @Test
    fun unavailableCanRetryButDisposedIsTerminal() {
        val machine = FaceArStateMachine(true)
        machine.beginPrepare()
        assertEquals(FaceArState.UNAVAILABLE, machine.markUnavailable())
        val retry = machine.beginPrepare()
        assertTrue(retry.accepted)
        assertTrue(retry.startWork)
        machine.dispose()
        val afterDispose = machine.beginPrepare()
        assertFalse(afterDispose.accepted)
        assertFalse(afterDispose.startWork)
        assertEquals(FaceArState.UNAVAILABLE, afterDispose.state)
    }

    @Test
    fun unsupportedMachineRejectsEveryEntryPoint() {
        val machine = FaceArStateMachine(false)
        assertEquals(FaceArState.UNAVAILABLE, machine.state)
        assertFalse(machine.beginPrepare().accepted)
        assertFalse(machine.setEnabled(true).accepted)
        assertEquals(FaceArState.UNAVAILABLE, machine.reset())
    }
}
