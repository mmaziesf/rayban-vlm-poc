import XCTest
@testable import GlanceCore

// Port of phone/core/src/test/kotlin/glance/core/CoreTests.kt — same scenarios, same expectations.

final class FakeClock: Clock, @unchecked Sendable { var t: Int64; init(_ t: Int64 = 10_000) { self.t = t }; func nowMs() -> Int64 { t } }
final class RecHud: HudRenderer { var states: [HudState] = []; var onRender: ((HudState) -> Void)?
    func render(_ s: HudState) { states.append(s); onRender?(s) } }
final class RecSpeaker: Speaker { var said: [String] = []; func speak(_ t: String) { said.append(t) } }
final class MemLog: MealLog { var rows: [MealEntry] = []; func insert(_ e: MealEntry) -> Int { rows.append(e); return rows.count } }
final class FakeVlm: VlmEngine {
    let clock: FakeClock; let cost: Int64; let reply: (Frame?, String) -> String; var calls: [(Frame?, String)] = []
    init(_ c: FakeClock, cost: Int64 = 0, _ r: @escaping (Frame?, String) -> String) { clock = c; self.cost = cost; reply = r }
    func infer(frame: Frame?, prompt: String) throws -> VlmResult { calls.append((frame, prompt)); clock.t += cost; return VlmResult(text: reply(frame, prompt)) }
}

func lumaFrame(_ t: Int64, w: Int = 64, h: Int = 64, sharp: Bool = true, origin: FrameOrigin = .streamBuffer) -> Frame {
    let y: [UInt8] = (0..<(w * h * 3 / 2)).map { i in
        guard i < w * h else { return 128 }
        return sharp ? ((((i % w) / 8 + (i / w) / 8) % 2 == 0) ? 230 : 20) : 128
    }
    return Frame(bytes: y, width: w, height: h, format: .yuv420, captureTimeMs: t, origin: origin,
                 sharpness: Sharpness.lumaLaplacianVariance(y, width: w, height: h, step: 4))
}

final class IntentRouterTests: XCTestCase {
    let r = IntentRouter()
    func testDescribe() {
        for s in ["What am I seeing?", "what am I looking at right now", "Hey Meta, what am I looking at?",
                  "What's in front of me", "describe this", "what is this", "What do you see"] {
            XCTAssertEqual(r.route(s), .describe, s)
        }
    }
    func testLog() {
        for s in ["Log this meal", "log this", "log my lunch", "save this meal", "Track my dinner", "log what I'm looking at"] {
            XCTAssertEqual(r.route(s), .logMeal, s)
        }
    }
    func testOthers() {
        XCTAssertNotEqual(r.route("what is a catalog"), .logMeal)
        if case .chat = r.route("how many calories are in an apple") {} else { XCTFail("chat") }
        if case .unknown = r.route("   ") {} else { XCTFail("empty→unknown") }
        if case .unknown = r.route("what am I seeing", confidence: 0.1) {} else { XCTFail("low conf→unknown") }
        XCTAssertTrue(r.isVisionHint("what am") && r.isVisionHint("log th") && !r.isVisionHint("tell me"))
        XCTAssertEqual(r.route("Hey Meta, what’s this?"), .describe) // curly apostrophe
    }
}

final class BufferTests: XCTestCase {
    func testSharpness() { XCTAssertGreaterThan(lumaFrame(0).sharpness, lumaFrame(0, sharp: false).sharpness) }
    func testRing() {
        let b = FrameRingBuffer(capacity: 4)
        for i in 0..<6 { b.push(lumaFrame(1000 + Int64(i) * 500)) }
        XCTAssertEqual(b.snapshot().count, 4)
        XCTAssertEqual(b.snapshot().first?.captureTimeMs, 3500); XCTAssertEqual(b.snapshot().last?.captureTimeMs, 2000)
        XCTAssertEqual(b.totalPushed, 6)
        XCTAssertNil(b.select(nowMs: 10_000, maxAgeMs: 1500)); XCTAssertNotNil(b.select(nowMs: 3700, maxAgeMs: 1500))
        XCTAssertEqual(b.bytesHeld(), 4 * (64 * 64 * 3 / 2))
        let m = FrameRingBuffer(capacity: 4); m.push(lumaFrame(1000)); m.push(lumaFrame(1500, sharp: false))
        XCTAssertEqual(m.select(nowMs: 1600, maxAgeMs: 1500)?.captureTimeMs, 1000, "prefers sharp over newest-blurry")
    }
    func testChip() {
        XCTAssertEqual(BufferStatus(live: true, fps: 2, lastFrameAgeMs: 300).chip(), "Live 2 fps · 0.3 s")
        XCTAssertEqual(BufferStatus(live: false, fps: 2, lastFrameAgeMs: nil).chip(), "Camera off")
    }
    func testMealParser() {
        XCTAssertNil(MealParser.parse("no json here", nowMs: 0, frameTimeMs: 0))
        let e = MealParser.parse(#"Sure: {"is_food":true,"name":"Grilled salmon","kcal":620,"protein_g":42}"#, nowMs: 1, frameTimeMs: 0)
        XCTAssertEqual(e?.name, "Grilled salmon"); XCTAssertEqual(e?.kcal, 620); XCTAssertEqual(e?.proteinG, 42)
        XCTAssertNil(MealParser.parse(#"{"is_food":false}"#, nowMs: 0, frameTimeMs: 0))
    }
}

final class ControllerTests: XCTestCase {
    func testEndToEndWithFakes() {
        let r = IntentRouter(); let clock = FakeClock(10_000); let ring = FrameRingBuffer(capacity: 6)
        var captureCalls = 0
        let fallback = ClosureCapture { captureCalls += 1; clock.t += 1800; return lumaFrame(clock.t, origin: .photoCapture) }
        let hud = RecHud(); let spk = RecSpeaker(); let log = MemLog()
        let vlm = FakeVlm(clock, cost: 900) { f, p in
            if p == Prompts.meal { return #"Sure: {"is_food":true,"name":"Grilled salmon","kcal":620,"protein_g":42}"# }
            return f == nil ? "Text answer" : "A desk with a laptop."
        }
        let c = GlanceController(router: r, buffer: ring, frames: BufferedFrameSource(buffer: ring, clock: clock, fallback: fallback),
                                 vlm: vlm, hud: hud, speaker: spk, mealLog: log, clock: clock, streamFps: 2, streamLive: true)
        for _ in 0..<5 { ring.push(lumaFrame(clock.t)); clock.t += 500 }
        c.onTranscription("what am", isFinal: false)
        let pinnedT = ring.latest()!.captureTimeMs
        clock.t += 700; ring.push(lumaFrame(clock.t)) // head turned after speaking began
        c.onTranscription("What am I seeing?", isFinal: true)
        XCTAssertEqual(spk.said.last, "A desk with a laptop.")
        XCTAssertEqual(vlm.calls.last?.0?.captureTimeMs, pinnedT, "describe used pinned frame")
        XCTAssertEqual(captureCalls, 0)
        XCTAssertEqual(hud.states.map(\.label), ["Listening", "Capturing", "Thinking", "Answer"])
        guard case .answer(_, _, let meta) = hud.states.last! else { return XCTFail() }
        XCTAssertTrue(meta.hasPrefix("pinned"), meta)

        ring.push(lumaFrame(clock.t))
        c.onTranscription("log this meal", isFinal: true)
        XCTAssertEqual(log.rows.first?.name, "Grilled salmon"); XCTAssertEqual(log.rows.first?.kcal, 620)
        XCTAssertEqual(hud.states.last?.label, "Logged")

        clock.t += 10_000
        c.onTranscription("what am I looking at", isFinal: true)
        XCTAssertEqual(captureCalls, 1, "stale buffer uses capture fallback")
        guard case .answer(_, _, let m2) = hud.states.last! else { return XCTFail() }
        XCTAssertTrue(m2.hasPrefix("capture-fallback"), m2)

        c.onTranscription("how far is the moon", isFinal: true)
        XCTAssertNil(vlm.calls.last?.0, "chat is text-only")
    }

    func testNoFrameAndNonFood() {
        let r = IntentRouter(); let clock = FakeClock()
        let hud2 = RecHud(); let b = FrameRingBuffer(capacity: 2)
        GlanceController(router: r, buffer: b, frames: BufferedFrameSource(buffer: b, clock: clock, fallback: nil),
                         vlm: FakeVlm(clock) { _, _ in "x" }, hud: hud2, speaker: RecSpeaker(), mealLog: MemLog(), clock: clock)
            .onTranscription("what am I seeing", isFinal: true)
        XCTAssertEqual(hud2.states.last?.label, "Error")

        let hud3 = RecHud(); let log3 = MemLog(); let ring3 = FrameRingBuffer(capacity: 2); ring3.push(lumaFrame(clock.t))
        GlanceController(router: r, buffer: ring3, frames: BufferedFrameSource(buffer: ring3, clock: clock, fallback: nil),
                         vlm: FakeVlm(clock) { _, _ in #"{"is_food":false}"# }, hud: hud3, speaker: RecSpeaker(), mealLog: log3, clock: clock)
            .onTranscription("log this", isFinal: true)
        XCTAssertTrue(log3.rows.isEmpty)
        guard case .answer(_, let text, _) = hud3.states.last! else { return XCTFail() }
        XCTAssertTrue(text.hasPrefix("No meal"))
    }

    /// Regression from the Android TCG emulator (2026-10-10): a frame arriving while Capturing renders must not give a negative age.
    func testFrameAgeNeverNegative() {
        let ck = FakeClock(50_000); let rb = FrameRingBuffer(capacity: 6); let hud = RecHud()
        hud.onRender = { s in if case .capturing = s { ck.t += 3000; rb.push(lumaFrame(ck.t)) } }
        GlanceController(router: IntentRouter(), buffer: rb, frames: BufferedFrameSource(buffer: rb, clock: ck, fallback: nil),
                         vlm: FakeVlm(ck, cost: 200) { _, _ in "ok" }, hud: hud, speaker: RecSpeaker(), mealLog: MemLog(),
                         clock: ck, streamFps: 2, streamLive: true).onTranscription("what am I seeing", isFinal: true)
        guard case .answer(_, _, let m) = hud.states.last! else { return XCTFail("\(hud.states)") }
        XCTAssertTrue(m.contains("frame 0 ms old") && !m.contains("-"), m)
    }
}
