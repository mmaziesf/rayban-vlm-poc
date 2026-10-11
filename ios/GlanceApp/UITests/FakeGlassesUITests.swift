// CI fallback tests: real GlanceController / IntentRouter / FrameRingBuffer / HUD state machine, driven through the UI,
// with frames from FakeRig instead of a DAT session (launch arg --fake-glasses). They do NOT exercise the DAT link;
// MockLoopUITests remains the DAT-level suite. See docs/IOS_OPTIONS.md.
import XCTest

final class FakeGlassesUITests: XCTestCase {
    let app = XCUIApplication()
    let timeoutScale = Double(ProcessInfo.processInfo.environment["TIMEOUT_SCALE"] ?? "2") ?? 2

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--fake-glasses"]
        app.launch()
        app.buttons["startMock"].tap()
        let status = app.staticTexts["status"]
        let r = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", "Fake glasses connected"), evaluatedWith: status)],
                               timeout: 20 * timeoutScale)
        XCTAssertEqual(r, .completed, "status was: '\(status.exists ? status.label : "<missing>")'")
    }

    private func waitLabel(_ label: String, _ t: Double = 20) {
        let el = app.staticTexts["hudLabel"]
        let r = XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: el)], timeout: t * timeoutScale)
        XCTAssertEqual(r, .completed, "HUD never reached \(label); was '\(el.exists ? el.label : "<missing>")' text='\(app.staticTexts["hudText"].label)'")
    }

    func testIdleShowsLiveBuffer() {
        waitLabel("Ready")
        XCTAssertTrue(app.staticTexts["hudMeta"].label.hasPrefix("Live"), "meta='\(app.staticTexts["hudMeta"].label)'")
    }

    func testCommandDescribeAnswers() {
        waitLabel("Ready")
        app.buttons["cmdDescribe"].tap()
        waitLabel("Answer")
        XCTAssertTrue(app.staticTexts["hudText"].label.contains("plate"), "answer='\(app.staticTexts["hudText"].label)'")
    }

    func testSpokenDescribeAnswers() {
        waitLabel("Ready")
        app.buttons["sayDescribe"].tap()
        waitLabel("Answer")
    }

    func testSpokenLogMealLogs() {
        waitLabel("Ready")
        app.buttons["sayLog"].tap()
        waitLabel("Logged")
    }
}
