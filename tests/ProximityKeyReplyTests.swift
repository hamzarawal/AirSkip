import XCTest
@testable import MenuBarApp

final class ProximityKeyReplyTests: XCTestCase {
    private let encryption = Data((0..<16).map(UInt8.init))
    private var reply: Data {
        var data = Data([4, 0, 4, 0, 0x31, 0, 2, 1, 0, 16, 0])
        data.append(Data(repeating: 0x55, count: 16))
        data.append(contentsOf: [4, 0, 16, 0])
        data.append(encryption)
        return data
    }

    func testSelectsEncryptionInsteadOfIdentityKey() {
        XCTAssertEqual(ProximityKeyReply.encryptionKey(in: reply), encryption)
    }

    func testRejectsTruncatedReplyAndWrongOpcode() {
        for size in 0..<reply.count {
            XCTAssertNil(ProximityKeyReply.encryptionKey(in: reply.prefix(size)))
        }
        var wrongOpcode = reply
        wrongOpcode[4] = 0x30
        XCTAssertNil(ProximityKeyReply.encryptionKey(in: wrongOpcode))
        var trailing = reply
        trailing.append(0)
        XCTAssertNil(ProximityKeyReply.encryptionKey(in: trailing))
    }

    func testRejectsMissingDuplicateOrWrongLengthEncryptionKey() {
        var missing = reply
        missing[27] = 1
        XCTAssertNil(ProximityKeyReply.encryptionKey(in: missing))
        var duplicate = reply
        duplicate[7] = 4
        XCTAssertNil(ProximityKeyReply.encryptionKey(in: duplicate))
        var wrongLength = reply
        wrongLength[29] = 15
        wrongLength.removeLast()
        XCTAssertNil(ProximityKeyReply.encryptionKey(in: wrongLength))
    }
}
