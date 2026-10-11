// Debug-only Mock Device Kit rig. Mirrors Android debug MockRig and Meta's DisplayAccess sample
// (LivePhonePreviewManager): enable → pair RBD → powerOn/unfold/don → wait until linkState == .connected &&
// compatibility == .compatible → SpecificDeviceSelector(device: id).
#if DEBUG
import Foundation
import MWDATCore
import MWDATMockDevice

enum MockRigError: Error, CustomStringConvertible {
    case notReady(link: String, compat: String)
    var description: String {
        switch self { case .notReady(let l, let c): "mock device not ready (link=\(l), compat=\(c))" }
    }
}

final class MockRig: @unchecked Sendable {
    private var glasses: (any MockGlasses)?
    private(set) var deviceId: DeviceIdentifier?

    @MainActor
    func startAndAwait(timeout: Duration = .seconds(15), step: (String) -> Void) async throws -> any DeviceSelector {
        let kit = MockDeviceKit.shared
        step("MDK enable")
        // Like Meta's CameraAccess UI tests (mock pair → active device passes on CI): start UNREGISTERED and go through
        // startRegistration() (MDK's fake handler), instead of the initiallyRegistered shortcut. With the shortcut,
        // AutoDeviceSelector never yields an active device in our app (run 38118355688).
        if !kit.isEnabled { kit.enable(config: MockDeviceKitConfig(initiallyRegistered: false, initialPermissionsGranted: true)) }
        if Wearables.shared.registrationState != .registered {
            step("MDK startRegistration (state=\(Wearables.shared.registrationState))")
            do { try await Wearables.shared.startRegistration() } catch { step("WARN startRegistration: \(error)") }
            let clock = ContinuousClock(); let deadline = clock.now.advanced(by: .seconds(10))
            while Wearables.shared.registrationState != .registered, clock.now < deadline { try? await clock.sleep(for: .milliseconds(100)) }
            step("MDK registration=\(Wearables.shared.registrationState)")
        }
        // Step 2 (2026-10-10 22:20): pair + powerOn/unfold/don OFF the main actor (step 1 on main: run 38112910442, still
        // disconnected/undefined), then listen for link/compat changes instead of only polling.
        step("MDK pair metaRayBanDisplay (detached)")
        let g = try await Task.detached { () throws -> any MockGlasses in
            let g = try kit.pairGlasses(model: .metaRayBanDisplay)
            g.powerOn(); g.unfold(); g.don()
            return g
        }.value
        glasses = g; deviceId = g.deviceIdentifier

        let ready = await waitReadyListening(g.deviceIdentifier, timeout: .seconds(5), step: step)
        if !ready { step("WARN link not connected yet (\(linkInfo(g.deviceIdentifier))); continuing to session start") }

        g.services.speech.setTranscriptionSource(.injected)   // never the live phone mic in tests
        if let feed = Bundle.main.url(forResource: "mock_feed_hevc", withExtension: "mp4") { g.services.camera.setCameraFeed(fileURL: feed) }
        else { step("WARN mock_feed_hevc.mp4 missing from bundle") }
        if let jpg = Bundle.main.url(forResource: "mock_photo_meal", withExtension: "jpg") { g.services.camera.setCapturedImage(fileURL: jpg) }
        // Test server for XCUITest MockDeviceTestClient / Chrome preview. Non-fatal (like Android).
        do { let port = try await kit.startTestServer(port: 9000); step("MDK test server :\(port)") }
        catch { step("WARN test server: \(error)") }
        // Like Meta's CameraAccess sample (whose mock-pair UI test passes on CI): AutoDeviceSelector + activeDeviceStream(),
        // instead of SpecificDeviceSelector gated on linkState (which never leaves .disconnected here; runs 38112910442…38117301155).
        let auto = AutoDeviceSelector(wearables: Wearables.shared)
        let active = await Self.firstActiveDevice(auto, timeout: .seconds(10))
        step("MDK auto selector active=\(active.map { "\($0)" } ?? "nil") (paired \(g.deviceIdentifier))")
        return auto
    }

    private static func firstActiveDevice(_ sel: AutoDeviceSelector, timeout: Duration) async -> DeviceIdentifier? {
        await withTaskGroup(of: DeviceIdentifier?.self) { group in
            group.addTask { for await id in sel.activeDeviceStream() { if let id { return id } }; return nil }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - XCUITest mode (`--ui-testing`), mirrors Meta's CameraAccess sample + CameraAccessUITests

    static let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    /// Called from DatBoot right after Wearables.configure(), before any other Wearables.shared use (as CameraAccessApp.init).
    /// Instantiate the MockDeviceKit singleton before `Wearables.configure()` (CameraAccessApp does this implicitly).
    static func touchKitBeforeConfigure() {
        NSLog("GlanceDiag: MockDeviceKit.shared touched before configure (isEnabled=%@)", "\(MockDeviceKit.shared.isEnabled)")
    }

    static func bootForUITesting() {
        let kit = MockDeviceKit.shared
        if !kit.isEnabled { kit.enable(config: MockDeviceKitConfig(initiallyRegistered: false, initialPermissionsGranted: true)) }
        let portFile = ProcessInfo.processInfo.environment["MWDAT_TEST_SERVER_PORT_FILE"]
        Task {
            do { let port = try await kit.startTestServer(portFilePath: portFile); NSLog("GlanceDiag: MDK test server :%d portFile=%@", Int(port), portFile ?? "-") }
            catch { NSLog("GlanceDiag: WARN test server: %@", "\(error)") }
        }
        NSLog("GlanceDiag: MDK enabled for UI testing (unregistered)")
    }

    /// Start (mock) in UI-testing mode: register through the SDK (MDK fake handler), then wait for the device that the
    /// TEST process pairs via MockDeviceTestClient.pairDevice() to become active on an AutoDeviceSelector.
    @MainActor
    func startForUITesting(timeout: Duration = .seconds(90), step: (String) -> Void) async throws -> any DeviceSelector {
        let kit = MockDeviceKit.shared
        if Wearables.shared.registrationState != .registered {
            step("MDK startRegistration (state=\(Wearables.shared.registrationState))")
            do { try await Wearables.shared.startRegistration() } catch { step("WARN startRegistration: \(error)") }
            let clock = ContinuousClock(); let deadline = clock.now.advanced(by: .seconds(15))
            while Wearables.shared.registrationState != .registered, clock.now < deadline { try? await clock.sleep(for: .milliseconds(100)) }
        }
        let auto = AutoDeviceSelector(wearables: Wearables.shared)
        step("Waiting for test-paired glasses")   // UI test pairs when it sees this exact status
        guard let id = await Self.firstActiveDevice(auto, timeout: timeout) else {
            let devs = Wearables.shared.devices.map { id in Wearables.shared.deviceForIdentifier(id).map { "\(id)=\($0.linkState)/\($0.compatibility())" } ?? "\(id)=?" }
            throw MockRigError.notReady(link: "no active device; registration=\(Wearables.shared.registrationState) devices=\(devs) paired=\(kit.pairedDevices.count)", compat: "-")
        }
        deviceId = id
        step("MDK active device \(id)")
        if let g = kit.pairedDevices.compactMap({ $0 as? any MockGlasses }).first(where: { $0.deviceIdentifier == id }) {
            glasses = g
            g.services.speech.setTranscriptionSource(.injected)
            if let feed = Bundle.main.url(forResource: "mock_feed_hevc", withExtension: "mp4") { g.services.camera.setCameraFeed(fileURL: feed) }
            if let jpg = Bundle.main.url(forResource: "mock_photo_meal", withExtension: "jpg") { g.services.camera.setCapturedImage(fileURL: jpg) }
        } else { step("WARN active device is not an in-process MockGlasses (feeds not set)") }
        return auto
    }

    /// Waits for the Device object to appear (devicesStream lag ≈ 60–250 ms in CI), attaches link-state + compatibility
    /// listeners (logged as GlanceDiag), and returns once connected+compatible or on timeout.
    @MainActor
    private func waitReadyListening(_ id: DeviceIdentifier, timeout: Duration, step: (String) -> Void) async -> Bool {
        step("MDK wait connected id=\(id) reg=\(String(describing: Wearables.shared.registrationState)) devices=\(Wearables.shared.devices) streamed=\(DatBoot.deviceIds)")
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: timeout)
        var device: Device?
        while clock.now < deadline, device == nil {
            device = Wearables.shared.deviceForIdentifier(id)
            if device == nil { try? await clock.sleep(for: .milliseconds(50)) }
        }
        guard let device else { step("MDK no Device object for \(id) after \(timeout)"); return false }
        step("MDK device visible: link=\(device.linkState) compat=\(device.compatibility())")
        let (events, cont) = AsyncStream<Void>.makeStream()
        listenTokens.append(device.addLinkStateListener { st in NSLog("GlanceDiag: MDK linkState → %@", "\(st)"); cont.yield() })
        listenTokens.append(device.addCompatibilityListener { c in NSLog("GlanceDiag: MDK compatibility → %@", "\(c)"); cont.yield() })
        let timer = Task { try? await clock.sleep(until: deadline); cont.finish() }
        defer { timer.cancel() }
        if device.linkState == .connected, device.compatibility() == .compatible { return true }
        for await _ in events {
            if device.linkState == .connected, device.compatibility() == .compatible { cont.finish(); return true }
        }
        step("MDK not ready after \(timeout): link=\(device.linkState) compat=\(device.compatibility()) streamed=\(DatBoot.deviceIds)")
        return false
    }
    private var listenTokens: [any AnyListenerToken] = []

    @MainActor
    private func linkInfo(_ id: DeviceIdentifier) -> String {
        guard let d = Wearables.shared.deviceForIdentifier(id) else { return "no device; devices=\(Wearables.shared.devices)" }
        return "link=\(d.linkState) compat=\(d.compatibility())"
    }

    /// DEBUG diagnostic: `simctl launch … --mock-probe` tries several bring-up variants one after another and logs
    /// "PROBE variant=… connected=… after=…ms link=… compat=…". Run by CI after the UI tests (not counted as tests).
    static func probe() async {
        enum V: String, CaseIterable { case mainUnfold, detachedListener, rayBanMeta, enableNoArg }
        let kit = MockDeviceKit.shared
        for v in V.allCases {
            if v == .enableNoArg { kit.enable() } else { kit.enable(config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true)) }
            let model: GlassesModel = v == .rayBanMeta ? .rayBanMeta : .metaRayBanDisplay
            var token: (any AnyListenerToken)?
            let g: (any MockGlasses)?
            if v == .detachedListener {
                g = await Task.detached { () -> (any MockGlasses)? in
                    guard let g = try? kit.pairGlasses(model: model) else { return nil }
                    g.powerOn(); g.unfold(); g.don(); return g
                }.value
                if let g, let d = Wearables.shared.deviceForIdentifier(g.deviceIdentifier) {
                    token = d.addLinkStateListener { st in NSLog("PROBE \(v.rawValue) linkListener=\(st)") }
                }
            } else {
                g = try? kit.pairGlasses(model: model)
                g?.powerOn(); g?.unfold(); g?.don()
            }
            guard let g else { NSLog("PROBE variant=\(v.rawValue) pair FAILED"); await kit.disable(); continue }
            let clock = ContinuousClock(); let t0 = clock.now; var connected = false
            while clock.now - t0 < .seconds(8) {
                if let d = Wearables.shared.deviceForIdentifier(g.deviceIdentifier), d.linkState == .connected { connected = true; break }
                try? await clock.sleep(for: .milliseconds(100))
            }
            let d = Wearables.shared.deviceForIdentifier(g.deviceIdentifier)
            let elapsed = clock.now - t0
            let line = "PROBE variant=\(v.rawValue) model=\(model) connected=\(connected) after=\(elapsed) link=\(d.map { "\($0.linkState)" } ?? "nil") compat=\(d.map { "\($0.compatibility())" } ?? "nil") devices=\(Wearables.shared.devices.count)"
            NSLog("%@", line); print(line)
            _ = token
            await kit.unpairDevice(g); await kit.disable()
            try? await Task.sleep(for: .milliseconds(500))
        }
        print("PROBE done"); NSLog("PROBE done")
    }

    func say(_ text: String) {
        guard let s = glasses?.services.speech else { return }
        let words = text.split(separator: " ")
        if words.count > 1 { for i in 1..<words.count { s.simulateTranscription(text: words.prefix(i).joined(separator: " "), isFinal: false, confidence: 0.9) } }
        s.simulateTranscription(text: text, isFinal: true, confidence: 0.95)
    }

    func stop() async { await MockDeviceKit.shared.disable() }
}
#endif
