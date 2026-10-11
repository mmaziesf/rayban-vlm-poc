package glance.core

/**
 * Orchestrates one turn: transcript → intent → frame → VLM → HUD + speech (+ meal log).
 * Synchronous on purpose: the Android layer runs it on a single background dispatcher, and
 * JVM tests run it directly with fakes.
 */
class GlanceController(
    private val router: IntentRouter,
    private val buffer: FrameRingBuffer,
    private val frames: BufferedFrameSource,
    private val vlm: VlmEngine,
    private val hud: HudRenderer,
    private val speaker: Speaker,
    private val mealLog: MealLog,
    private val clock: Clock,
    var streamFps: Int = 2,
    var streamLive: Boolean = false,
) {
    @Volatile var busy = false; private set

    fun bufferStatus() = BufferStatus(streamLive, streamFps, buffer.latest()?.ageMs(clock.nowMs()))
    fun showIdle() = hud.render(HudState.Idle(bufferStatus()))

    /** Wire to DAT Speech transcriptions (partial and final). */
    fun onTranscription(text: String, isFinal: Boolean, confidence: Float = 1f) {
        if (busy) return
        if (!isFinal) {
            if (router.isVisionHint(text)) buffer.pinLatest()
            hud.render(HudState.Listening(text))
            return
        }
        handle(text, router.route(text, confidence))
    }

    /** Debug/HUD buttons and voice share the same path. */
    fun onCommand(intent: GlanceIntent, utterance: String) = handle(utterance, intent)

    private fun handle(utterance: String, intent: GlanceIntent) {
        if (busy) return
        busy = true
        val t0 = clock.nowMs()
        try {
            when (intent) {
                is GlanceIntent.Unknown -> { hud.render(HudState.Error("Didn't catch that")); return }
                is GlanceIntent.Chat -> {
                    hud.render(HudState.Processing(utterance))
                    val r = vlm.infer(null, utterance)
                    finishAnswer(utterance, r.text, "text-only · ${clock.nowMs() - t0} ms")
                }
                GlanceIntent.Describe, GlanceIntent.LogMeal -> {
                    hud.render(HudState.Capturing(utterance))
                    val fr = frames.acquire()
                    val tSel = clock.nowMs() // age at selection time; t0 can precede a frame that arrived while Capturing rendered (seen on emulator: -401 ms)
                    val frame = fr.frame
                    if (frame == null) { hud.render(HudState.Error("No camera frame available")); speaker.speak("I can't see anything right now."); return }
                    val frameAge = (tSel - frame.captureTimeMs).coerceAtLeast(0)
                    hud.render(HudState.Processing(utterance))
                    if (intent == GlanceIntent.Describe) {
                        val r = vlm.infer(frame, Prompts.DESCRIBE)
                        finishAnswer(utterance, r.text, "${fr.note} · frame ${frameAge} ms old · ${clock.nowMs() - t0} ms")
                    } else {
                        val r = vlm.infer(frame, Prompts.MEAL)
                        val entry = MealParser.parse(r.text, clock.nowMs(), frame.captureTimeMs)
                        if (entry == null) {
                            finishAnswer(utterance, "No meal detected. Nothing logged.", "${fr.note} · ${clock.nowMs() - t0} ms")
                        } else {
                            val n = mealLog.insert(entry)
                            val text = "Logged ${entry.name}" + (entry.kcal?.let { ", about $it calories." } ?: ".")
                            hud.render(HudState.Logged(utterance, text, "saved · $n entries · ${clock.nowMs() - t0} ms"))
                            speaker.speak(text)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            hud.render(HudState.Error(e.message ?: "Inference failed"))
        } finally {
            busy = false
        }
    }

    private fun finishAnswer(utterance: String, text: String, meta: String) {
        hud.render(HudState.Answer(utterance, text, meta))
        speaker.speak(text)
    }
}
