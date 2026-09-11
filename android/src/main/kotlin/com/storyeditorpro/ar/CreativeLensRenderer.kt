package com.storyeditorpro.ar

import android.content.Context
import android.graphics.*
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import androidx.camera.effects.Frame
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.min
import kotlin.math.ceil

/** CameraX compositor for authored camera lenses, shared by all capture outputs. */
internal class CreativeLensRenderer(@Suppress("UNUSED_PARAMETER") context: Context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val formatted = LinkedHashMap<String, String>()
    private val textLayouts = LinkedHashMap<String, StaticLayout>()
    private var arabicLocale = false

    fun draw(frame: Frame, lensId: String, intensity: Float, lensContext: CreativeLensContext) {
        val sensorCrop = frame.cropRect
        if (sensorCrop.isEmpty) return
        val rotated = frame.rotationDegrees % 180 != 0
        val width = (if (rotated) sensorCrop.height() else sensorCrop.width()).toFloat()
        val height = (if (rotated) sensorCrop.width() else sensorCrop.height()).toFloat()
        val canvas = frame.overlayCanvas
        val save = canvas.save()
        try {
            canvas.clipRect(sensorCrop)
            // Artwork is authored upright. CameraX rotates the composed sensor
            // buffer later, so undo that rotation before drawing text.
            canvas.translate(sensorCrop.exactCenterX(), sensorCrop.exactCenterY())
            canvas.rotate(-frame.rotationDegrees.toFloat())
            canvas.translate(-width / 2, -height / 2)
            // CameraX outputs explicitly use MIRROR_MODE_OFF. Frame.isMirroring
            // describes the input transform, not another output mirror.
            if (lensContext.mirrorOutput) {
                canvas.scale(-1f, 1f, width / 2, height / 2)
            }
            val u = min(width / 1080f, height / 1920f)
            val locale = Locale(lensContext.languageCode, lensContext.countryCode)
            arabicLocale = locale.language == "ar"
            val now = Date()
            val strength = intensity.coerceIn(0f, 1f)
            val cream = Color.argb((245 * strength).toInt(), 255, 243, 218)
            val selected = if (lensContext.compositionId != "none") lensContext.compositionId else lensId
            when (selected) {
                "vhs1993" -> {
                    round(canvas, 34*u, 36*u, 146*u, 52*u, 18*u, Color.argb(205, 12, 13, 16))
                    paint.color = Color.rgb(255,62,76); canvas.drawCircle(56*u,62*u,7*u,paint)
                    text(canvas,if(arabicLocale) "تسجيل" else "REC",76*u,70*u,25*u,cream,mono=true,maxWidth=94*u)
                    text(canvas,if(arabicLocale) "كاميرا ٠١" else "CAM 01",width-34*u,69*u,23*u,cream,mono=true,align=Paint.Align.RIGHT)
                    text(canvas,date("HH:mm",now,locale),34*u,height-76*u,30*u,cream,mono=true)
                    text(canvas,date("dd  MM  yyyy",now,locale),width-34*u,height-76*u,23*u,cream,mono=true,align=Paint.Align.RIGHT)
                }
                "daytime" -> {
                    // Botanical light at the edges; the face remains unobstructed.
                    for (side in 0..1) {
                        val saved = canvas.save()
                        canvas.translate(if (side == 0) 0f else width, height * .85f)
                        if (side == 1) canvas.scale(-1f, 1f)
                        paint.color = Color.argb((120 * strength).toInt(), 255, 220, 165)
                        paint.strokeWidth = 2*u; paint.style = Paint.Style.STROKE
                        val stem = Path().apply { moveTo(18*u, 0f); cubicTo(95*u,-100*u,55*u,-265*u,145*u,-380*u) }
                        canvas.drawPath(stem,paint)
                        paint.style = Paint.Style.FILL
                        for (i in 0..5) {
                            val y = -45*u-i*51*u; val x = 30*u+i*15*u
                            val leaf = Path().apply { moveTo(x,y); quadTo(x+70*u,y-8*u,x+63*u,y-49*u); quadTo(x+13*u,y-40*u,x,y) }
                            canvas.drawPath(leaf,paint)
                        }
                        canvas.restoreToCount(saved)
                    }
                }
                "timefocus" -> {
                    paint.color=cream; paint.strokeWidth=3*u
                    val inset=40*u; val arm=76*u
                    for (x in floatArrayOf(inset,width-inset)) for (y in floatArrayOf(inset,height-inset)) {
                        canvas.drawLine(x,y,x+if(x<width/2) arm else -arm,y,paint)
                        canvas.drawLine(x,y,x,y+if(y<height/2) arm else -arm,paint)
                    }
                    text(canvas,"${if(arabicLocale) "بورتريه" else "PORTRAIT"}  /  \u2066${date("HH:mm",now,locale)}\u2069",width/2,height-68*u,20*u,cream,mono=true,align=Paint.Align.CENTER)
                }
                "kuwaitgold" -> {
                    // Fine sand-contour engraving; no invented time or place caption.
                    paint.style = Paint.Style.STROKE; paint.strokeWidth = 1.7f*u
                    for (i in 0..7) {
                        paint.color = Color.argb(((95-i*8)*strength).toInt(), 235, 197, 143)
                        val y = height - (24+i*15)*u
                        val contour = Path().apply { moveTo(0f,y); cubicTo(width*.3f,y-115*u,width*.55f,y+55*u,width,y-100*u) }
                        canvas.drawPath(contour,paint)
                    }
                    paint.style = Paint.Style.FILL
                }
                "retrodate" -> {
                    paint.color=Color.argb(82,7,8,12)
                    canvas.drawRect(0f,0f,width,56*u,paint); canvas.drawRect(0f,height-56*u,width,height,paint)
                    text(canvas,if(arabicLocale) "٣٥ مم  •  إطار ٢٤" else "35 MM  •  FRAME 24",30*u,38*u,18*u,cream,mono=true)
                    text(canvas,date("MMM dd  yyyy",now,locale),width-30*u,height-20*u,19*u,cream,mono=true,align=Paint.Align.RIGHT)
                }
            }
            if (lensContext.placeStyle != "none" && lensContext.placeName.isNotBlank()) {
                drawPlace(canvas,width,height,u,lensContext)
            }
        } finally { canvas.restoreToCount(save) }
    }

    private fun drawPlace(c: Canvas,w: Float,h: Float,u: Float,value: CreativeLensContext) {
        val artwork = value.placeArtwork ?: return
        val scale = u * value.placeScale
        val width = artwork.width * scale
        val height = artwork.height * scale
        val x = w * value.placeX; val y = h * value.placeY
        paint.reset(); paint.isAntiAlias = true; paint.isFilterBitmap = true
        val saved = c.save()
        try {
            c.rotate(value.placeRotation * (180f / Math.PI.toFloat()), x, y)
            c.drawBitmap(artwork, null, RectF(x-width/2, y-height/2, x+width/2, y+height/2), paint)
        } finally { c.restoreToCount(saved) }
    }

    private fun date(pattern: String,now: Date,locale: Locale): String {
        val key="$pattern|${locale.toLanguageTag()}|${now.time/60000}"
        return formatted[key] ?: SimpleDateFormat(pattern,locale).format(now).also {
            if(formatted.size>24) formatted.clear()
            formatted[key]=it
        }
    }
    private fun text(c: Canvas,value: String,x: Float,y: Float,size: Float,color: Int,mono: Boolean=false,serif: Boolean=false,align: Paint.Align=Paint.Align.LEFT,maxWidth: Float=Float.MAX_VALUE) {
        // StaticLayout shapes connected Arabic and resolves mixed-direction
        // runs. Cache layouts so camera frames do not rebuild text every time.
        val key="$value|$size|$color|$mono|$serif|$maxWidth|$arabicLocale"
        val layout=textLayouts[key] ?: run {
            val tp=TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color=color
                textSize=size
                // Use native Arabic glyphs without synthetic Latin italics.
                typeface=if(value.any { it in '\u0600'..'\u06ff' || it in '\u0750'..'\u08ff' })
                    Typeface.create("sans-serif",Typeface.BOLD)
                else if(mono) Typeface.MONOSPACE
                else if(serif) Typeface.create("serif",Typeface.BOLD_ITALIC)
                else Typeface.create("sans-serif-medium",Typeface.NORMAL)
            }
            val measured=Layout.getDesiredWidth(value,tp)
            if(measured>maxWidth) tp.textSize=size*maxWidth/measured
            val width=ceil(min(Layout.getDesiredWidth(value,tp),maxWidth).toDouble()).toInt().coerceAtLeast(1)
            StaticLayout.Builder.obtain(value,0,value.length,tp,width)
                .setTextDirection(if(arabicLocale) TextDirectionHeuristics.FIRSTSTRONG_RTL else TextDirectionHeuristics.FIRSTSTRONG_LTR)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setIncludePad(true)
                .setMaxLines(1)
                .setEllipsize(TextUtils.TruncateAt.END)
                .build().also {
                    if(textLayouts.size>=64) textLayouts.clear()
                    textLayouts[key]=it
                }
        }
        val left=when(align) { Paint.Align.CENTER -> x-layout.width/2f; Paint.Align.RIGHT -> x-layout.width; else -> x }
        val save=c.save()
        c.translate(left,y-layout.getLineBaseline(0))
        layout.draw(c)
        c.restoreToCount(save)
    }
    private fun round(c: Canvas,x: Float,y: Float,w: Float,h: Float,r: Float,color: Int) {
        paint.shader=null;paint.style=Paint.Style.FILL;paint.color=color
        c.drawRoundRect(x,y,x+w,y+h,r,r,paint)
    }
    private fun rule(c: Canvas,x: Float,y: Float,right: Float,color: Int,stroke: Float) {
        paint.shader=null;paint.color=color;paint.strokeWidth=stroke;c.drawLine(x,y,right,y,paint)
    }
}
