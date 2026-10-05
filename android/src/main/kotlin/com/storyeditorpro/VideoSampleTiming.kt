package com.storyeditorpro

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.math.BigInteger

/** MP4 sample durations, paired with MediaExtractor's actual presentation PTS.
 * Track/movie duration may clip samples; it can NEVER extend them. */
data class VideoSampleTiming(val timescale: Long, val durations: List<Long>) {
    fun presentationTick(ptsUs: Long): BigInteger {
        require(timescale in 1..1000000L)
        val million=BigInteger.valueOf(1000000L)
        val ticks=BigInteger.valueOf(ptsUs).multiply(BigInteger.valueOf(timescale))
        val adjustment=million-BigInteger.ONE
        return if(ticks.signum()>=0) (ticks+adjustment).divide(million)
            else (ticks-adjustment).divide(million)
    }
    fun coveredMicroseconds(pts: List<Long>, clipEndUs: Long): Long {
        require(pts.size == durations.size && clipEndUs > 0)
        val scale = BigInteger.valueOf(timescale)
        val million = BigInteger.valueOf(1000000L)
        val zero = BigInteger.ZERO
        val clipEnd = BigInteger.valueOf(clipEndUs).multiply(scale)
        val intervals = pts.indices.mapNotNull { i ->
            // Recover exact media ticks from truncated microsecond PTS only
            // where each tick is at least 1us. Duration is never rounded up.
            val raw = presentationTick(pts[i]).multiply(million)
            val start = raw.max(zero)
            val end = raw.add(BigInteger.valueOf(durations[i]).multiply(million)).min(clipEnd)
            if (end > start) start to end else null
        }.sortedBy { it.first }
        var covered = zero
        var start = zero
        var end = zero
        for ((a,b) in intervals) {
            if (a > end) { covered += end-start; start=a; end=b }
            else end=end.max(b)
        }
        covered += end-start
        require(covered >= scale.multiply(million).multiply(BigInteger.valueOf(2L))) {
            "video_too_short"
        }
        return covered.divide(scale).longValueExact()
    }
    companion object {
        private data class Box(val type: String, val bytes: ByteArray)
        private fun u32(bytes: ByteArray, offset: Int): Long =
            ByteBuffer.wrap(bytes,offset,4).order(ByteOrder.BIG_ENDIAN).int.toLong() and 0xffffffffL
        private fun boxes(bytes: ByteArray): List<Box> {
            val result=mutableListOf<Box>(); var offset=0
            while(offset<bytes.size) {
                require(offset+8<=bytes.size)
                val size=u32(bytes,offset); require(size>=8 && size<=bytes.size-offset)
                result.add(Box(String(bytes,offset+4,4,Charsets.US_ASCII),bytes.copyOfRange(offset+8,offset+size.toInt())))
                offset+=size.toInt()
            }
            return result
        }
        private fun one(bytes: ByteArray,type: String): ByteArray = boxes(bytes).filter { it.type==type }.single().bytes
        fun read(file: File): VideoSampleTiming {
            val moov=RandomAccessFile(file,"r").use { input ->
                var found: ByteArray?=null
                while(input.filePointer+8<=input.length()) {
                    val offset=input.filePointer
                    val size=input.readInt().toLong() and 0xffffffffL
                    val type=ByteArray(4);input.readFully(type)
                    require(size>=8 && size<=input.length()-offset)
                    if(String(type,Charsets.US_ASCII)=="moov") {
                        require(size<=8*1024*1024)
                        found=ByteArray((size-8).toInt());input.readFully(found);break
                    }
                    input.seek(offset+size)
                }
                found ?: error("video_timing_unreadable")
            }
            val tracks=boxes(moov).filter { it.type=="trak" }.map { one(it.bytes,"mdia") }.filter {
                val h=one(it,"hdlr");h.size>=12 && String(h,8,4,Charsets.US_ASCII)=="vide"
            }
            require(tracks.size==1)
            val mdhd=one(tracks.single(),"mdhd")
            val version=mdhd[0].toInt();require(version==0 || version==1)
            val scale=u32(mdhd,if(version==1)20 else 12);require(scale>0)
            // Unit-rate edits retain sample durations. Nonunit playback and
            // fractional media-tick translations cannot use this proof.
            val videoTrack=boxes(moov).filter { it.type=="trak" }.single {
                val h=one(one(it.bytes,"mdia"),"hdlr");String(h,8,4,Charsets.US_ASCII)=="vide"
            }.bytes
            val edits=boxes(videoTrack).filter { it.type=="edts" }
            if(edits.isNotEmpty()) {
                require(edits.size==1)
                val elst=one(edits.single().bytes,"elst")
                val ev=elst[0].toInt();require(ev==0 || ev==1)
                val entries=u32(elst,4);val width=if(ev==1)20 else 12
                require(entries in 1..1024 && elst.size.toLong()==8+entries*width)
                val mvhd=one(moov,"mvhd");val mv=mvhd[0].toInt();require(mv==0 || mv==1)
                val movieScale=u32(mvhd,if(mv==1)20 else 12);require(movieScale>0)
                var editStart=BigInteger.ZERO
                for(i in 0 until entries.toInt()) {
                    val off=8+i*width
                    val segment=if(ev==1) ByteBuffer.wrap(elst,off,8).long else u32(elst,off)
                    val mediaTime=if(ev==1) ByteBuffer.wrap(elst,off+8,8).long else ByteBuffer.wrap(elst,off+4,4).int.toLong()
                    val rate=ByteBuffer.wrap(elst,off+width-4,4).int
                    require(segment>=0 && mediaTime>=-1 && rate==0x00010000) { "video_edit_unsupported" }
                    require(editStart.multiply(BigInteger.valueOf(scale)).mod(BigInteger.valueOf(movieScale))==BigInteger.ZERO) {
                        "video_edit_translation_unsupported"
                    }
                    editStart+=BigInteger.valueOf(segment)
                }
            }
            val stbl=one(one(tracks.single(),"minf"),"stbl")
            val stts=one(stbl,"stts");require(stts[0].toInt()==0)
            val count=u32(stts,4);require(count>0 && count<=216000 && stts.size.toLong()==8+count*8)
            val durations=ArrayList<Long>()
            for(i in 0 until count.toInt()) {
                val n=u32(stts,8+i*8);val delta=u32(stts,12+i*8)
                require(n>0 && delta>0 && n<=216000-durations.size)
                repeat(n.toInt()){durations.add(delta)}
            }
            val sizes=one(stbl,"stsz");require(u32(sizes,8)==durations.size.toLong())
            return VideoSampleTiming(scale,durations)
        }
    }
}
