// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
// Mirrors phone/app/src/androidTest/.../MockLoopTest.kt (4 cases). Requires the app's DEBUG MockRig test server (port 9000).
import XCTest
import MWDATMockDeviceTestClient

final class MockLoopUITests: XCTestCase {
    let app = XCUIApplication()
    let timeoutScale = Double(ProcessInfo.processInfo.environment["TIMEOUT_SCALE"] ?? "1") ?? 1

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        app.buttons["startMock"].tap()
        XCTAssertTrue(app.staticTexts["Mock glasses connected"].waitForExistence(timeout: 20 * timeoutScale))
    }

    private func waitLabel(_ label: String, _ t: Double = 15) {
        let el = app.staticTexts["hudLabel"]
        let p = NSPredicate(format: "label == %@", label)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: p, evaluatedWith: el)], timeout: t * timeoutScale), .completed, "HUD never reached \(label)")
    }

    func testDisplayIdleShowsLiveBuffer() {
        waitLabel("Ready")
        XCTAssertTrue(app.staticTexts["hudMeta"].label.hasPrefix("Live"))
    }

    func testSpeechDescribeUsesBufferedFrame() async throws {
        let client = MockDeviceTestClient(port: 9000)
        // NOTE: deviceId of the in-app paired mock; TODO(verify): expose via accessibility label if pairDevice is needed instead.
        let id = await client.pairDevice(deviceType: .metaRayBanDisplay) ?? ""
        _ = await client.simulateTranscription(deviceId: id, text: "what am I seeing", isFinal: true, confidence: 0.95)
        waitLabel("Answer")
    }

    func testSpeechLogMealLogs() async throws {
        let client = MockDeviceTestClient(port: 9000)
        let id = await client.pairDevice(deviceType: .metaRayBanDisplay) ?? ""
        _ = await client.simulateTranscription(deviceId: id, text: "log this meal", isFinal: true, confidence: 0.95)
        waitLabel("Logged")
    }

    func testCommandPathWithoutSpeech() {
        app.buttons["cmdDescribe"].tap()
        waitLabel("Answer")
    }
}
