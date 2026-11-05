import XCTest
@testable import MenuBarApp

final class CaseAdvertisementTests: XCTestCase {
    private let key = Data((0..<16).map(UInt8.init))
    // Based on the published Pro 3 case capture, with a synthetic key/counter.
    private var closed: Data { Data([0x29, 0x20, 0x08, 0x3d, 0xde, 0xdd, 0x51, 0x0b, 0, 0, 0, 0, 0xf7, 0x82, 0x16, 0]) }

    private func packet(_ plaintext: Data) throws -> Data {
        var data = Data([0x4c, 0, 0x07, 0x11, 0x06])
        data.append(try XCTUnwrap(AESBlock.encrypt(plaintext, key: key)))
        return data
    }

    func testKnownAESVector() throws {
        let aesKey = try XCTUnwrap(AirPodsKey.parse("000102030405060708090a0b0c0d0e0f"))
        let input = try XCTUnwrap(AirPodsKey.parse("00112233445566778899aabbccddeeff"))
        let output = try XCTUnwrap(AirPodsKey.parse("69c4e0d86a7b0430d8cdb78070b4c55a"))
        XCTAssertEqual(AESBlock.encrypt(input, key: aesKey), output)
        XCTAssertEqual(AESBlock.decrypt(output, key: aesKey), input)
    }

    func testClosedWithBothBuds() throws {
        let result = try XCTUnwrap(CaseAdvertisement.decode(manufacturerData: packet(closed), key: key))
        XCTAssertFalse(result.isOpen)
        XCTAssertEqual(result.batteryPercent, 61)
        XCTAssertEqual(result.earbudsInCase, 2)
    }

    func testOpenEmptyCaseAndOneBud() throws {
        var open = closed
        open[2] = 0x01
        open[4] = 0xff
        open[5] = 0xff
        let result = try XCTUnwrap(CaseAdvertisement.decode(manufacturerData: packet(open), key: key))
        XCTAssertTrue(result.isOpen)
        XCTAssertEqual(result.openCounter, 1)
        XCTAssertEqual(result.earbudsInCase, 0)
        open[5] = 0x5a
        XCTAssertEqual(CaseAdvertisement.decode(manufacturerData: try packet(open), key: key)?.earbudsInCase, 1)
    }

    func testMacOSDecodedFirmware9A348NeedsNoKeyOrSecondDecryption() throws {
        // Observed layout and lid sequence from an empty Pro 3 case on 9A348.
        // The changing counter is synthetic; no key or device identifier is stored.
        var payload = Data([0x29, 0x20, 0x0c, 100, 0xff, 0xff, 0x5a, 0x86,
                            0, 0, 1, 0, 1, 2, 3, 4])
        for (lid, isOpen) in [(UInt8(0x0c), false), (0x05, true), (0x07, true), (0x0f, false), (0x09, false)] {
            payload[2] = lid
            let raw = Data([0x4c, 0, 0x07, 0x11, 0x06]) + payload
            let result = try XCTUnwrap(CaseAdvertisement.decode(manufacturerData: raw))
            XCTAssertEqual(result.isOpen, isOpen)
            XCTAssertEqual(result.batteryPercent, 100)
            XCTAssertEqual(result.earbudsInCase, 0)
            XCTAssertTrue(result.deliveredPlaintext)
            XCTAssertEqual(CaseAdvertisement.decode(manufacturerData: raw, key: key), result)
            XCTAssertEqual(CaseAdvertisement.decode(manufacturerData: raw, key: Data()), result)
        }
        let encrypted = try packet(payload)
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: encrypted))
        let result = try XCTUnwrap(CaseAdvertisement.decode(manufacturerData: encrypted, key: key))
        XCTAssertFalse(result.deliveredPlaintext)
        XCTAssertFalse(result.isOpen)
    }

    func testDifferentModelHeadersDecodePlaintextAndEncryptedLidStates() throws {
        // Synthetic headers exercise compatibility without claiming other models were tested.
        for header: UInt16 in [0x2920, 0x1420, 0x0000, 0xffff] {
            for isOpen in [false, true] {
                var payload = closed
                payload[0] = UInt8(header >> 8)
                payload[1] = UInt8(header & 0xff)
                payload[2] = isOpen ? 1 : 9
                let plaintext = Data([0x4c, 0, 0x07, 0x11, 0x06]) + payload
                let direct = try XCTUnwrap(CaseAdvertisement.decode(manufacturerData: plaintext))
                XCTAssertEqual(direct.isOpen, isOpen)
                XCTAssertTrue(direct.deliveredPlaintext)
                XCTAssertEqual(CaseAdvertisement.decode(manufacturerData: plaintext, key: key), direct)
                let decrypted = try XCTUnwrap(CaseAdvertisement.decode(manufacturerData: packet(payload), key: key))
                XCTAssertEqual(decrypted.isOpen, isOpen)
                XCTAssertEqual(decrypted.batteryPercent, direct.batteryPercent)
                XCTAssertEqual(decrypted.earbudsInCase, direct.earbudsInCase)
                XCTAssertFalse(decrypted.deliveredPlaintext)
            }
        }
    }

    func testPlaintextRejectsInvalidFieldsAcrossModelHeaders() {
        for model: UInt8 in [0x29, 0x14] {
            let payload = Data([model, 0x20, 1, 100, 0xff, 0xff, 0x5a, 0x86,
                                0, 0, 1, 0, 1, 2, 3, 4])
            for (index, value) in [(8, UInt8(1)), (10, 2), (11, 1), (3, 101), (4, 101), (5, 101)] {
                var changed = payload
                changed[index] = value
                let raw = Data([0x4c, 0, 0x07, 0x11, 0x06]) + changed
                XCTAssertNil(CaseAdvertisement.decode(manufacturerData: raw))
                XCTAssertNil(CaseAdvertisement.decode(manufacturerData: raw, key: key))
            }
        }
    }

    func testRegisteredLayoutCanUseDifferentMessageLengthAndFields() throws {
        let additional = CasePacketLayout(messageLength: 0x05) { data in
            let bytes = [UInt8](data)
            guard bytes.count == 4, bytes[0] == 0xa5, bytes[1] <= 1,
                  bytes[2] <= 100, bytes[3] <= 2 else { return nil }
            return CaseAdvertisement(isOpen: bytes[1] == 1, openCounter: 0,
                                     batteryPercent: Int(bytes[2]), earbudsInCase: Int(bytes[3]))
        }
        let layouts = CasePacketLayout.supported + [additional]
        let payload = Data([0xa5, 1, 65, 2])
        XCTAssertNil(CasePacketLayout.decode(payload, messageLength: 0x05))
        let decoded = try XCTUnwrap(CasePacketLayout.decode(payload, messageLength: 0x05, layouts: layouts))
        XCTAssertTrue(decoded.isOpen)
        XCTAssertEqual(decoded.batteryPercent, 65)
        XCTAssertEqual(decoded.earbudsInCase, 2)
        XCTAssertNil(CasePacketLayout.decode(payload, messageLength: 0x11, layouts: layouts))
        XCTAssertNil(CasePacketLayout.decode(Data([0xa5, 2, 65, 2]), messageLength: 0x05, layouts: layouts))
        XCTAssertNotNil(CasePacketLayout.decode(closed, messageLength: 0x11, layouts: layouts))
    }

    func testFirmwareVariantsAndCounterAreNotIdentityFields() {
        var data = closed
        data[6] = 0x5a
        data[7] = 0x86
        data[9] = 0xbe
        data[12] = 0xff
        data[14] = 0xa4
        XCTAssertNotNil(CaseAdvertisement.decodePlaintext(data))
    }

    func testRejectWrongKeyWrongAdvertiserAndEarbudFormat() throws {
        let good = try packet(closed)
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: good, key: Data(repeating: 0xff, count: 16)))
        var other = good
        other[0] = 0x01
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: other, key: key))
        var buds = Data([0x4c, 0, 0x07, 0x19, 0x01, 0x27, 0x20, 0x73, 0xaa, 0xaa, 0x39])
        buds.append(Data(repeating: 0, count: 18))
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: buds, key: key))
        var wrongLength = good
        wrongLength[3] = 0x19
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: wrongLength, key: key))
    }

    func testRejectTruncationAndImpossiblePlaintext() throws {
        let good = try packet(closed)
        for length in 0..<good.count {
            XCTAssertNil(CaseAdvertisement.decode(manufacturerData: good.prefix(length), key: key))
        }
        for index in [8, 11] {
            var data = closed
            data[index] ^= 0x01
            XCTAssertNil(CaseAdvertisement.decodePlaintext(data))
        }
        var data = closed
        data[3] = 0x7f
        XCTAssertNil(CaseAdvertisement.decodePlaintext(data))
        data[3] = 0xff
        XCTAssertNil(CaseAdvertisement.decodePlaintext(data))
    }

    func testKeyImportAcceptsKeychainFormatAndRejectsGarbage() {
        XCTAssertEqual(AirPodsKey.parse("00-01-02-03-04-05-06-07-08-09-0A-0B-0C-0D-0E-0F"), key)
        XCTAssertNil(AirPodsKey.parse("xyz"))
        XCTAssertNil(AirPodsKey.parse(String(repeating: "0", count: 31)))
        XCTAssertNil(AirPodsKey.parse(String(repeating: "g", count: 32)))
    }

    func testInspectionDistinguishesMissingKeyFromMalformedPayload() throws {
        let encrypted = try packet(closed)
        XCTAssertEqual(CaseAdvertisement.inspect(manufacturerData: encrypted), .invalidKey)
        XCTAssertEqual(CaseAdvertisement.inspect(manufacturerData: encrypted, key: Data()), .invalidKey)
        XCTAssertEqual(CaseAdvertisement.inspect(manufacturerData: encrypted, key: Data(repeating: 0xff, count: 16)), .layoutMismatch)
        var malformed = closed
        malformed[11] = 1
        XCTAssertEqual(CaseAdvertisement.inspect(manufacturerData: try packet(malformed), key: key), .layoutMismatch)
        XCTAssertEqual(CaseAdvertisement.inspect(manufacturerData: Data(), key: key), .notCase)
    }

    func testCasePacketInsideMultipleAppleMessages() throws {
        let standalone = try packet(closed)
        var combined = Data([0x4c, 0, 0x10, 0x01, 0x05])
        combined.append(standalone.dropFirst(2))
        combined.append(contentsOf: [0x12, 0x02, 0x00, 0x00])
        XCTAssertEqual(AppleAdvertisement.proximityPackets(in: combined), [standalone])
        XCTAssertEqual(CaseAdvertisement.decode(manufacturerData: combined, key: key),
                       CaseAdvertisement.decode(manufacturerData: standalone, key: key))
        combined.append(0x07)
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: combined, key: key))
        XCTAssertTrue(AppleAdvertisement.proximityPackets(in: Data([0x4c, 0, 0x07, 0xff, 0])).isEmpty)
    }

    func testCaseFlagVariationStillRequiresValidDecryptedFields() throws {
        var data = try packet(closed)
        data[4] = 0x07
        XCTAssertNotNil(CaseAdvertisement.decode(manufacturerData: data, key: key))
        XCTAssertNil(CaseAdvertisement.decode(manufacturerData: data, key: Data(repeating: 0xff, count: 16)))
    }

}
