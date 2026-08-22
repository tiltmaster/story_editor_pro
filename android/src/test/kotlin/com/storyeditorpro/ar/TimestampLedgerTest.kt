package com.storyeditorpro.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class TimestampLedgerTest {
    @Test
    fun preservesExactCameraTimestampAndRotation() {
        val ledger = TimestampLedger()
        val key = ledger.record(4_123_456_789L, 270)
        assertEquals(4_123L, key)
        assertEquals(TrackedFrame(4_123_456_789L, 270), ledger.take(key))
        assertNull(ledger.take(key))
    }

    @Test
    fun producesStrictlyIncreasingMediaPipeTimestampsForSameMillisecond() {
        val ledger = TimestampLedger()
        val first = ledger.record(5_000_000L, 0)
        val second = ledger.record(5_500_000L, 0)
        assertEquals(first + 1L, second)
        assertEquals(5_000_000L, ledger.take(first)?.timestampNs)
        assertEquals(5_500_000L, ledger.take(second)?.timestampNs)
    }

    @Test
    fun evictsOldestFramesAtCapacityAndCanClear() {
        val ledger = TimestampLedger(capacity = 2)
        val first = ledger.record(1_000_000L, 0)
        val second = ledger.record(2_000_000L, 0)
        val third = ledger.record(3_000_000L, 0)
        assertEquals(2, ledger.size())
        assertNull(ledger.take(first))
        assertEquals(TrackedFrame(2_000_000L, 0), ledger.take(second))
        assertEquals(TrackedFrame(3_000_000L, 0), ledger.take(third))
        ledger.record(4_000_000L, 0)
        ledger.clear()
        assertEquals(0, ledger.size())
    }

    @Test
    fun rejectsNonPositiveCapacity() {
        try {
            TimestampLedger(0)
            fail("zero capacity should fail")
        } catch (_: IllegalArgumentException) {
        }
    }
}
