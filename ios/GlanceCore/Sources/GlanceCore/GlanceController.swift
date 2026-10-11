import Foundation

/// One turn: transcript → intent → frame → VLM → HUD + speech (+ meal log). Synchronous like the Kotlin version;
/// the app runs it on one serial background queue/actor, tests run it directly with fakes.
public final class GlanceController {
    let router: IntentRouter; let buffer: FrameRingBuffer; let frames: BufferedFrameSource
    let vlm: VlmEngine; let hud: HudRenderer; let speaker: Speaker; let mealLog: MealLog; let clock: Clock
    public var streamFps: Int; public var streamLive: Bool
    public private(set) var busy = false

    public init(router: IntentRouter, buffer: FrameRingBuffer, frames: BufferedFrameSource, vlm: VlmEngine,
                hud: HudRenderer, speaker: Speaker, mealLog: MealLog, clock: Clock, streamFps: Int = 2, streamLive: Bool = false) {
        self.router = router; self.buffer = buffer; self.frames = frames; self.vlm = vlm; self.hud = hud
        self.speaker = speaker; self.mealLog = mealLog; self.clock = clock; self.streamFps = streamFps; self.streamLive = streamLive
    }

    public func bufferStatus() -> BufferStatus { BufferStatus(live: streamLive, fps: streamFps, lastFrameAgeMs: buffer.latest()?.ageMs(clock.nowMs())) }
    public func showIdle() { hud.render(.idle(bufferStatus())) }

    /// Wire to DAT `speech.transcriptionPublisher` (partial and final).
    public func onTranscription(_ text: String, isFinal: Bool, confidence: Float = 1) {
        if busy { return }
        if !isFinal {
            if router.isVisionHint(text) { buffer.pinLatest() }
            hud.render(.listening(partial: text)); return
        }
        handle(text, router.route(text, confidence: confidence))
    }

    public func onCommand(_ intent: GlanceIntent, utterance: String) { handle(utterance, intent) }

    private func handle(_ utterance: String, _ intent: GlanceIntent) {
        if busy { return }
        busy = true; defer { busy = false }
        let t0 = clock.nowMs()
        do {
            switch intent {
            case .unknown:
                hud.render(.error("Didn't catch that"))
            case .chat:
                hud.render(.processing(utterance: utterance))
                let r = try vlm.infer(frame: nil, prompt: utterance)
                finishAnswer(utterance, r.text, "text-only · \(clock.nowMs() - t0) ms")
            case .describe, .logMeal:
                hud.render(.capturing(utterance: utterance))
                let fr = frames.acquire()
                let tSel = clock.nowMs() // age at selection time (Android emulator bug: t0 could precede the frame)
                guard let frame = fr.frame else {
                    hud.render(.error("No camera frame available")); speaker.speak("I can't see anything right now."); return
                }
                let frameAge = max(0, tSel - frame.captureTimeMs)
                hud.render(.processing(utterance: utterance))
                if intent == .describe {
                    let r = try vlm.infer(frame: frame, prompt: Prompts.describe)
                    finishAnswer(utterance, r.text, "\(fr.note) · frame \(frameAge) ms old · \(clock.nowMs() - t0) ms")
                } else {
                    let r = try vlm.infer(frame: frame, prompt: Prompts.meal)
                    if let e = MealParser.parse(r.text, nowMs: clock.nowMs(), frameTimeMs: frame.captureTimeMs) {
                        let n = mealLog.insert(e)
                        let text = "Logged \(e.name)" + (e.kcal.map { ", about \($0) calories." } ?? ".")
                        hud.render(.logged(utterance: utterance, text: text, meta: "saved · \(n) entries · \(clock.nowMs() - t0) ms"))
                        speaker.speak(text)
                    } else {
                        finishAnswer(utterance, "No meal detected. Nothing logged.", "\(fr.note) · \(clock.nowMs() - t0) ms")
                    }
                }
            }
        } catch {
            hud.render(.error("\(error)"))
        }
    }

    private func finishAnswer(_ u: String, _ text: String, _ meta: String) {
        hud.render(.answer(utterance: u, text: text, meta: meta)); speaker.speak(text)
    }
}
