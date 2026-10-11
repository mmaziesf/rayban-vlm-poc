package glance.core

// Dependency-free test runner so it compiles with plain kotlinc (no Gradle/JUnit needed on the box).
private var failures = 0
private var passes = 0
private fun check(name: String, cond: Boolean, info: Any? = null) {
    if (cond) { passes++; println("PASS  $name") } else { failures++; println("FAIL  $name  ${info ?: ""}") }
}

class FakeClock(var t: Long = 10_000) : Clock { override fun nowMs() = t }
class RecHud : HudRenderer { val states = mutableListOf<HudState>(); override fun render(state: HudState) { states += state } }
class RecSpeaker : Speaker { val said = mutableListOf<String>(); override fun speak(text: String) { said += text } }
class MemLog : MealLog { val rows = mutableListOf<MealEntry>(); override fun insert(entry: MealEntry): Int { rows += entry; return rows.size } }
class FakeVlm(private val clock: FakeClock, private val costMs: Long = 0, val reply: (Frame?, String) -> String) : VlmEngine {
    val calls = mutableListOf<Pair<Frame?, String>>()
    override fun infer(frame: Frame?, prompt: String): VlmResult { calls += frame to prompt; clock.t += costMs; return VlmResult(reply(frame, prompt)) }
}

fun lumaFrame(t: Long, w: Int = 64, h: Int = 64, sharp: Boolean = true, origin: FrameOrigin = FrameOrigin.STREAM_BUFFER): Frame {
    val y = ByteArray(w * h * 3 / 2) { i -> if (i < w * h) (if (sharp) (if (((i % w) / 8 + (i / w) / 8) % 2 == 0) 230 else 20) else 128).toByte() else 128.toByte() }
    return Frame(y, w, h, FrameFormat.YUV420, t, origin, Sharpness.lumaLaplacianVariance(y, w, h, step = 4))
}

fun main() {
    val r = IntentRouter()
    // --- IntentRouter
    for (s in listOf("What am I seeing?", "what am I looking at right now", "Hey Meta, what am I looking at?",
                     "What's in front of me", "describe this", "what is this", "What do you see"))
        check("route describe: '$s'", r.route(s) == GlanceIntent.Describe, r.route(s))
    for (s in listOf("Log this meal", "log this", "log my lunch", "save this meal", "Track my dinner", "log what I'm looking at"))
        check("route log: '$s'", r.route(s) == GlanceIntent.LogMeal, r.route(s))
    check("'catalog this' is not a log", r.route("what is a catalog") == GlanceIntent.Describe || r.route("what is a catalog") is GlanceIntent.Chat)
    check("route chat", r.route("how many calories are in an apple") is GlanceIntent.Chat)
    check("route empty -> unknown", r.route("   ") is GlanceIntent.Unknown)
    check("low confidence -> unknown", r.route("what am I seeing", 0.1f) is GlanceIntent.Unknown)
    check("vision hint on partial", r.isVisionHint("what am") && r.isVisionHint("log th") && !r.isVisionHint("tell me"))

    // --- Sharpness
    val sharpF = lumaFrame(0, sharp = true); val flatF = lumaFrame(0, sharp = false)
    check("sharpness ranks textured > flat", sharpF.sharpness > flatF.sharpness, "${sharpF.sharpness} vs ${flatF.sharpness}")

    // --- Ring buffer
    val buf = FrameRingBuffer(4)
    for (i in 0 until 6) buf.push(lumaFrame(1000L + i * 500))
    check("ring keeps capacity", buf.snapshot().size == 4)
    check("ring newest first", buf.snapshot().first().captureTimeMs == 3500L && buf.snapshot().last().captureTimeMs == 2000L)
    check("totalPushed counts all", buf.totalPushed == 6L)
    check("select returns null when stale", buf.select(nowMs = 10_000, maxAgeMs = 1500) == null)
    check("select returns fresh", buf.select(nowMs = 3700, maxAgeMs = 1500) != null)
    val mixed = FrameRingBuffer(4)
    mixed.push(lumaFrame(1000, sharp = true)); mixed.push(lumaFrame(1500, sharp = false))
    check("select prefers sharp over newest-blurry", mixed.select(1600, 1500)?.captureTimeMs == 1000L)
    check("bytesHeld", buf.bytesHeld() == 4L * (64 * 64 * 3 / 2))

    // --- Controller end-to-end with buffered frames
    val clock = FakeClock(10_000)
    val ring = FrameRingBuffer(6)
    var captureCalls = 0
    val fallback = OnDemandCapture { captureCalls++; clock.t += 1800; lumaFrame(clock.t, origin = FrameOrigin.PHOTO_CAPTURE) }
    val src = BufferedFrameSource(ring, clock, fallback, maxAgeMs = 1500)
    val hud = RecHud(); val spk = RecSpeaker(); val log = MemLog()
    val vlm = FakeVlm(clock, costMs = 900) { f, p ->
        when {
            p == Prompts.MEAL -> """Sure: {"is_food":true,"name":"Grilled salmon","kcal":620,"protein_g":42}"""
            f == null -> "Text answer"
            else -> "A desk with a laptop."
        }
    }
    val c = GlanceController(r, ring, src, vlm, hud, spk, log, clock, streamFps = 2, streamLive = true)

    // stream at 2 fps
    for (i in 0 until 5) { ring.push(lumaFrame(clock.t)); clock.t += 500 }
    c.onTranscription("what am", isFinal = false)
    val pinnedT = ring.latest()!!.captureTimeMs
    clock.t += 700; ring.push(lumaFrame(clock.t)) // head turned after speaking began
    c.onTranscription("What am I seeing?", isFinal = true)
    check("describe answered", spk.said.lastOrNull() == "A desk with a laptop.", spk.said)
    check("describe used pinned frame (not newer)", vlm.calls.last().first?.captureTimeMs == pinnedT)
    check("no slow capture when buffer fresh", captureCalls == 0)
    val seq = hud.states.map { it.label }
    check("HUD sequence listening→capturing→thinking→answer", seq == listOf("Listening", "Capturing", "Thinking", "Answer"), seq)
    check("answer meta mentions pinned", (hud.states.last() as HudState.Answer).meta.startsWith("pinned"))

    // regression (emulator 2026-10-10): slow HUD render while Capturing → a newer frame arrives after t0; age must not be negative
    run {
        val ck = FakeClock(50_000); val rb = FrameRingBuffer(6)
        val slowHud = object : HudRenderer { val st = mutableListOf<HudState>()
            override fun render(state: HudState) { st += state; if (state is HudState.Capturing) { ck.t += 3000; rb.push(lumaFrame(ck.t)) } } }
        val cc = GlanceController(r, rb, BufferedFrameSource(rb, ck, null, maxAgeMs = 1500), FakeVlm(ck, 200) { _, _ -> "ok" },
            slowHud, RecSpeaker(), MemLog(), ck, streamFps = 2, streamLive = true)
        cc.onTranscription("what am I seeing", isFinal = true)
        val m = (slowHud.st.last() as? HudState.Answer)?.meta ?: ""
        check("frame age never negative", m.contains("frame 0 ms old") && !m.contains("-"), m)
    }

    // log meal from buffer
    ring.push(lumaFrame(clock.t))
    c.onTranscription("log this meal", isFinal = true)
    check("meal logged", log.rows.size == 1 && log.rows[0].name == "Grilled salmon" && log.rows[0].kcal == 620, log.rows)
    check("logged HUD", hud.states.last() is HudState.Logged)

    // stale buffer -> fallback capture
    clock.t += 10_000
    c.onTranscription("what am I looking at", isFinal = true)
    check("stale buffer uses capture fallback", captureCalls == 1)
    check("fallback meta", (hud.states.last() as HudState.Answer).meta.startsWith("capture-fallback"))

    // no frames at all and no fallback
    val hud2 = RecHud()
    val c3 = GlanceController(r, FrameRingBuffer(2), BufferedFrameSource(FrameRingBuffer(2), clock, null), vlm, hud2, spk, log, clock)
    c3.onTranscription("what am I seeing", true)
    check("no frame -> error state", hud2.states.last() is HudState.Error)

    // non-food
    val vlm2 = FakeVlm(clock) { _, _ -> """{"is_food":false}""" }
    val hud3 = RecHud(); val log3 = MemLog(); val ring3 = FrameRingBuffer(2); ring3.push(lumaFrame(clock.t))
    GlanceController(r, ring3, BufferedFrameSource(ring3, clock, null), vlm2, hud3, RecSpeaker(), log3, clock).onTranscription("log this", true)
    check("non-food not logged", log3.rows.isEmpty() && (hud3.states.last() as HudState.Answer).text.startsWith("No meal"))

    // chat
    c.onTranscription("how far is the moon", true)
    check("chat is text-only (no frame)", vlm.calls.last().first == null)

    check("buffer chip", BufferStatus(true, 2, 300).chip() == "Live 2 fps · 0.3 s" && BufferStatus(false, 2, null).chip() == "Camera off")
    check("MealParser rejects garbage", MealParser.parse("no json here", 0, 0) == null)


    // --- VlmSelection (M1c stub vs real) ---
    run {
        val ok = VlmSelection.Candidate("/m/gemma.litertlm", true, 100)
        val missing = VlmSelection.Candidate("/x/gemma.litertlm", false, 0)
        val big = 8L shl 30
        check("vlm: stub by default", VlmSelection.decide("stub", null, listOf(ok), 100, big).mode == VlmSelection.Mode.STUB)
        val r = VlmSelection.decide("real", null, listOf(missing, ok), 100, big)
        check("vlm: real when model present", r.mode == VlmSelection.Mode.REAL && r.modelPath == "/m/gemma.litertlm", r)
        check("vlm: override real", VlmSelection.decide("stub", "real", listOf(ok), 100, null).mode == VlmSelection.Mode.REAL)
        check("vlm: override stub", VlmSelection.decide("real", "stub", listOf(ok), 100, null).mode == VlmSelection.Mode.STUB)
        check("vlm: unknown override ignored", VlmSelection.decide("real", "garbage", listOf(ok), 100, null).mode == VlmSelection.Mode.REAL)
        val nf = VlmSelection.decide("real", null, listOf(missing), 100, null)
        check("vlm: no file → stub + reason", nf.mode == VlmSelection.Mode.STUB && nf.reason.contains("no model"), nf)
        val part = VlmSelection.decide("real", null, listOf(ok.copy(sizeBytes = 50)), 100, null)
        check("vlm: partial push → stub", part.mode == VlmSelection.Mode.STUB && part.reason.contains("incomplete"), part)
        val low = VlmSelection.decide("real", null, listOf(ok), 100, 1L shl 30)
        check("vlm: low RAM → stub", low.mode == VlmSelection.Mode.STUB && low.reason.contains("low RAM"), low)
    }

    hplTests { n, c, i -> check(n, c, i) }

    println("\n$passes passed, $failures failed")
    if (failures > 0) kotlin.system.exitProcess(1)
}

