// Same steps as Meta's CameraAccessUITests: launch --ui-testing with a port file, register, pairDevice() (default
// Ray-Ban Meta) from THIS process, then expect an active device and a started session.
import XCTest
import MWDATMockDeviceTestClient

@MainActor
final class ProbeUITests: XCTestCase {
    private let portFilePath = NSTemporaryDirectory() + "mwdat_test_server_port_\(UUID().uuidString).txt"
    private let app = XCUIApplication()
    private var client: MockDeviceTestClient!
    private var deviceId: String?

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MWDAT_TEST_SERVER_PORT_FILE"] = portFilePath
        app.launch()
        client = MockDeviceTestClient(portFilePath: portFilePath)
        let ok = await client.waitForServer(timeout: 15)
        XCTAssertTrue(ok, "test server not reachable")
    }

    override func tearDown() async throws {
        if let id = deviceId { _ = await client.unpairDevice(deviceId: id) }
        app.terminate()
    }

    private func waitLabel(_ id: String, _ pred: String, _ t: TimeInterval) -> Bool {
        let el = app.staticTexts[id]
        return XCTWaiter.wait(for: [expectation(for: NSPredicate(format: pred), evaluatedWith: el)], timeout: t) == .completed
    }
    private var state: String {
        ["reg", "active", "link", "session"].map { "\($0)=\(app.staticTexts[$0].exists ? app.staticTexts[$0].label : "<missing>")" }.joined(separator: " ")
    }

    func testPairBecomesActiveAndSessionStarts() async throws {
        app.buttons["register"].tap()
        let registered = waitLabel("reg", "label == 'registered'", 20)
        var st = state
        XCTAssertTrue(registered, "not registered: \(st)")
        deviceId = await client.pairDevice()
        XCTAssertNotNil(deviceId, "pairDevice nil")
        let active = waitLabel("active", "label != 'active=nil'", 30)
        st = state; print("PROBE_RESULT active=\(active) \(st)")
        XCTAssertTrue(active, "ACTIVE FAIL: \(st)")
        app.buttons["startSession"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let started = waitLabel("session", "label == 'started'", 30)
        st = state; print("PROBE_RESULT session=\(started) \(st)")
        XCTAssertTrue(started, "SESSION FAIL: \(st)")
    }
}
