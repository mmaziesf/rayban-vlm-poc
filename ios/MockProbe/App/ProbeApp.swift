// Minimal DAT MockDeviceKit probe, written to mirror Meta's CameraAccess sample flow (whose mock session starts on
// macos-26 CI). Built as 4 app targets that differ ONLY in linked DAT products (project.yml) to find out whether
// linking MWDATDisplay / MWDATSpeech keeps a mock device from becoming active/connected (GlanceApp: it never does).
import SwiftUI
import MWDATCore
import MWDATMockDevice

@main
struct ProbeApp: App {
    #if MOCK_EARLY
    // Meta's CameraAccessApp builds `MockDeviceKitViewModel(mockDeviceKit: MockDeviceKit.shared)` in a stored-property
    // initializer, i.e. BEFORE `Wearables.configure()` runs in init(). Mirror that ordering.
    private let earlyKitEnabled: Bool = {
        let e = MockDeviceKit.shared.isEnabled
        NSLog("ProbeDiag: MockDeviceKit.shared touched before configure (isEnabled=%@)", "\(e)")
        return e
    }()
    #endif
    init() {
        do { try Wearables.configure() } catch { NSLog("ProbeDiag: configure failed: \(error)") }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: false))
            let portFilePath = ProcessInfo.processInfo.environment["MWDAT_TEST_SERVER_PORT_FILE"]
            Task {
                do { _ = try await MockDeviceKit.shared.startTestServer(portFilePath: portFilePath) }
                catch { NSLog("ProbeDiag: test server failed: \(error)") }
            }
        }
    }
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var reg = "?"
    @Published var active = "active=nil"
    @Published var link = "-"
    @Published var session = "-"
    private let selector = AutoDeviceSelector(wearables: Wearables.shared)
    private var deviceSession: DeviceSession?

    init() {
        Task { for await st in Wearables.shared.registrationStateStream() { self.reg = st == .registered ? "registered" : "\(st)" } }
        Task { for await id in self.selector.activeDeviceStream() { self.active = "active=\(id ?? "nil")"; NSLog("ProbeDiag: %@", self.active) } }
        Task {
            while true {   // poll link/compat of every known device
                let s = Wearables.shared.devices.map { id in
                    Wearables.shared.deviceForIdentifier(id).map { "\($0.linkState)/\($0.compatibility())" } ?? "?"
                }.joined(separator: ",")
                if s != self.link { self.link = s; NSLog("ProbeDiag: link %@", s) }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func register() {
        Task {
            do { try await Wearables.shared.startRegistration() }
            catch { self.reg = "error \(error)" }
        }
    }

    func startSession() {
        do {
            let s = try Wearables.shared.createSession(deviceSelector: selector)
            deviceSession = s
            Task { for await st in s.stateStream() { self.session = "\(st)"; NSLog("ProbeDiag: session %@", "\(st)") } }
            try s.start()
        } catch { session = "error \(error)"; NSLog("ProbeDiag: session error %@", "\(error)") }
    }
}

struct ProbeView: View {
    @StateObject private var m = ProbeModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(m.reg).accessibilityIdentifier("reg")
            Text(m.active).accessibilityIdentifier("active")
            Text(m.link).accessibilityIdentifier("link")
            Text(m.session).accessibilityIdentifier("session")
            Button("Register") { m.register() }.accessibilityIdentifier("register")
            Button("Start session") { m.startSession() }.accessibilityIdentifier("startSession")
        }
        .padding()
        .onOpenURL { url in Task { _ = try? await Wearables.shared.handleUrl(url) } }
    }
}
