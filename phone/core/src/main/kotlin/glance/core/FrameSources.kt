package glance.core

/**
 * Preferred path: answer from the rolling stream buffer (instant).
 * Fallback: on-demand capture (DAT Photo or Stream.capturePhoto) when the buffer is empty/stale.
 * Pinned frame (set on the first partial transcript) wins if still fresh: it is what the wearer
 * was looking at when they started asking, not after they turned their head.
 */
class BufferedFrameSource(
    private val buffer: FrameRingBuffer,
    private val clock: Clock,
    private val fallback: OnDemandCapture?,
    private val maxAgeMs: Long = 1500,
) {
    fun acquire(): FrameResult {
        val now = clock.nowMs()
        buffer.takePinned()?.let { if (it.ageMs(now) <= maxAgeMs * 2) return FrameResult(it, "pinned") }
        buffer.select(now, maxAgeMs)?.let { return FrameResult(it, "buffer") }
        val f = fallback?.capture()
        return if (f != null) FrameResult(f, "capture-fallback") else FrameResult(null, "no-frame")
    }
}
