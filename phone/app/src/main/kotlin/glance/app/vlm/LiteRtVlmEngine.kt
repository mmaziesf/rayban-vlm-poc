package glance.app.vlm

import android.util.Log
import com.google.ai.edge.litertlm.*
import glance.app.dat.YuvJpeg
import glance.core.*

/**
 * Gemma 4 E4B via LiteRT-LM (Kotlin API per https://ai.google.dev/edge/litert-lm/android).
 *  - visionBackend MUST be GPU on Android (CPU vision crashes on the 2nd image turn:
 *    https://github.com/google-ai-edge/LiteRT-LM/issues/2056).
 *  - Engine init (~5-10 s, mmaps the 3.66 GB file) happens in the constructor → construct OFF the main thread
 *    (GlanceGraph.start runs on Dispatchers.Default). Construction failure is caught by VlmFactory → stub fallback.
 *  - One short-lived Conversation per turn (no chat memory until M5). Calls are serialized: one GPU engine,
 *    and GlanceController already rejects overlapping turns ("busy").
 *  - Fully offline: reads a local file only. LiteRT-LM itself does no network I/O here; release builds have no
 *    INTERNET permission (offline proof for M1c = `aapt dump permissions` on the release APK).
 * Logs (bot parses with tools/m1c/parse_timings.sh):
 *   GlanceVlm: load_ms=… path=…        once
 *   GlanceVlm: infer_ms=… jpeg_ms=… img=WxH prompt_chars=… out_chars=…   per turn
 * VERIFY on device: visual-token budget knob (70…1120) is not exposed in the Kotlin guide; per-stage
 * prefill/decode timings are not exposed either → we log wall time and the encode step separately.
 */
class LiteRtVlmEngine(private val modelPath: String, cacheDir: String) : VlmEngine, AutoCloseable {
    private val engine: Engine
    val loadMs: Long

    init {
        val t0 = System.currentTimeMillis()
        engine = Engine(
            EngineConfig(modelPath = modelPath, backend = Backend.GPU(), visionBackend = Backend.GPU(), cacheDir = cacheDir)
        ).also { it.initialize() }
        loadMs = System.currentTimeMillis() - t0
        Log.i(TAG, "load_ms=$loadMs path=$modelPath")
    }

    @Synchronized
    override fun infer(frame: Frame?, prompt: String): VlmResult {
        val t0 = System.currentTimeMillis()
        val jpeg = frame?.let {
            when (it.format) {
                FrameFormat.JPEG -> it.bytes
                FrameFormat.YUV420 -> YuvJpeg.i420ToJpeg(it.bytes, it.width, it.height)
            }
        }
        val tEnc = System.currentTimeMillis()
        engine.createConversation().use { conv ->
            val msg = if (jpeg == null) conv.sendMessage(prompt)
                      else conv.sendMessage(Contents.of(Content.ImageBytes(jpeg), Content.Text(prompt)))
            val out = msg.toString().trim()
            val t1 = System.currentTimeMillis()
            Log.i(TAG, "infer_ms=${t1 - t0} jpeg_ms=${tEnc - t0} img=${frame?.let { "${it.width}x${it.height}" } ?: "none"} " +
                "prompt_chars=${prompt.length} out_chars=${out.length}")
            return VlmResult(out, decodeMs = t1 - tEnc)
        }
    }

    override fun close() = engine.close()

    companion object { const val TAG = "GlanceVlm" }
}

/** Instant offline stand-in: emulator, CI and instrumented tests (deterministic, keeps MockLoopTest green). */
class CannedVlmEngine : VlmEngine {
    override fun infer(frame: Frame?, prompt: String): VlmResult = VlmResult(
        when {
            prompt == Prompts.MEAL -> """{"is_food":true,"name":"Test plate","kcal":500,"protein_g":30}"""
            frame == null -> "I can only answer that with the camera for now."
            else -> "Mock answer for a ${frame.width}x${frame.height} frame from ${frame.origin}."
        }
    )
}
