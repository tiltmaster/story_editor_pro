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
                    text(canvas,date("EEEE",now,locale),width/2,height*0.65f,76*u,cream,serif=true,align=Paint.Align.CENTER,maxWidth=width*0.85f)
                    text(canvas,date("h:mm a",now,locale),width/2,height*0.65f+52*u,32*u,cream,align=Paint.Align.CENTER)
                    rule(canvas,width/2-150*u,height*0.65f+72*u,width/2+150*u,Color.rgb(245,201,129),3*u)
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
                    // A device locale is never represented as the user's location.
                    val title = lensContext.placeName.ifBlank { if (lensContext.languageCode == "ar") "الساعة الذهبية" else "GOLDEN HOUR" }
                    round(canvas,width*0.14f,42*u,width*0.72f,82*u,34*u,Color.argb(178,42,29,20))
                    text(canvas,title,width/2,95*u,30*u,cream,align=Paint.Align.CENTER,maxWidth=width*0.64f)
                    text(canvas,date("EEEE  •  d MMMM",now,locale),width/2,height-74*u,27*u,cream,serif=true,align=Paint.Align.CENTER,maxWidth=width*0.9f)
                }
                "retrodate" -> {
                    paint.color=Color.argb(82,7,8,12)
                    canvas.drawRect(0f,0f,width,56*u,paint); canvas.drawRect(0f,height-56*u,width,height,paint)
                    text(canvas,if(arabicLocale) "٣٥ مم  •  إطار ٢٤" else "35 MM  •  FRAME 24",30*u,38*u,18*u,cream,mono=true)
                    text(canvas,date("MMM dd  yyyy",now,locale),width-30*u,height-20*u,19*u,cream,mono=true,align=Paint.Align.RIGHT)
                }
            }
            if (lensContext.placeStyle != "none" && lensContext.placeName.isNotBlank()) {
                drawPlace(canvas,width,height,u,lensContext,now,locale)
            }
        } finally { canvas.restoreToCount(save) }
    }

    private fun drawPlace(c: Canvas,w: Float,h: Float,u: Float,value: CreativeLensContext,now: Date,locale: Locale) {
        val name=value.placeName
        val cream=Color.rgb(255,245,225)
        val gold=Color.rgb(230,193,134)
        val arabic=value.languageCode=="ar"
        // Deliberately above camera controls; all typography scales with crop.
        val baseline=h*0.73f
        when(value.placeStyle) {
            "postcard" -> {
                val left=w*0.07f; val right=w*0.93f
                val top=baseline-180*u; val bottom=baseline+64*u
                val ink=Color.rgb(27,37,52); val red=Color.rgb(219,45,57)
                round(c,left,top,right-left,bottom-top,10*u,Color.rgb(250,249,245))
                // Airmail edge belongs to the card, never to a cropped gradient.
                val edge=(right-left)/24
                for (i in 0..23) {
                    paint.color=if(i%2==0) red else Color.rgb(38,66,103)
                    c.drawRect(left+i*edge,top,left+(i+1)*edge,top+7*u,paint)
                }
                val leading=if(arabic) right-28*u else left+28*u
                val align=if(arabic) Paint.Align.RIGHT else Paint.Align.LEFT
                text(c,if(arabic) "بطاقة بريدية · تحية من" else "POSTCARD / GREETINGS FROM",leading,top+44*u,19*u,red,mono=true,align=align,maxWidth=(right-left)*.72f)
                text(c,name,leading,top+124*u,64*u,ink,serif=true,align=align,maxWidth=(right-left)*.72f)
                text(c,date("dd MMM yyyy",now,locale),leading,bottom-28*u,20*u,ink,mono=true,align=align)
                val stampX=if(arabic) left+70*u else right-70*u
                paint.color=red;paint.style=Paint.Style.STROKE;paint.strokeWidth=3*u
                c.drawCircle(stampX,top+116*u,43*u,paint)
                c.drawCircle(stampX,top+116*u,35*u,paint)
                c.drawLine(stampX-45*u,top+166*u,stampX+45*u,top+166*u,paint)
                paint.style=Paint.Style.FILL
                text(c,date("dd",now,locale),stampX,top+125*u,25*u,red,mono=true,align=Paint.Align.CENTER)
            }
            "editorial" -> {
                val left=w*0.07f; val right=w*0.93f
                val leading=if(arabic) right-32*u else left+32*u
                val align=if(arabic) Paint.Align.RIGHT else Paint.Align.LEFT
                val top=baseline-166*u
                round(c,left,top,right-left,226*u,10*u,Color.argb(224,16,18,22))
                paint.color=Color.rgb(237,52,68)
                c.drawRect(if(arabic) right-7*u else left,top,if(arabic) right else left+7*u,top+226*u,paint)
                text(c,if(arabic) "من قلب المكان" else "ON LOCATION",leading,top+43*u,20*u,Color.rgb(245,78,88),mono=true,align=align,maxWidth=w*.75f)
                text(c,name,leading,top+126*u,68*u,Color.WHITE,align=align,maxWidth=w*.77f)
                text(c,date("EEEE  /  HH:mm",now,locale),leading,top+190*u,21*u,Color.rgb(205,208,215),mono=true,align=align,maxWidth=w*.77f)
            }
            "stamp" -> {
                val save=c.save();c.rotate(-7f,w/2,baseline-20*u)
                round(c,w*0.18f,baseline-155*u,w*0.64f,244*u,12*u,Color.argb(225,247,234,207))
                paint.color=Color.rgb(66,88,78);paint.style=Paint.Style.STROKE;paint.strokeWidth=3*u
                c.drawRoundRect(w*0.18f+14*u,baseline-141*u,w*0.82f-14*u,baseline+75*u,7*u,7*u,paint);paint.style=Paint.Style.FILL
                val ink=Color.rgb(45,70,62)
                text(c,if(arabic) "ذكريات السفر" else "A MOMENT IN",w/2,baseline-97*u,20*u,ink,mono=true,align=Paint.Align.CENTER)
                text(c,name,w/2,baseline-20*u,61*u,ink,serif=true,align=Paint.Align.CENTER,maxWidth=w*0.53f)
                text(c,date("dd . MM . yyyy",now,locale),w/2,baseline+40*u,22*u,ink,mono=true,align=Paint.Align.CENTER)
                c.restoreToCount(save)
            }
        }
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
