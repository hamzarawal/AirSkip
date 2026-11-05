import Foundation

public struct CaseAdvertisement: Equatable {
    public let isOpen: Bool
    public let openCounter: UInt8
    public let batteryPercent: Int
    public let earbudsInCase: Int
    public private(set) var deliveredPlaintext = false

    public enum Inspection: Equatable {
        case notCase, invalidKey, layoutMismatch
        case unsupportedHeader(UInt16)
        case decoded(CaseAdvertisement)
    }

    /// CoreBluetooth can deliver an already decoded 07/11 case payload. Check
    /// its structure first; only try AES when the payload is still encrypted.
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
            case .unsupportedHeader: failure = result
            case .notCase: break
            default:
                if case .unsupportedHeader = failure { continue }
                failure = result
            }
        }
        return failure
    }

    private static func inspectPacket(_ data: Data, key: Data?) -> Inspection {
        let bytes = [UInt8](data)
        guard bytes.count == 21,
              bytes[0] == 0x4c, bytes[1] == 0x00,
              bytes[2] == 0x07, bytes[3] == 0x11
        else { return .notCase }
        let payload = Data(bytes[5..<21])
        if var result = decodePlaintext(payload) {
            result.deliveredPlaintext = true
            return .decoded(result)
        }
        guard let key, let plaintext = AESBlock.decrypt(payload, key: key) else { return .invalidKey }
        let p = [UInt8](plaintext)
        guard p[8] == 0, p[10] <= 1, p[11] == 0,
              battery(p[3]) != nil,
              p[4] == 0xff || battery(p[4]) != nil,
              p[5] == 0xff || battery(p[5]) != nil else { return .layoutMismatch }
        guard p[0] == 0x29, p[1] == 0x20 else {
            return .unsupportedHeader(UInt16(p[0]) << 8 | UInt16(p[1]))
        }
        guard let result = decodePlaintext(plaintext) else { return .layoutMismatch }
        return .decoded(result)
    }

    public static func decodePlaintext(_ data: Data) -> Self? {
        let p = [UInt8](data)
        // This is a reverse-engineered layout, not authenticated encryption.
        // Firmware 9A348 on macOS also delivers byte 10 as 1. Keep the model,
        // remaining reserved fields and battery checks; neither format proves
        // device identity. The caller must bind and physically verify one source.
        guard p.count == 16, p[0] == 0x29, p[1] == 0x20,
              p[8] == 0, p[10] <= 1, p[11] == 0,
              let percent = battery(p[3]),
              p[4] == 0xff || battery(p[4]) != nil,
              p[5] == 0xff || battery(p[5]) != nil
        else { return nil }
        return Self(isOpen: p[2] & 0x08 == 0,
                    openCounter: p[2] & 0x07,
                    batteryPercent: percent,
                    earbudsInCase: [p[4], p[5]].filter { $0 != 0xff }.count)
    }

    private static func battery(_ byte: UInt8) -> Int? {
        guard byte != 0xff, byte & 0x7f <= 100 else { return nil }
        return Int(byte & 0x7f)
    }
}
