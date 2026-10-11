import Foundation

/// Abstractions the iOS/DAT layer implements. Core never touches DAT, LiteRT-LM or AVFoundation.
public protocol Clock: Sendable { func nowMs() -> Int64 }
public struct SystemClock: Clock { public init() {}; public func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) } }

public struct FrameResult { public let frame: Frame?; public let note: String }

/// On-demand frame (DAT `stream.capturePhoto(format:)` / `camera.photo`). May be slow.
public protocol OnDemandCapture { func capture() -> Frame? }
public struct ClosureCapture: OnDemandCapture { let f: () -> Frame?; public init(_ f: @escaping () -> Frame?) { self.f = f }; public func capture() -> Frame? { f() } }

public struct VlmResult { public let text: String; public init(text: String) { self.text = text } }
public protocol VlmEngine { func infer(frame: Frame?, prompt: String) throws -> VlmResult }
public protocol Speaker { func speak(_ text: String) }
public protocol HudRenderer { func render(_ state: HudState) }

public struct MealEntry: Equatable {
    public let tsMs: Int64; public let name: String; public let kcal: Int?; public let proteinG: Int?
    public let frameTimeMs: Int64; public let rawJson: String
}
public protocol MealLog { func insert(_ entry: MealEntry) -> Int }
