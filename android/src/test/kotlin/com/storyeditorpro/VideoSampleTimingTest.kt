package com.storyeditorpro

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class VideoSampleTimingTest {
    private fun ints(vararg values: Int): ByteArray {
        val buffer=java.nio.ByteBuffer.allocate(values.size*4)
        values.forEach {buffer.putInt(it)};return buffer.array()
    }
    private fun box(tag: String,body: ByteArray)=ints(body.size+8)+tag.toByteArray(Charsets.US_ASCII)+body
    private fun fixture(rate: Int,movieScale: Int=1000,emptyLead: Boolean=false): java.io.File {
        val mdhd=box("mdhd",ints(0,0,0,1000,2000,0))
        val hdlr=box("hdlr",ints(0,0)+"vide".toByteArray()+ints(0,0,0))
        val stbl=box("stbl",box("stts",ints(0,1,1,2000))+box("stsz",ints(0,4,1)))
        val elst=box("elst",ints(0,if(emptyLead)2 else 1)+
            (if(emptyLead)ints(1,-1,0x10000)else byteArrayOf())+ints(2000,0,rate))
        val track=box("trak",box("edts",elst)+box("mdia",mdhd+hdlr+box("minf",stbl)))
        val file=java.io.File.createTempFile("niero-timing-",".mp4")
        file.writeBytes(box("moov",box("mvhd",ints(0,0,0,movieScale,2000,0))+track))
        return file
    }
    @Test fun unitRateEditsAreAcceptedAndNonunitEditsFailClosed() {
        val valid=fixture(0x10000)
        try {assertEquals(listOf(2000L),VideoSampleTiming.read(valid).durations)}finally{valid.delete()}
        for(rate in listOf(0x20000,0x08000,0)) {
            val file=fixture(rate)
            try {assertThrows(IllegalArgumentException::class.java){VideoSampleTiming.read(file)}}finally{file.delete()}
        }
    }
    @Test fun fractionalMediaTickEditTranslationsFailClosed() {
        val file=fixture(0x10000,movieScale=3,emptyLead=true)
        try {assertThrows(IllegalArgumentException::class.java){VideoSampleTiming.read(file)}}finally{file.delete()}
    }
    @Test fun singleFrameHoldIsVideo() {
        assertEquals(2000000L, VideoSampleTiming(1000,listOf(2000)).coveredMicroseconds(listOf(0),2000000))
    }
    @Test fun inflatedTrackOrAudioTailCannotExtendSample() {
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(90000,listOf(3000)).coveredMicroseconds(listOf(0),27000000)
        }
    }
    @Test fun gapsAndOverlapsAreNotCountedTwice() {
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(1000,listOf(700,700)).coveredMicroseconds(listOf(0,3000000),4000000)
        }
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(1000,listOf(1500,1500)).coveredMicroseconds(listOf(0,0),3000000)
        }
    }
    @Test fun exactThresholdNeverRoundsShortVideoUp() {
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(1000000,listOf(1999999)).coveredMicroseconds(listOf(0),3000000)
        }
    }
    @Test fun normalThirtyFpsUsesExactTicks() {
        val timing=VideoSampleTiming(90000,List(60){3000L})
        val pts=List(60){it*1000000L/30}
        assertEquals(2000000L,timing.coveredMicroseconds(pts,2000000))
    }
    @Test fun signedPresentationRoundingRecoversTicksWithoutRoundingDuration() {
        val timing=VideoSampleTiming(90000,listOf(3000))
        assertEquals(java.math.BigInteger.valueOf(3000),timing.presentationTick(33333))
        assertEquals(java.math.BigInteger.valueOf(-3000),timing.presentationTick(-33333))
        assertEquals(java.math.BigInteger.ZERO,timing.presentationTick(0))
        assertEquals(java.math.BigInteger.ONE,VideoSampleTiming(1000000,listOf(1)).presentationTick(1))
    }
    @Test fun trimClipsActualPresentation() {
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(1000,listOf(3000)).coveredMicroseconds(listOf(-1500000),1500000)
        }
        assertEquals(2000000L,VideoSampleTiming(1000,listOf(3000)).coveredMicroseconds(listOf(-1000000),2000000))
    }
    @Test fun variableFrameDurationRetainsExactCoverage() {
        assertEquals(2000000L,VideoSampleTiming(1000,listOf(500,1500)).coveredMicroseconds(listOf(0,500000),2000000))
    }
    @Test fun unknownTimingCannotBorrowDuration() {
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(90000,listOf(3000,3000)).coveredMicroseconds(listOf(0),3000000)
        }
        assertThrows(IllegalArgumentException::class.java) {
            VideoSampleTiming(2000000,listOf(4000000)).coveredMicroseconds(listOf(0),2000000)
        }
    }
}
