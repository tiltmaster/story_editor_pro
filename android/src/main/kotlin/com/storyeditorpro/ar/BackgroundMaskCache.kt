package com.storyeditorpro.ar

import java.util.concurrent.atomic.AtomicReference

/** Keep the last completed matte visible between inferences, even under load.
 * Freshness gates new captures; it must not toggle the selected scene off.
 * An epoch changes on camera rebind, disable, or scene selection.
 */
internal class BackgroundMaskCache<T> {
    private data class Entry<T>(val value: T, val capturedMs: Long, val style: Int, val epoch: Int)
    private val latest = AtomicReference<Entry<T>?>(null)

    fun update(value: T, capturedMs: Long, style: Int, epoch: Int) {
        latest.set(Entry(value, capturedMs, style, epoch))
    }

    fun current(style: Int, epoch: Int): T? = latest.get()
        ?.takeIf { it.style == style && it.epoch == epoch }?.value

    fun isReady(style: Int, epoch: Int, nowMs: Long): Boolean = latest.get()?.let {
        it.style == style && it.epoch == epoch && BackgroundMaskPolicy.isFresh(it.capturedMs, nowMs)
    } ?: false

    fun clear() { latest.set(null) }
}
