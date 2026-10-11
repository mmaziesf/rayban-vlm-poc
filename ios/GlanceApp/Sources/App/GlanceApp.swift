// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
import SwiftUI
import MWDATCore
import GlanceCore

@main
struct GlanceAppMain: App {
    @StateObject private var model = GlanceModel()
    init() { DatBoot.configure() }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .onOpenURL { url in
                    // DAT registration callback, or debug trigger glance-debug://command?text=… (DEBUG only)
                    if model.handleDebugURL(url) { return }
                    if DatBoot.ok { Task { _ = try? await Wearables.shared.handleUrl(url) } }
                }
        }
    }
}

/// DAT bootstrap result. CI run 38108083323 trapped (EXC_BREAKPOINT, _assertionFailure inside MWDATCore) at the first
/// `Wearables.shared` access → configure() had failed and its error was swallowed by `try?`. Now: record the error,
/// never touch `Wearables.shared` when unconfigured, and show the reason in the UI (UI tests print it on failure).
enum DatBoot {
    nonisolated(unsafe) static var error: String?
    nonisolated(unsafe) static var ok = false
    static func configure() {
        do { try Wearables.configure(); ok = true }
        catch let e as WearablesError where e == .alreadyConfigured { ok = true }
        catch { self.error = "\(error) (\(String(reflecting: error)))"; ok = false }
        NSLog("GlanceDiag: Wearables.configure ok=%@ error=%@", "\(ok)", error ?? "-")
        if ok { observeDevices() }
    }

    /// Like Meta's DisplayAccess/BirdSpotter samples: keep a devicesStream() subscription alive from launch.
    /// Run 38111400016: without it `Wearables.shared.devices` stayed [] after pairing a mock → noEligibleDevice.
    nonisolated(unsafe) static var deviceIds: [DeviceIdentifier] = []
    nonisolated(unsafe) private static var devicesTask: Task<Void, Never>?
    private static func observeDevices() {
        guard devicesTask == nil else { return }
        devicesTask = Task.detached {
            for await ids in Wearables.shared.devicesStream() {
                deviceIds = ids
                let info = ids.map { id -> String in
                    guard let d = Wearables.shared.deviceForIdentifier(id) else { return "\(id)=?" }
                    return "\(id)=\(d.linkState)/\(d.compatibility())"
                }
                NSLog("GlanceDiag: devicesStream %@", info.joined(separator: ", "))
            }
        }
    }
}

/// Same graph as Android GlanceGraph: buffer(6) + BufferedFrameSource + controller on one serial queue.
@MainActor
final class GlanceModel: ObservableObject {
    @Published var hudLabel = "Ready"; @Published var hudText = ""; @Published var hudMeta = ""
    @Published var status = DatBoot.ok ? "Not started" : "DAT configure failed: \(DatBoot.error ?? "?")"
    let buffer = FrameRingBuffer(capacity: 6)
    let speaker = AVSpeaker()
    let meals = InMemoryMealLog()
    private let queue = DispatchQueue(label: "glance.controller")
    private var controller: GlanceController?
    private var rig: GlassesRig?
    #if DEBUG
    private var mock: MockRig?
    #endif

    @Published var mockDeviceId = ""
    private var started = false

    /// Every step is NSLog'd ("GlanceDiag: …", visible in `log show` on CI) and shown in `status`;
    /// any failure lands on the HUD as Error instead of crashing.
    private func step(_ s: String) { NSLog("GlanceDiag: %@", s); status = s }

    func start(useMock: Bool) {
        guard !started else { step("already started"); return }
        // (Removed: enabling MockDeviceKit when DAT is unconfigured — run 38109145843 showed MDK.enable itself traps then.)
        guard DatBoot.ok else {   // touching Wearables.shared now would trap inside MWDATCore
            step("Start failed: DAT configure: \(DatBoot.error ?? "unknown")"); hudLabel = "Error"; hudText = status; return
        }
        started = true
        let hud = TeeHud { [weak self] s in
            let (_, body, meta) = DatHudRenderer.lines(s)
            Task { @MainActor in self?.hudLabel = s.label; self?.hudText = body; self?.hudMeta = meta }
        }
        let rig = GlassesRig(buffer: buffer)
        let frames = BufferedFrameSource(buffer: buffer, clock: SystemClock(), fallback: rig.makeCapture())
        let ctl = GlanceController(router: IntentRouter(), buffer: buffer, frames: frames, vlm: CannedVlmEngine(),
                                   hud: hud, speaker: speaker, mealLog: meals, clock: SystemClock())
        controller = ctl; self.rig = rig
        let queue = self.queue
        Task { @MainActor in
            do {
                var selector: any DeviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
                #if DEBUG
                if useMock {
                    let m = MockRig(); mock = m
                    selector = try await m.startAndAwait { [weak self] in self?.step($0) }
                    mockDeviceId = m.deviceId ?? ""
                }
                #endif
                // @Sendable + explicit main-actor hop: a MainActor-inferred closure called off-main traps at runtime (dispatch_assert_queue).
                try await rig.start(selector: selector, step: { s in Task { @MainActor [weak self] in self?.step(s) } }) { text, fin, conf in
                    queue.async { ctl.onTranscription(text, isFinal: fin, confidence: conf) }
                }
                hud.glasses = rig.hud
                ctl.streamLive = true
                step(useMock ? "Mock glasses connected" : "Glasses session started")
                queue.async { ctl.showIdle() }
            } catch {
                step("Start failed: \(error)")
                hudLabel = "Error"; hudText = "\(error)"
                started = false
            }
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
            Text(m.mockDeviceId).font(.caption2).accessibilityIdentifier("mockDeviceId")
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
