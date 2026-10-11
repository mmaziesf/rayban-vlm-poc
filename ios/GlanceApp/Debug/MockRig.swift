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
        g.powerOn(); g.unfold(); g.don()
        g.services.speech.setTranscriptionSource(.injected)   // never the live phone mic in tests
        if let feed = Bundle.main.url(forResource: "mock_feed_hevc", withExtension: "mp4") { g.services.camera.setCameraFeed(fileURL: feed) }
        else { step("WARN mock_feed_hevc.mp4 missing from bundle") }
        if let jpg = Bundle.main.url(forResource: "mock_photo_meal", withExtension: "jpg") { g.services.camera.setCapturedImage(fileURL: jpg) }
        glasses = g; deviceId = g.deviceIdentifier

        step("MDK wait connected id=\(g.deviceIdentifier)")
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: timeout)
        while true {
            let d = Wearables.shared.deviceForIdentifier(g.deviceIdentifier)
            if let d, d.linkState == .connected, d.compatibility() == .compatible { break }
            if clock.now >= deadline {
                throw MockRigError.notReady(link: d.map { String(describing: $0.linkState) } ?? "no device",
                                            compat: d.map { String(describing: $0.compatibility()) } ?? "-")
            }
            try await clock.sleep(for: .milliseconds(100))
        }
        // Test server for XCUITest MockDeviceTestClient / Chrome preview. Non-fatal (like Android).
        do { let port = try await kit.startTestServer(port: 9000); step("MDK test server :\(port)") }
        catch { step("WARN test server: \(error)") }
        return SpecificDeviceSelector(device: g.deviceIdentifier)
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
