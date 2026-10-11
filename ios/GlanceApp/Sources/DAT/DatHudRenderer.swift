// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
import Foundation
import MWDATDisplay
import GlanceCore

/// HudState → DAT Display FlexBox. Mirrors Android DatHudRenderer; also logs a stable line for UI tests / log scraping.
final class DatHudRenderer: HudRenderer, @unchecked Sendable {
    private let display: Display
    init(display: Display) { self.display = display }

    func render(_ state: HudState) {
        let (title, body, meta) = Self.lines(state)
        Task { [display] in
            try? await display.send(FlexBox(direction: .column, spacing: 6) {
                Text(title, style: .heading)
                if !body.isEmpty { Text(body) }
                if !meta.isEmpty { Text(meta, style: .meta, color: .secondary) }
            })
        }
    }
    func stop() { display.stop() }

    static func lines(_ s: HudState) -> (String, String, String) {
        switch s {
        case .idle(let b): return ("Glance", "Say: what am I seeing / log this meal", b.chip())
        case .listening(let p): return ("Listening", p, "")
        case .capturing(let u), .processing(let u): return (s.label, u, "")
        case .answer(_, let t, let m), .logged(_, let t, let m): return (s.label, t, m)
        case .error(let e): return ("Error", e, "")
        }
    }
}

/// Tee: phone SwiftUI state + log line + optional glasses display (same as Android LoggingHud).
final class TeeHud: HudRenderer, @unchecked Sendable {
    var glasses: HudRenderer?
    let sink: @Sendable (HudState) -> Void
    init(sink: @escaping @Sendable (HudState) -> Void) { self.sink = sink }
    func render(_ state: HudState) {
        let (_, body, meta) = DatHudRenderer.lines(state)
        print("GlanceHud: state=\(state.label) text=\"\(body)\" meta=\"\(meta)\"")
        sink(state); glasses?.render(state)
    }
}
