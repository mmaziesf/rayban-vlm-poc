// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
import SwiftUI
import MWDATCore
import GlanceCore

@main
struct GlanceAppMain: App {
    @StateObject private var model = GlanceModel()
    init() { try? Wearables.configure() }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .onOpenURL { url in
                    // DAT registration callback, or debug trigger glance-debug://command?text=… (DEBUG only)
                    if model.handleDebugURL(url) { return }
                    Task { _ = try? await Wearables.shared.handleUrl(url) }
                }
        }
    }
}

/// Same graph as Android GlanceGraph: buffer(6) + BufferedFrameSource + controller on one serial queue.
@MainActor
final class GlanceModel: ObservableObject {
    @Published var hudLabel = "Ready"; @Published var hudText = ""; @Published var hudMeta = ""
    @Published var status = "Not started"
    let buffer = FrameRingBuffer(capacity: 6)
    let speaker = AVSpeaker()
    let meals = InMemoryMealLog()
    private let queue = DispatchQueue(label: "glance.controller")
    private var controller: GlanceController?
    private var rig: GlassesRig?
    #if DEBUG
    private var mock: MockRig?
    #endif

    func start(useMock: Bool) {
        let hud = TeeHud { [weak self] s in
            let (_, body, meta) = DatHudRenderer.lines(s)
            Task { @MainActor in self?.hudLabel = s.label; self?.hudText = body; self?.hudMeta = meta }
        }
        let rig = GlassesRig(buffer: buffer)
        let frames = BufferedFrameSource(buffer: buffer, clock: SystemClock(), fallback: rig.makeCapture())
        let ctl = GlanceController(router: IntentRouter(), buffer: buffer, frames: frames, vlm: CannedVlmEngine(),
                                   hud: hud, speaker: speaker, mealLog: meals, clock: SystemClock())
        controller = ctl; self.rig = rig
        Task {
            do {
                var selector: any DeviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
                #if DEBUG
                if useMock { let m = MockRig(); mock = m; selector = try await m.startAndAwait() }
                #endif
                try rig.start(selector: selector) { [weak self] text, fin, conf in
                    self?.queue.async { ctl.onTranscription(text, isFinal: fin, confidence: conf) }
                }
                hud.glasses = rig.hud
                ctl.streamLive = true
                status = useMock ? "Mock glasses connected" : "Glasses session started"
                queue.async { ctl.showIdle() }
            } catch { status = "Start failed: \(error)" }
        }
    }

    func command(_ text: String) {
        guard let ctl = controller else { return }
        queue.async { ctl.onTranscription(text, isFinal: true) }
    }

    func stop() { rig?.stop(); controller?.streamLive = false; status = "Stopped" }

    /// Debug-only analogue of the Android ADB broadcast: xcrun simctl openurl booted 'glance-debug://command?text=what%20am%20I%20seeing'
    func handleDebugURL(_ url: URL) -> Bool {
        #if DEBUG
        guard url.scheme == "glance-debug" else { return false }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let text = q.first { $0.name == "text" }?.value ?? "what am I seeing"
        if q.first(where: { $0.name == "viaMockSpeech" })?.value == "true", let m = mock { m.say(text) } else { command(text) }
        return true
        #else
        return false
        #endif
    }
}

struct ContentView: View {
    @EnvironmentObject var m: GlanceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(m.status).font(.caption).accessibilityIdentifier("status")
            Text(m.hudLabel).font(.title).accessibilityIdentifier("hudLabel")
            Text(m.hudText).accessibilityIdentifier("hudText")
            Text(m.hudMeta).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("hudMeta")
            HStack {
                Button("Start (mock)") { m.start(useMock: true) }.accessibilityIdentifier("startMock")
                Button("Start (glasses)") { m.start(useMock: false) }
                Button("Stop") { m.stop() }
            }
            HStack {
                Button("What am I seeing") { m.command("what am I seeing") }.accessibilityIdentifier("cmdDescribe")
                Button("Log this meal") { m.command("log this meal") }.accessibilityIdentifier("cmdLog")
            }
        }.padding()
    }
}
