import Foundation

public enum FrameFormat: Sendable { case yuv420, jpeg, bgra }
public enum FrameOrigin: Sendable { case streamBuffer, photoCapture, testAsset }

/// One camera frame held on the phone. For `.yuv420` the first width*height bytes are luma.
/// On iOS, DAT `VideoFrame.sampleBuffer` (codec `.raw`) → CVPixelBuffer → copy plane 0 here (see GlanceApp/DAT).
public final class Frame: @unchecked Sendable, CustomStringConvertible {
    public let bytes: [UInt8]; public let width: Int; public let height: Int
    public let format: FrameFormat; public let captureTimeMs: Int64; public let origin: FrameOrigin
    public let sharpness: Double
    public init(bytes: [UInt8], width: Int, height: Int, format: FrameFormat, captureTimeMs: Int64,
                origin: FrameOrigin, sharpness: Double = .nan) {
        self.bytes = bytes; self.width = width; self.height = height; self.format = format
        self.captureTimeMs = captureTimeMs; self.origin = origin; self.sharpness = sharpness
    }
    public func ageMs(_ nowMs: Int64) -> Int64 { nowMs - captureTimeMs }
    public var description: String { "Frame(\(width)x\(height) \(format) \(origin) t=\(captureTimeMs))" }
}

/// Variance of a 4-neighbour Laplacian on a subsampled luma plane. Higher = sharper.
public enum Sharpness {
    public static func lumaLaplacianVariance(_ luma: [UInt8], width: Int, height: Int, step: Int = 8) -> Double {
        precondition(luma.count >= width * height, "luma too small")
        var n = 0; var sum = 0.0; var sumSq = 0.0
        var y = step
        while y < height - step {
            var x = step; let row = y * width
            while x < width - step {
                let c = Int(luma[row + x])
                let l = Int(luma[row + x - step]) + Int(luma[row + x + step]) +
                        Int(luma[row - step * width + x]) + Int(luma[row + step * width + x]) - 4 * c
                sum += Double(l); sumSq += Double(l) * Double(l); n += 1
                x += step
            }
            y += step
        }
        if n == 0 { return 0 }
        let mean = sum / Double(n)
        return sumSq / Double(n) - mean * mean
    }
}

/// Fixed-capacity rolling buffer of recent frames (thread-safe). 2 fps × 6 = ~3 s of history.
public final class FrameRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private var slots: [Frame?]; private var head = 0; private var count = 0; private var pinned: Frame?
    private let lock = NSLock()
    public private(set) var totalPushed: Int64 = 0

    public init(capacity: Int) { precondition(capacity > 0); self.capacity = capacity; slots = Array(repeating: nil, count: capacity) }
    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }

    public func push(_ frame: Frame) { locked { slots[head] = frame; head = (head + 1) % capacity; if count < capacity { count += 1 }; totalPushed += 1 } }
    /// Newest first.
    public func snapshot() -> [Frame] { locked { (0..<count).map { slots[(head - 1 - $0 + capacity * 2) % capacity]! } } }
    public func latest() -> Frame? { locked { count == 0 ? nil : slots[(head - 1 + capacity) % capacity] } }
    public func bytesHeld() -> Int { snapshot().reduce(0) { $0 + $1.bytes.count } }

    /// Newest frames within maxAgeMs; among the newest `lookback`, the sharpest (if all scored).
    public func select(nowMs: Int64, maxAgeMs: Int64, lookback: Int = 3) -> Frame? {
        let fresh = Array(snapshot().filter { $0.ageMs(nowMs) <= maxAgeMs }.prefix(lookback))
        guard let first = fresh.first else { return nil }
        let scored = fresh.filter { !$0.sharpness.isNaN }
        return scored.count == fresh.count ? scored.max { $0.sharpness < $1.sharpness } : first
    }

    @discardableResult public func pinLatest() -> Frame? { let l = latest(); locked { pinned = l }; return l }
    public func takePinned() -> Frame? { locked { let p = pinned; pinned = nil; return p } }
    public func clear() { locked { slots = Array(repeating: nil, count: capacity); head = 0; count = 0; pinned = nil } }
}
