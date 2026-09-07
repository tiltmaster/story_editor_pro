package com.storyeditorpro.ar

import org.junit.Assert.*
import org.junit.Test

class CameraEffectsStackTest {
    @Test fun placeNeedsExplicitNameAndNeverInfersLocationFromLocale() {
        assertFalse(CreativeLensContext(countryCode="KW", placeStyle="postcard").hasOverlay)
        assertTrue(CreativeLensContext(placeStyle="postcard", placeName="Kyoto").hasOverlay)
        assertFalse(CreativeLensContext(placeStyle="none", placeName="Kyoto").hasOverlay)
        assertTrue(CreativeLensContext(compositionId="daytime").hasOverlay)
    }

    @Test fun allTrackedArtworkIsValidatedIndependentlyOfComposition() {
        for (id in listOf("face_celestial", "face_hearts", "face_freckles", "face_neon", "face_butterflies")) {
            assertTrue(id in FaceArContract.faceLensIds)
            assertEquals(id, FaceArSettings.validated(id, 0.7).lensId)
            val context = CreativeLensContext(compositionId="retrodate", placeStyle="editorial", placeName="Paris")
            assertTrue(context.hasOverlay)
        }
    }

    @Test fun uprightArtworkRoundTripsEverySensorRotation() {
        for (rotation in listOf(0, 90, 180, 270)) {
            for (point in listOf(Point3f(.1f,.2f,0f), Point3f(.8f,.65f,0f))) {
                val sensor = FaceCoordinateTransform.detectorToBuffer(point,rotation)
                val upright = FaceCoordinateTransform.bufferToDetector(sensor,rotation)
                assertEquals(point.x,upright.x,.00001f)
                assertEquals(point.y,upright.y,.00001f)
            }
        }
    }
}
