import Foundation

public struct CaseAdvertisement: Equatable {
    public let isOpen: Bool
    public let openCounter: UInt8
    public let batteryPercent: Int
    public let earbudsInCase: Int
    public private(set) var deliveredPlaintext = false

    public enum Inspection: Equatable {
        case notCase, invalidKey, layoutMismatch
        case decoded(CaseAdvertisement)
    }

    /// CoreBluetooth may deliver an already decoded payload. Check its layout
    /// first, then try AES for an encrypted payload.
    public static func decode(manufacturerData: Data, key: Data? = nil) -> Self? {
        guard case .decoded(let result) = inspect(manufacturerData: manufacturerData, key: key) else { return nil }
        return result
    }

    public static func inspect(manufacturerData: Data, key: Data? = nil) -> Inspection {
        var failure: Inspection = .notCase
        for packet in AppleAdvertisement.proximityPackets(in: manufacturerData) {
            let result = inspectPacket(packet, key: key)
            switch result {
            case .decoded: return result
            case .notCase: break
            default: failure = result
            }
        }
        return failure
    }

    private static func inspectPacket(_ data: Data, key: Data?) -> Inspection {
        let bytes = [UInt8](data)
        guard bytes.count >= 5,
              bytes[0] == 0x4c, bytes[1] == 0x00, bytes[2] == 0x07,
              bytes.count == 4 + Int(bytes[3]),
              CasePacketLayout.supported.contains(where: { $0.messageLength == bytes[3] })
        else { return .notCase }
        let messageLength = bytes[3]
        let payload = Data(bytes.dropFirst(5))
        if var result = decodePlaintext(payload, messageLength: messageLength) {
            result.deliveredPlaintext = true
            return .decoded(result)
        }
        guard let key, let plaintext = AESBlock.decrypt(payload, key: key) else { return .invalidKey }
        guard let result = decodePlaintext(plaintext, messageLength: messageLength) else { return .layoutMismatch }
        return .decoded(result)
    }

    public static func decodePlaintext(_ data: Data, messageLength: UInt8 = 0x11) -> Self? {
        CasePacketLayout.decode(data, messageLength: messageLength)
    }
}
