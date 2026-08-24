package com.storyeditorpro.ar

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class FaceArSettingsTest {
    @Test
    fun clampsIntensity() {
        assertEquals(0f, FaceArSettings.validated("none", -2).intensity)
        assertEquals(1f, FaceArSettings.validated("glasses_classic", 4).intensity)
    }

    @Test
    fun rejectsUnknownLensAndNonFiniteIntensity() {
        try {
            FaceArSettings.validated("unknown", 1)
            fail("unknown lens should fail")
        } catch (_: IllegalArgumentException) {
        }
        try {
            FaceArSettings.validated("glasses_classic", Float.NaN)
            fail("NaN intensity should fail")
        } catch (_: IllegalArgumentException) {
        }
        for (invalid in listOf(Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY)) {
            try {
                FaceArSettings.validated("glasses_classic", invalid)
                fail("infinite intensity should fail")
            } catch (_: IllegalArgumentException) {
            }
        }
    }

    @Test
    fun acceptsEveryContractLensAtBounds() {
        assertEquals(
            setOf("glasses_classic", "glasses_aviator_gold", "glasses_visor_cyan"),
            FaceArContract.glassesLensIds,
        )
        for (lens in FaceArContract.lensIds) {
            assertEquals(0f, FaceArSettings.validated(lens, 0).intensity)
            assertEquals(1f, FaceArSettings.validated(lens, 1).intensity)
        }
    }
}
