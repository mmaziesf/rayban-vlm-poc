// Mirrors phone/app/src/androidTest/.../MockLoopTest.kt (4 cases) and follows Meta's CameraAccessUITests pattern:
// the app enables MockDeviceKit + its test server at launch (`--ui-testing`), and THIS process pairs the mock
// glasses through MockDeviceTestClient (port file), then drives speech through the same client.
import XCTest
import MWDATCore            // DeviceType (already a dependency of MWDATMockDeviceTestClient)
import MWDATMockDeviceTestClient

@MainActor
final class MockLoopUITests: XCTestCase {
    private let portFilePath = NSTemporaryDirectory() + "mwdat_test_server_port_\(UUID().uuidString).txt"
    private let app = XCUIApplication()
    private var client: MockDeviceTestClient!
    private var deviceId: String!
    private static var didAllowLocalNetwork = false
    let timeoutScale = Double(ProcessInfo.processInfo.environment["TIMEOUT_SCALE"] ?? "2") ?? 2

    override func setUp() async throws {
        continueAfterFailure = false
        addTeardownBlock { [portFilePath] in try? FileManager.default.removeItem(atPath: portFilePath) }
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MWDAT_TEST_SERVER_PORT_FILE"] = portFilePath
        app.launch()

        client = MockDeviceTestClient(portFilePath: portFilePath)
        let reachable = await client.waitForServer(timeout: 15)
        XCTAssertTrue(reachable, "app's MockDeviceKit test server not reachable (port file \(portFilePath))")

        app.buttons["startMock"].tap()
        waitStatus("Waiting for test-paired glasses", 30)          // app registered via MDK's fake handler

        deviceId = await client.pairDevice(deviceType: .metaRayBanDisplay)
        XCTAssertNotNil(deviceId, "MockDeviceTestClient.pairDevice returned nil")
        allowLocalNetworkPermissionIfNeeded()
        waitStatus("Mock glasses connected", 45)
    }

    override func tearDown() async throws {
        if let id = deviceId, let c = client { _ = await c.unpairDevice(deviceId: id) }
        app.terminate()
    }

    private func waitStatus(_ text: String, _ t: Double) {
        let status = app.staticTexts["status"]
        let r = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: status)], timeout: t * timeoutScale)
        if r != .completed { let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot) }
        XCTAssertEqual(r, .completed,
            "waiting for '\(text)'; status was: '\(status.exists ? status.label : "<missing>")' appState=\(app.state.rawValue) " +
            "hud='\(app.staticTexts["hudLabel"].exists ? app.staticTexts["hudLabel"].label : "<missing>")' " +
            "text='\(app.staticTexts["hudText"].exists ? app.staticTexts["hudText"].label : "<missing>")'")
    }

    /// Streaming runs over the "Wi-Fi" link level, so iOS may show the Local Network dialog once per install (SpringBoard).
    private func allowLocalNetworkPermissionIfNeeded() {
        guard !Self.didAllowLocalNetwork else { return }
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap(); Self.didAllowLocalNetwork = true }
    }

    private func waitLabel(_ label: String, _ t: Double = 20) {
        let el = app.staticTexts["hudLabel"]
        let r = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: el)], timeout: t * timeoutScale)
        XCTAssertEqual(r, .completed, "HUD never reached \(label); was '\(el.exists ? el.label : "<missing>")' text='\(app.staticTexts["hudText"].label)'")
    }

    func testDisplayIdleShowsLiveBuffer() {
        waitLabel("Ready")
        XCTAssertTrue(app.staticTexts["hudMeta"].label.hasPrefix("Live"), "meta='\(app.staticTexts["hudMeta"].label)'")
    }

    func testSpeechDescribeUsesBufferedFrame() async throws {
        let ok = await client.simulateTranscription(deviceId: deviceId, text: "what am I seeing", isFinal: true, confidence: 0.95)
        XCTAssertTrue(ok, "simulateTranscription failed (id=\(deviceId ?? "nil"))")
        waitLabel("Answer")
    }

    func testSpeechLogMealLogs() async throws {
        let ok = await client.simulateTranscription(deviceId: deviceId, text: "log this meal", isFinal: true, confidence: 0.95)
        XCTAssertTrue(ok, "simulateTranscription failed (id=\(deviceId ?? "nil"))")
        waitLabel("Logged")
    }

    func testCommandPathWithoutSpeech() {
        app.buttons["cmdDescribe"].tap()
        waitLabel("Answer")
    }
}
