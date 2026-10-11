// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
import Foundation
import AVFoundation
import GlanceCore

/// Deterministic engine used in mock/UI tests (same canned behaviour as Android CannedVlmEngine).
struct CannedVlmEngine: VlmEngine {
    func infer(frame: Frame?, prompt: String) throws -> VlmResult {
        Thread.sleep(forTimeInterval: 0.3)
        if prompt.contains("JSON") {
            return VlmResult(text: #"{"is_food":true,"name":"salmon with rice and broccoli","kcal":620,"protein_g":42}"#)
        }
        return VlmResult(text: frame == nil ? "I can't see anything right now." : "A plate with salmon, rice and broccoli on a table.")
    }
}

/// Placeholder for the real on-device VLM. Options (see docs/IOS_OPTIONS.md §VLM):
///  - LiteRT-LM Swift API (Early Preview, Metal GPU). Gemma 4 **E2B** — E4B vision currently broken on iOS
///    (google-ai-edge/LiteRT-LM#2370).
///  - MLX Swift port (gemma-4-swift-mlx).
/// Intentionally not implemented: no API was compiled/verified from Linux.
struct OnDeviceVlmEngine: VlmEngine {
    struct NotWired: Error {}
    func infer(frame: Frame?, prompt: String) throws -> VlmResult { throw NotWired() }
}

final class AVSpeaker: Speaker, @unchecked Sendable {
    private let synth = AVSpeechSynthesizer()
    private(set) var lastSpoken: String?
    func speak(_ text: String) {
        lastSpoken = text
        let u = AVSpeechUtterance(string: text); u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)   // routes to glasses speakers when they are the active BT audio route
    }
}

final class InMemoryMealLog: MealLog, @unchecked Sendable {
    private(set) var entries: [MealEntry] = []
    private let lock = NSLock()
    func insert(_ entry: MealEntry) -> Int { lock.lock(); defer { lock.unlock() }; entries.append(entry); return entries.count }
}
