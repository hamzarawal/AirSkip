import XCTest
@testable import MenuBarApp

final class PairedDeviceTests: XCTestCase {
    private func device(_ id: String, _ name: String = "AirPods Pro", connected: Bool = false) -> PairedDevice {
        PairedDevice(id: id, name: name, isConnected: connected)
    }

    func testConnectedPairWinsOverRememberedDisconnectedPair() {
        let old = device("old")
        let connected = device("new", connected: true)
        XCTAssertEqual(PairedDevice.preferred(in: [old, connected], rememberedID: old.id), connected)
    }

    func testAmbiguousConnectedPairsRequireSelection() {
        let first = device("a", connected: true)
        let second = device("b", connected: true)
        XCTAssertNil(PairedDevice.preferred(in: [first, second], rememberedID: nil))
        XCTAssertEqual(PairedDevice.preferred(in: [first, second], rememberedID: second.id), second)
    }

    func testRememberedRenamedPairRemainsRecognizable() {
        let renamed = device("a", "My headphones", connected: true)
        let mouse = device("b", "Magic Mouse", connected: true)
        XCTAssertEqual(PairedDevice.preferred(in: [mouse, renamed], rememberedID: renamed.id), renamed)
        XCTAssertNil(PairedDevice.preferred(in: [mouse, renamed], rememberedID: nil))
    }

    func testSinglePairedAirPodsWorksWithDisconnectedEarbuds() {
        let pair = device("a")
        XCTAssertEqual(PairedDevice.preferred(in: [pair], rememberedID: nil), pair)
        XCTAssertNil(PairedDevice.preferred(in: [pair, device("b")], rememberedID: nil))
    }
}
