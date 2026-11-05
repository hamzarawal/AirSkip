import XCTest
@testable import MenuBarApp

final class LidMatchPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let source = UUID()
    private let pair = PairedDevice(id: "test-pair", name: "AirPods Pro", isConnected: false)

    override func setUp() {
        suite = "AirSkipTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(pair.id, forKey: "pairedAddress")
        saveMatch()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func saveMatch() {
        defaults.set(["address": pair.id, "source": source.uuidString], forKey: "verifiedLidMatch")
    }

    func testDelayedDeviceDiscoveryRestoresMatchWithoutReusingOldSignal() {
        var devices: [PairedDevice] = []
        let model = AppModel(defaults: defaults, deviceProvider: { devices })
        model.refreshPairedDevices()
        XCTAssertFalse(model.verified)

        devices = [pair]
        model.refreshPairedDevices()
        XCTAssertTrue(model.verified)
        XCTAssertEqual(model.selectedCaseID, source)
        XCTAssertFalse(model.signalFresh)
        XCTAssertFalse(model.enabled)
    }

    func testAutomaticKeyRecoveryBeforeDiscoveryKeepsPersistedMatch() {
        var devices: [PairedDevice] = []
        let model = AppModel(defaults: defaults, deviceProvider: { devices })
        model.acceptKey(Data(repeating: 0, count: 16), name: pair.name, preserveVerification: true)
        XCTAssertNotNil(defaults.dictionary(forKey: "verifiedLidMatch"))

        devices = [pair]
        model.refreshPairedDevices()
        XCTAssertTrue(model.verified)
        XCTAssertEqual(model.selectedCaseID, source)
    }

    func testAutomaticKeyRecoveryKeepsRestoredMatchAcrossAnotherLaunch() {
        let model = AppModel(defaults: defaults, deviceProvider: { [self.pair] })
        model.refreshPairedDevices()
        model.acceptKey(Data(repeating: 0, count: 16), name: pair.name, preserveVerification: true)
        let relaunched = AppModel(defaults: defaults, deviceProvider: { [self.pair] })
        relaunched.refreshPairedDevices()
        XCTAssertTrue(relaunched.verified)
        XCTAssertEqual(relaunched.selectedCaseID, source)
    }

    func testDifferentPairDoesNotInheritSavedMatch() {
        let other = PairedDevice(id: "other-pair", name: "AirPods", isConnected: true)
        let model = AppModel(defaults: defaults, deviceProvider: { [other] })
        model.refreshPairedDevices()
        XCTAssertFalse(model.verified)
        XCTAssertNil(model.selectedCaseID)
    }

    func testManualKeyReplacementStillRequiresMatching() {
        let model = AppModel(defaults: defaults, deviceProvider: { [self.pair] })
        model.refreshPairedDevices()
        model.acceptKey(Data(repeating: 0, count: 16), name: pair.name)
        XCTAssertFalse(model.verified)
        XCTAssertNil(defaults.dictionary(forKey: "verifiedLidMatch"))
    }
}
