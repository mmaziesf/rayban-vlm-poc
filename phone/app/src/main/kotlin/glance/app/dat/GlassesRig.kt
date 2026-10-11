package glance.app.dat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.meta.wearable.dat.camera.Camera
import com.meta.wearable.dat.camera.addCamera
import com.meta.wearable.dat.camera.types.PhotoData
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.StreamState
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.display.addDisplay
import com.meta.wearable.dat.display.types.DisplayConfiguration
import com.meta.wearable.dat.display.types.DisplayState
import com.meta.wearable.dat.speech.addSpeech
import glance.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import java.io.ByteArrayOutputStream

/**
 * One DeviceSession with three capabilities: Display (HUD), Camera stream (rolling buffer), Speech (glasses ASR).
 * Signatures checked against mwdat-*-1.0.1 AARs (javap), 2026-10-10.
 * VERIFY at runtime: Display + Speech + Camera concurrently in one session (not documented).
 */
class GlassesRig(
    private val context: Context,
    private val scope: CoroutineScope,
    private val buffer: FrameRingBuffer,
    private val clock: Clock = SystemClock,
    val streamFps: Int = 2,                                  // DAT accepts 2, 7, 15, 24, 30 — not 4
    private val quality: VideoQuality = VideoQuality.MEDIUM, // 504x896; HIGH = 720x1280
) {
    lateinit var controller: GlanceController
    var streamLive = false; private set
    private var camera: Camera? = null
    private val work = Dispatchers.Default.limitedParallelism(1) // one turn at a time

    /** [selector]: SpecificDeviceSelector for a known (e.g. mock) device, or AutoDeviceSelector(filter = { it.isDisplayCapable() }). */
    suspend fun start(selector: DeviceSelector, onDescribe: () -> Unit, onLog: () -> Unit): DatHudRenderer {
        // Wearables.initialize(context) is called once in MainActivity.onCreate.
        val session = Wearables.createSession(selector).getOrThrow()
        session.start()
        session.state.first { it == DeviceSessionState.STARTED }

        val display = session.addDisplay(DisplayConfiguration()).getOrThrow()
        display.state.first { it == DisplayState.STARTED }

        // --- Camera stream → rolling buffer (preferred frame source for vision intents)
        val cam = session.addCamera(StreamConfiguration(videoQuality = quality, frameRate = streamFps)).getOrThrow()
        camera = cam
        scope.launch(Dispatchers.Default) {
            cam.stream.videoStream.collect { f ->
                if (f.isCompressed) return@collect                       // we asked for decoded YUV (compressVideo=false)
                val src = f.buffer.duplicate()
                val bytes = ByteArray(src.remaining()); src.get(bytes)   // copy: SDK may reuse buffers
                val sharp = if (bytes.size >= f.width * f.height) Sharpness.lumaLaplacianVariance(bytes, f.width, f.height) else Double.NaN
                buffer.push(Frame(bytes, f.width, f.height, FrameFormat.YUV420, clock.nowMs(), FrameOrigin.STREAM_BUFFER, sharp))
            }
        }
        scope.launch { cam.stream.state.collect { s -> streamLive = s == StreamState.STREAMING; if (::controller.isInitialized) controller.streamLive = streamLive } }
        scope.launch { cam.stream.errorStream.collect { e -> android.util.Log.w("Glance", "stream: ${e.description}") } } // THERMAL_HOT, BATTERY_LOW, PEAK_POWER_LIMIT…
        cam.stream.start()

        // --- Speech (glasses on-device ASR) → controller
        val speech = session.addSpeech().getOrThrow()
        scope.launch {
            speech.transcriptions.collect { r ->
                if (r != null && ::controller.isInitialized) launch(work) { controller.onTranscription(r.text, r.isFinal, r.confidence) }
            }
        }
        speech.start()

        return DatHudRenderer(display, onDescribe, onLog)
    }

    /** Fallback when the buffer is stale: still photo while the stream runs (slow: transfer over the glasses link). */
    fun captureFallback(): OnDemandCapture = OnDemandCapture {
        val cam = camera ?: return@OnDemandCapture null
        val t = clock.nowMs()
        val data = runBlocking { cam.stream.capturePhoto() }.getOrNull() ?: return@OnDemandCapture null
        val bmp: Bitmap? = when (data) {
            is PhotoData.Bitmap -> data.bitmap
            is PhotoData.HEIC -> { val b = data.data.duplicate(); val arr = ByteArray(b.remaining()); b.get(arr); BitmapFactory.decodeByteArray(arr, 0, arr.size) }
        }
        bmp ?: return@OnDemandCapture null
        val out = ByteArrayOutputStream(); bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
        Frame(out.toByteArray(), bmp.width, bmp.height, FrameFormat.JPEG, t, FrameOrigin.PHOTO_CAPTURE)
    }
}
