package com.storyeditorpro.ar

import org.junit.Assert.assertEquals
import org.junit.Test

class FaceCoordinateTransformTest {
    private val point = Point3f(0.2f, 0.7f, -0.1f)

    @Test
    fun invertsDetectorRotationIntoBufferCoordinates() {
        assertPoint(0.2f, 0.7f, FaceCoordinateTransform.detectorToBuffer(point, 0))
        assertPoint(0.7f, 0.8f, FaceCoordinateTransform.detectorToBuffer(point, 90))
        assertPoint(0.8f, 0.3f, FaceCoordinateTransform.detectorToBuffer(point, 180))
        assertPoint(0.3f, 0.2f, FaceCoordinateTransform.detectorToBuffer(point, 270))
    }

    @Test
    fun normalizesEquivalentPositiveAndNegativeRotations() {
        assertEquals(
            FaceCoordinateTransform.detectorToBuffer(point, 90),
            FaceCoordinateTransform.detectorToBuffer(point, 450),
        )
        assertEquals(
            FaceCoordinateTransform.detectorToBuffer(point, 270),
            FaceCoordinateTransform.detectorToBuffer(point, -90),
        )
    }

    private fun assertPoint(x: Float, y: Float, actual: Point3f) {
        assertEquals(x, actual.x, 0.0001f)
        assertEquals(y, actual.y, 0.0001f)
        assertEquals(point.z, actual.z, 0.0001f)
    }
}
