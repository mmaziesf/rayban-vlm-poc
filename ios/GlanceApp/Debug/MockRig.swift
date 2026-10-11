// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
// Compiled only in Debug (project.yml excludes Debug/ from Release via a DEBUG #if).
#if DEBUG
import Foundation
import MWDATCore
import MWDATMockDevice

/// Mirrors Android debug MockRig: enable MDK, pair a Ray-Ban Display, power/unfold/don, feed the same H.265 clip.
final class MockRig: @unchecked Sendable {
    private var glasses: (any MockGlasses)?

    func startAndAwait(timeout: TimeInterval = 15) async throws -> any DeviceSelector {
        MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true))
        let g = try MockDeviceKit.shared.pairGlasses(model: .metaRayBanDisplay)
        g.powerOn(); g.unfold(); g.don()
        if let feed = Bundle.main.url(forResource: "mock_feed_hevc", withExtension: "mp4") { g.services.camera.setCameraFeed(fileURL: feed) }
        if let jpg = Bundle.main.url(forResource: "mock_photo_meal", withExtension: "jpg") { g.services.camera.setCapturedImage(fileURL: jpg) }
        glasses = g
        // Test server for XCUITest MockDeviceTestClient; non-fatal like Android.
        _ = try? await MockDeviceKit.shared.startTestServer(port: 9000)
        // TODO(verify on macOS): wait for link CONNECTED like Android (devicesStream / addLinkStateListener).
        try await Task.sleep(nanoseconds: 500_000_000)
        _ = timeout
        return AutoDeviceSelector(wearables: Wearables.shared)
    }

    func say(_ text: String) {
        guard let s = glasses?.services.speech else { return }
        let words = text.split(separator: " ")
        for i in 1..<max(words.count, 1) { s.simulateTranscription(text: words.prefix(i).joined(separator: " "), isFinal: false, confidence: 0.9) }
        s.simulateTranscription(text: text, isFinal: true, confidence: 0.95)
    }

    func stop() async { await MockDeviceKit.shared.disable() }
}
#endif
