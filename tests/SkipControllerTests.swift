import XCTest
@testable import MenuBarApp

final class SkipControllerTests: XCTestCase {
    private let source = UUID()
    private var open: CaseAdvertisement { .init(isOpen: true, openCounter: 1, batteryPercent: 70, earbudsInCase: 0) }
    private var closed: CaseAdvertisement { .init(isOpen: false, openCounter: 1, batteryPercent: 70, earbudsInCase: 0) }

    private func verifiedController() -> SkipController {
        var controller = SkipController()
        controller.observe(closed, at: 0, source: source)
        controller.observe(open, at: 0.1, source: source)
        XCTAssertTrue(controller.verify())
        return controller
    }

    func testRequiresBothLidStatesAndExplicitVerification() {
        var c = SkipController()
        c.observe(open, at: 0, source: source)
        XCTAssertFalse(c.verify())
        XCTAssertFalse(c.shouldPress(at: 0, enabled: true, targetReady: true))
        c.observe(closed, at: 0.1, source: source)
        c.observe(open, at: 0.2, source: source)
        XCTAssertFalse(c.shouldPress(at: 0.2, enabled: true, targetReady: true))
        XCTAssertTrue(c.verify())
        XCTAssertTrue(c.shouldPress(at: 0.2, enabled: true, targetReady: true))
    }

    func testRestoredVerificationStillRequiresFreshSignalFromSavedCase() {
        var c = SkipController()
        c.restoreVerification(for: source)
        XCTAssertTrue(c.verified)
        XCTAssertEqual(c.source, source)
        XCTAssertFalse(c.shouldPress(at: 0, enabled: true, targetReady: true))
        XCTAssertFalse(c.observe(open, at: 0.1, source: UUID()))
        XCTAssertFalse(c.shouldPress(at: 0.1, enabled: true, targetReady: true))
        XCTAssertTrue(c.observe(open, at: 0.2, source: source))
        XCTAssertTrue(c.shouldPress(at: 0.2, enabled: true, targetReady: true))
    }

    func testImmediatePressAndConfiguredRepeatWithoutCatchUpBurst() {
        var c = verifiedController()
        c.interval = 0.5
        XCTAssertTrue(c.shouldPress(at: 0.1, enabled: true, targetReady: true))
        XCTAssertFalse(c.shouldPress(at: 0.59, enabled: true, targetReady: true))
        XCTAssertTrue(c.shouldPress(at: 0.6, enabled: true, targetReady: true))
        c.observe(open, at: 2, source: source)
        XCTAssertTrue(c.shouldPress(at: 2, enabled: true, targetReady: true))
        XCTAssertFalse(c.shouldPress(at: 2, enabled: true, targetReady: true))
    }

    func testCloseDisableFocusLossAndStaleSignalStopPresses() {
        var c = verifiedController()
        XCTAssertFalse(c.shouldPress(at: 0.1, enabled: false, targetReady: true))
        XCTAssertFalse(c.shouldPress(at: 0.1, enabled: true, targetReady: false))
        XCTAssertTrue(c.shouldPress(at: 0.1, enabled: true, targetReady: true))
        c.observe(closed, at: 0.2, source: source)
        XCTAssertFalse(c.shouldPress(at: 1, enabled: true, targetReady: true))
        c.observe(open, at: 1, source: source)
        XCTAssertTrue(c.shouldPress(at: 1, enabled: true, targetReady: true))
        XCTAssertFalse(c.shouldPress(at: 4, enabled: true, targetReady: true))
        XCTAssertFalse(c.shouldPress(at: 0.5, enabled: true, targetReady: true))
    }

    func testNewSignalRequiredAfterDisableOrSleep() {
        var c = verifiedController()
        c.clearSignal()
        XCTAssertTrue(c.verified)
        XCTAssertFalse(c.shouldPress(at: 0.2, enabled: true, targetReady: true))
        c.observe(open, at: 0.3, source: source)
        XCTAssertTrue(c.shouldPress(at: 0.3, enabled: true, targetReady: true))
        c.reset()
        XCTAssertFalse(c.verified)
        XCTAssertFalse(c.hasSeenOpen)
        XCTAssertFalse(c.hasSeenClosed)
    }

    func testRepeatDelayChangeAndInvalidValues() {
        var c = verifiedController()
        c.interval = .nan
        XCTAssertTrue(c.shouldPress(at: 0.1, enabled: true, targetReady: true))
        XCTAssertFalse(c.shouldPress(at: 0.3, enabled: true, targetReady: true))
        c.interval = 0.15
        XCTAssertTrue(c.shouldPress(at: 0.3, enabled: true, targetReady: true))
    }

    func testDifferentCasesCannotCombineVerificationOrRefreshStaleSignal() {
        var c = SkipController()
        let other = UUID()
        XCTAssertTrue(c.observe(open, at: 0, source: source))
        XCTAssertFalse(c.observe(closed, at: 0.1, source: other))
        XCTAssertFalse(c.verify())
        c.observe(closed, at: 0.2, source: source)
        XCTAssertTrue(c.verify())
        c.observe(open, at: 1, source: source)
        XCTAssertFalse(c.observe(open, at: 4, source: other))
        XCTAssertFalse(c.shouldPress(at: 4, enabled: true, targetReady: true))
        c.clearSignal()
        XCTAssertFalse(c.observe(open, at: 5, source: other))
        XCTAssertEqual(c.source, source)
    }

    func testSelectingAnotherCaseRequiresFreshPhysicalVerification() {
        var c = verifiedController()
        c.interval = 0.8
        let other = UUID()
        c.selectSource(other)
        XCTAssertNil(c.latest)
        XCTAssertFalse(c.verified)
        XCTAssertFalse(c.hasSeenOpen)
        XCTAssertFalse(c.hasSeenClosed)
        XCTAssertEqual(c.interval, 0.8)
        XCTAssertFalse(c.observe(closed, at: 1, source: source))
        c.observe(open, at: 1, source: other)
        XCTAssertFalse(c.verify())
        c.observe(closed, at: 2, source: other)
        XCTAssertTrue(c.verify())
        c.selectSource(nil)
        XCTAssertNil(c.source)
        XCTAssertFalse(c.verified)
        XCTAssertTrue(c.observe(open, at: 3, source: source))
    }
}
