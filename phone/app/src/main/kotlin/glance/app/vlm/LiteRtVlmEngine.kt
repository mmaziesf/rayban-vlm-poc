package glance.app.vlm

import com.google.ai.edge.litertlm.*
import glance.app.dat.YuvJpeg
import glance.core.*

/**
 * Gemma 4 E4B via LiteRT-LM (Kotlin API per https://ai.google.dev/edge/litert-lm/android).
 * visionBackend MUST be GPU on Android (CPU vision crashes on 2nd image turn:
 * https://github.com/google-ai-edge/LiteRT-LM/issues/2056).
 * One short-lived Conversation per turn for M2 (no chat memory yet → M5).
 * VERIFY: Kotlin knob for visual token budget (70/140/280/560/1120) — not found in the Android guide.
 */
class LiteRtVlmEngine(modelPath: String, cacheDir: String) : VlmEngine, AutoCloseable {
    private val engine = Engine(
        EngineConfig(modelPath = modelPath, backend = Backend.GPU(), visionBackend = Backend.GPU(), cacheDir = cacheDir)
    ).also { it.initialize() } // up to ~10 s: construct off the main thread

    override fun infer(frame: Frame?, prompt: String): VlmResult {
        val t0 = System.currentTimeMillis()
        engine.createConversation().use { conv ->
            val msg = if (frame == null) conv.sendMessage(prompt) else {
                val jpeg = when (frame.format) {
                    FrameFormat.JPEG -> frame.bytes
                    FrameFormat.YUV420 -> YuvJpeg.i420ToJpeg(frame.bytes, frame.width, frame.height)
                }
                conv.sendMessage(Contents.of(Content.ImageBytes(jpeg), Content.Text(prompt)))
            }
            return VlmResult(msg.toString().trim(), decodeMs = System.currentTimeMillis() - t0)
        }
    }

    override fun close() = engine.close()
}

/** Instant offline stand-in so the HUD/voice loop can be tested before the 3.65 GB model is on the phone. */
class CannedVlmEngine : VlmEngine {
    override fun infer(frame: Frame?, prompt: String): VlmResult = VlmResult(
        when {
            prompt == Prompts.MEAL -> """{"is_food":true,"name":"Test plate","kcal":500,"protein_g":30}"""
            frame == null -> "I can only answer that with the camera for now."
            else -> "Mock answer for a ${frame.width}x${frame.height} frame from ${frame.origin}."
        }
    )
}
