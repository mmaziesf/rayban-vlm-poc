package glance.core

enum class FrameFormat { YUV420, JPEG }
enum class FrameOrigin { STREAM_BUFFER, PHOTO_CAPTURE, TEST_ASSET }

/**
 * One camera frame held on the phone.
 * For YUV420 the first width*height bytes are assumed to be the Y (luma) plane.
 * VERIFY: DAT documents VideoFrame.buffer as "decoded YUV" but not the exact layout (I420 vs NV12/NV21).
 */
class Frame(
    val bytes: ByteArray,
    val width: Int,
    val height: Int,
    val format: FrameFormat,
    val captureTimeMs: Long,
    val origin: FrameOrigin,
    val sharpness: Double = Double.NaN,
) {
    fun ageMs(nowMs: Long) = nowMs - captureTimeMs
    override fun toString() = "Frame(${width}x$height $format $origin t=$captureTimeMs sharp=${"%.1f".format(sharpness)})"
}

/** Variance of a 4-neighbour Laplacian on a subsampled luma plane. Higher = sharper. Cheap (~1/64 of pixels at step 8). */
object Sharpness {
    fun lumaLaplacianVariance(luma: ByteArray, width: Int, height: Int, step: Int = 8): Double {
        require(luma.size >= width * height) { "luma too small" }
        var n = 0; var sum = 0.0; var sumSq = 0.0
        var y = step
        while (y < height - step) {
            var x = step
            val row = y * width
            while (x < width - step) {
                val c = luma[row + x].toInt() and 0xFF
                val l = (luma[row + x - step].toInt() and 0xFF) + (luma[row + x + step].toInt() and 0xFF) +
                        (luma[row - step * width + x].toInt() and 0xFF) + (luma[row + step * width + x].toInt() and 0xFF) - 4 * c
                sum += l; sumSq += l.toDouble() * l; n++
                x += step
            }
            y += step
        }
        if (n == 0) return 0.0
        val mean = sum / n
        return sumSq / n - mean * mean
    }
}

/**
 * Fixed-capacity rolling buffer of the most recent frames. Thread-safe.
 * At 2 fps, capacity 6 = ~3 s of history.
 * Memory per frame (YUV420): 504x896 ≈ 0.68 MB, 720x1280 ≈ 1.38 MB.
 */
class FrameRingBuffer(val capacity: Int) {
    init { require(capacity > 0) }
    private val slots = arrayOfNulls<Frame>(capacity)
    private var head = 0
    private var count = 0
    private var pinned: Frame? = null
    @Volatile var totalPushed: Long = 0; private set

    @Synchronized fun push(frame: Frame) {
        slots[head] = frame
        head = (head + 1) % capacity
        if (count < capacity) count++
        totalPushed++
    }

    /** Newest first. */
    @Synchronized fun snapshot(): List<Frame> =
        (0 until count).map { i -> slots[(head - 1 - i + capacity * 2) % capacity]!! }

    @Synchronized fun latest(): Frame? = if (count == 0) null else slots[(head - 1 + capacity) % capacity]

    @Synchronized fun bytesHeld(): Long = snapshot().sumOf { it.bytes.size.toLong() }

    /**
     * Pick the frame for a vision intent:
     * newest frames within [maxAgeMs]; among the newest [lookback] of those, the sharpest (if sharpness known).
     */
    fun select(nowMs: Long, maxAgeMs: Long, lookback: Int = 3): Frame? {
        val fresh = snapshot().filter { it.ageMs(nowMs) <= maxAgeMs }.take(lookback)
        if (fresh.isEmpty()) return null
        val scored = fresh.filter { !it.sharpness.isNaN() }
        return if (scored.size == fresh.size) scored.maxByOrNull { it.sharpness } else fresh.first()
    }

    /** Freeze the frame the wearer was looking at when they started speaking (partial transcript). */
    @Synchronized fun pinLatest(): Frame? { pinned = latest(); return pinned }
    @Synchronized fun takePinned(): Frame? { val p = pinned; pinned = null; return p }

    @Synchronized fun clear() { java.util.Arrays.fill(slots, null); head = 0; count = 0; pinned = null }
}
