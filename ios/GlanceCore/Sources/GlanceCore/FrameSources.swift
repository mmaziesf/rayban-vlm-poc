import Foundation

/// Buffer first (instant); pinned frame wins if fresh; fallback = on-demand capture. Same policy as Android.
public struct BufferedFrameSource {
    let buffer: FrameRingBuffer; let clock: Clock; let fallback: OnDemandCapture?; let maxAgeMs: Int64
    public init(buffer: FrameRingBuffer, clock: Clock, fallback: OnDemandCapture?, maxAgeMs: Int64 = 1500) {
        self.buffer = buffer; self.clock = clock; self.fallback = fallback; self.maxAgeMs = maxAgeMs
    }
    public func acquire() -> FrameResult {
        let now = clock.nowMs()
        if let p = buffer.takePinned(), p.ageMs(now) <= maxAgeMs * 2 { return FrameResult(frame: p, note: "pinned") }
        if let f = buffer.select(nowMs: now, maxAgeMs: maxAgeMs) { return FrameResult(frame: f, note: "buffer") }
        if let f = fallback?.capture() { return FrameResult(frame: f, note: "capture-fallback") }
        return FrameResult(frame: nil, note: "no-frame")
    }
}
