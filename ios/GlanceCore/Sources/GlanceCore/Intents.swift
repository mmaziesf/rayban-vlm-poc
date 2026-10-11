import Foundation

/// What the wearer asked for. Vision intents need a frame. Mirrors glance.core.GlanceIntent (Kotlin).
public enum GlanceIntent: Equatable, Sendable {
    case describe, logMeal
    case chat(String)
    case unknown(String)
    public var needsFrame: Bool { self == .describe || self == .logMeal }
}

/// Maps glasses ASR transcripts (DAT `Speech.transcriptionPublisher`) to intents. Same regexes as Android.
public struct IntentRouter: Sendable {
    let minConfidence: Float
    public init(minConfidence: Float = 0.4) { self.minConfidence = minConfidence }

    private static let describe = [
        Rx(#"\bwhat(?:'s| is| am i| are we)? (?:i'?m |am i )?(?:seeing|looking at|in front of me)\b"#),
        Rx(#"\bwhat do (?:i|you) see\b"#),
        Rx(#"\bdescribe (?:this|that|what i see|the scene|it)\b"#),
        Rx(#"\bwhat(?:'s| is) (?:this|that)\b"#),
    ]
    private static let logMeal = [
        Rx(#"^(?:please )?log (?:what|it\b)"#),
        Rx(#"\blog (?:this|that|my)(?: (?:meal|food|plate|lunch|dinner|breakfast|snack))?\b"#),
        Rx(#"\b(?:save|record|track) (?:this|my) (?:meal|food|plate|lunch|dinner|breakfast|snack)\b"#),
    ]
    private static let wake = Rx(#"^(?:hey meta[, ]*|ok(?:ay)? glance[, ]*|glance[, ]*)"#)
    private static let nonWord = Rx(#"[^a-z0-9' ]"#)
    private static let spaces = Rx(#"\s+"#)

    public func normalize(_ text: String) -> String {
        var t = text.lowercased().replacingOccurrences(of: "’", with: "'")
        t = Self.wake.replacing(t, with: "")
        t = Self.nonWord.replacing(t, with: " ")
        t = Self.spaces.replacing(t, with: " ")
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Route a FINAL transcript. "log …" wins over describe ("log what I'm looking at" is a log).
    public func route(_ text: String, confidence: Float = 1) -> GlanceIntent {
        let t = normalize(text)
        if t.isEmpty || confidence < minConfidence { return .unknown(text) }
        if Self.logMeal.contains(where: { $0.matches(t) }) { return .logMeal }
        if Self.describe.contains(where: { $0.matches(t) }) { return .describe }
        return .chat(text.trimmingCharacters(in: .whitespaces))
    }

    /// Cheap early signal on a PARTIAL transcript, used to pin the buffer frame before the final arrives.
    public func isVisionHint(_ partial: String) -> Bool {
        let t = normalize(partial)
        return t.hasPrefix("what") || t.hasPrefix("log") || t.hasPrefix("describe")
    }
}
