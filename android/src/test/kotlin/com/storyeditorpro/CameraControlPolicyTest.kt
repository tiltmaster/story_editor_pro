package com.storyeditorpro

import com.storyeditorpro.ar.OverlayGeometry
import org.junit.Assert.*
import org.junit.Test

class CameraControlPolicyTest {
    private val sensor = CameraSensorBounds(0f, 0f, 4000f, 3000f)
    private val sensorToBuffer = floatArrayOf(.25f, 0f, 0f, 0f, .25f, 0f, 0f, 0f, 1f)

    @Test fun zoomUsesActualHardwareRangeIncludingUltraWide() {
        assertEquals(.6f, CameraControlPolicy.zoom(.2, .6f, 12f), .0001f)
        assertEquals(12f, CameraControlPolicy.zoom(99.0, .6f, 12f), .0001f)
        assertEquals(2.5f, CameraControlPolicy.zoom(2.5, .6f, 12f), .0001f)
    }

    @Test fun exposureQuantizesEvToDeviceIndicesAndClamps() {
        assertEquals(2, CameraControlPolicy.exposureIndex(.72, 1.0 / 3.0, -6, 6))
        assertEquals(-2, CameraControlPolicy.exposureIndex(-.72, 1.0 / 3.0, -6, 6))
        assertEquals(6, CameraControlPolicy.exposureIndex(9.0, 1.0 / 3.0, -6, 6))
        assertEquals(-6, CameraControlPolicy.exposureIndex(-9.0, 1.0 / 3.0, -6, 6))
    }

    @Test fun portraitViewportFocusIncludesRotationAndCrop() {
        // 1000 x 750 sensor buffer with a 16:9 central crop, rotated clockwise.
        val frame = CameraMeteringFrame(OverlayGeometry(0f, 93.75f, 1000f, 562.5f, 90), sensorToBuffer)
        assertPoint(.5f, .5f, CameraControlPolicy.focusPoint(.5, .5, frame, sensor))
        assertPoint(0f, .875f, CameraControlPolicy.focusPoint(0.0, 0.0, frame, sensor))
        assertPoint(1f, .125f, CameraControlPolicy.focusPoint(1.0, 1.0, frame, sensor))
    }

    @Test fun frontStreamReflectionIsInvertedWithoutDoubleDisplayMirror() {
        val reflected = floatArrayOf(-.25f, 0f, 1000f, 0f, .25f, 0f, 0f, 0f, 1f)
        val frame = CameraMeteringFrame(OverlayGeometry(0f, 93.75f, 1000f, 562.5f, 270), reflected)
        assertPoint(0f, .125f, CameraControlPolicy.focusPoint(0.0, 0.0, frame, sensor))
        assertPoint(1f, .875f, CameraControlPolicy.focusPoint(1.0, 1.0, frame, sensor))
    }

    @Test fun sensorOriginAndViewportBoundsAreAccountedFor() {
        val offsetSensor = CameraSensorBounds(20f, 40f, 4000f, 3000f)
        val matrix = floatArrayOf(.25f, 0f, -5f, 0f, .25f, -10f, 0f, 0f, 1f)
        val frame = CameraMeteringFrame(OverlayGeometry(0f, 0f, 1000f, 750f, 0), matrix)
        assertPoint(0f, 1f, CameraControlPolicy.focusPoint(-2.0, 3.0, frame, offsetSensor))
    }

    @Test(expected = IllegalArgumentException::class)
    fun invalidFocusNeverReachesCamera() {
        val frame = CameraMeteringFrame(OverlayGeometry(0f, 0f, 1000f, 750f, 0), sensorToBuffer)
        CameraControlPolicy.focusPoint(Double.NaN, .5, frame, sensor)
    }

    @Test(expected = IllegalArgumentException::class)
    fun singularSensorTransformIsRejected() {
        val frame = CameraMeteringFrame(OverlayGeometry(0f, 0f, 1000f, 750f, 0), FloatArray(9))
        CameraControlPolicy.focusPoint(.5, .5, frame, sensor)
    }

    private fun assertPoint(x: Float, y: Float, actual: Pair<Float, Float>) {
        assertEquals(x, actual.first, .0001f)
        assertEquals(y, actual.second, .0001f)
    }
}
