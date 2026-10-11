import Foundation

/// Mirrors webapp/ and Android HudState 1:1.
public enum HudState: Equatable {
    case idle(BufferStatus)
    case listening(partial: String)
    case capturing(utterance: String)
    case processing(utterance: String)
    case answer(utterance: String, text: String, meta: String)
    case logged(utterance: String, text: String, meta: String)
    case error(String)

    public var label: String {
        switch self {
        case .idle: "Ready"; case .listening: "Listening"; case .capturing: "Capturing"; case .processing: "Thinking"
        case .answer: "Answer"; case .logged: "Logged"; case .error: "Error"
        }
    }
}

public struct BufferStatus: Equatable {
    public let live: Bool; public let fps: Int; public let lastFrameAgeMs: Int64?
    public init(live: Bool, fps: Int, lastFrameAgeMs: Int64?) { self.live = live; self.fps = fps; self.lastFrameAgeMs = lastFrameAgeMs }
    public func chip() -> String {
        guard live else { return "Camera off" }
        guard let a = lastFrameAgeMs else { return "Live · waiting" }
        return "Live \(fps) fps · " + String(format: "%.1f", Double(a) / 1000) + " s"
    }
}
