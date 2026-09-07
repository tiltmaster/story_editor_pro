package com.storyeditorpro

/** Scales media around the canvas center, then translates in canvas units. */
internal object MediaTransform {
    fun vertices(scale: Double, offsetX: Double, offsetY: Double): FloatArray {
        require(scale.isFinite() && offsetX.isFinite() && offsetY.isFinite())
        val s = scale.coerceIn(.5, 5.0).toFloat()
        val x = (offsetX * 2.0).toFloat()
        val y = (offsetY * -2.0).toFloat()
        require(x.isFinite() && y.isFinite())
        return floatArrayOf(-s + x, -s + y, s + x, -s + y, -s + x, s + y, s + x, s + y)
    }
}
