// Mirrors phone/app/src/androidTest/.../MockLoopTest.kt (4 cases). Drives the app's in-process MockDeviceKit
// (DEBUG MockRig) through MockDeviceTestClient → the app's test server on :9000.
import XCTest
import MWDATMockDeviceTestClient

final class MockLoopUITests: XCTestCase {
    let app = XCUIApplication()
    let timeoutScale = Double(ProcessInfo.processInfo.environment["TIMEOUT_SCALE"] ?? "2") ?? 2

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        app.buttons["startMock"].tap()
        let status = app.staticTexts["status"]
        let ok = NSPredicate(format: "label == %@", "Mock glasses connected")
        let r = XCTWaiter.wait(for: [expectation(for: ok, evaluatedWith: status)], timeout: 30 * timeoutScale)
        if r != .completed {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
        }
        XCTAssertEqual(r, .completed,
            "status was: '\(status.exists ? status.label : "<missing>")' appState=\(app.state.rawValue) " +
            "hud='\(app.staticTexts["hudLabel"].exists ? app.staticTexts["hudLabel"].label : "<missing>")' " +
            "text='\(app.staticTexts["hudText"].exists ? app.staticTexts["hudText"].label : "<missing>")'")
    }

    private func waitLabel(_ label: String, _ t: Double = 20) {
        let el = app.staticTexts["hudLabel"]
        let r = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: el)], timeout: t * timeoutScale)
        XCTAssertEqual(r, .completed, "HUD never reached \(label); was '\(el.exists ? el.label : "<missing>")' text='\(app.staticTexts["hudText"].label)'")
    }

    /// The device the app paired in-process (MockRig) — don't pair a second one from the test.
    private var deviceId: String { app.staticTexts["mockDeviceId"].label }

    func testDisplayIdleShowsLiveBuffer() {
        waitLabel("Ready")
        XCTAssertTrue(app.staticTexts["hudMeta"].label.hasPrefix("Live"), "meta='\(app.staticTexts["hudMeta"].label)'")
    }

    func testSpeechDescribeUsesBufferedFrame() async throws {
        let id = await MainActor.run { deviceId }
        let ok = await MockDeviceTestClient(port: 9000).simulateTranscription(deviceId: id, text: "what am I seeing", isFinal: true, confidence: 0.95)
        XCTAssertTrue(ok, "test client simulateTranscription failed (id=\(id))")
        await MainActor.run { waitLabel("Answer") }
    }

    func testSpeechLogMealLogs() async throws {
        let id = await MainActor.run { deviceId }
        let ok = await MockDeviceTestClient(port: 9000).simulateTranscription(deviceId: id, text: "log this meal", isFinal: true, confidence: 0.95)
        XCTAssertTrue(ok, "test client simulateTranscription failed (id=\(id))")
        await MainActor.run { waitLabel("Logged") }
    }

    func testCommandPathWithoutSpeech() {
        app.buttons["cmdDescribe"].tap()
        waitLabel("Answer")
    }
}
