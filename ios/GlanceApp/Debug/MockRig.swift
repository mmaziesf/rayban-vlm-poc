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
        if !kit.isEnabled { kit.enable(config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true)) }
        step("MDK pair metaRayBanDisplay")
        let g = try kit.pairGlasses(model: .metaRayBanDisplay)
        // Order from Meta's DisplayAccess sample + CameraAccessTests: powerOn → don (no unfold).
        g.powerOn(); g.don()
        glasses = g; deviceId = g.deviceIdentifier

        // Soft readiness wait (run 38110641886: link stayed .disconnected/compat .undefined for 15 s while unsessioned).
        // CameraAccessTests just sleeps 1 s and starts a session, so the session reaching .started is the real gate.
        let ready = await waitReady(g.deviceIdentifier, timeout: .seconds(5), step: step)
        if !ready { step("WARN link not connected yet (\(linkInfo(g.deviceIdentifier))); continuing to session start") }

        g.services.speech.setTranscriptionSource(.injected)   // never the live phone mic in tests
        if let feed = Bundle.main.url(forResource: "mock_feed_hevc", withExtension: "mp4") { g.services.camera.setCameraFeed(fileURL: feed) }
        else { step("WARN mock_feed_hevc.mp4 missing from bundle") }
        if let jpg = Bundle.main.url(forResource: "mock_photo_meal", withExtension: "jpg") { g.services.camera.setCapturedImage(fileURL: jpg) }
        // Test server for XCUITest MockDeviceTestClient / Chrome preview. Non-fatal (like Android).
        do { let port = try await kit.startTestServer(port: 9000); step("MDK test server :\(port)") }
        catch { step("WARN test server: \(error)") }
        return SpecificDeviceSelector(device: g.deviceIdentifier)
    }

    @MainActor
    private func waitReady(_ id: DeviceIdentifier, timeout: Duration, step: (String) -> Void) async -> Bool {
        step("MDK wait connected id=\(id) reg=\(String(describing: Wearables.shared.registrationState)) devices=\(Wearables.shared.devices)")
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let d = Wearables.shared.deviceForIdentifier(id), d.linkState == .connected, d.compatibility() == .compatible { return true }
            try? await clock.sleep(for: .milliseconds(100))
        }
        return false
    }

    @MainActor
    private func linkInfo(_ id: DeviceIdentifier) -> String {
        guard let d = Wearables.shared.deviceForIdentifier(id) else { return "no device; devices=\(Wearables.shared.devices)" }
        return "link=\(d.linkState) compat=\(d.compatibility())"
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
