package com.storyeditorpro.ar

import androidx.camera.core.CameraEffect
import org.junit.Assert.assertEquals
import org.junit.Test

class FaceArPipelineConfigTest {
    @Test
    fun overlayTargetsPreviewVideoAndImageCapture() {
        assertEquals(
            CameraEffect.PREVIEW or CameraEffect.VIDEO_CAPTURE or CameraEffect.IMAGE_CAPTURE,
            FaceArController.EFFECT_TARGETS,
        )
    }
}
