import Foundation

/// Each entry describes a case message length and its payload decoder.
/// Add layouts here when another case uses different fields or packet lengths.
struct CasePacketLayout {
    let messageLength: UInt8
    let decodePayload: (Data) -> CaseAdvertisement?

    static let supported = [
        CasePacketLayout(messageLength: 0x11, decodePayload: decodeStatus)
    ]

    static func decode(_ data: Data, messageLength: UInt8,
                       layouts: [Self] = supported) -> CaseAdvertisement? {
        for layout in layouts where layout.messageLength == messageLength {
            if let result = layout.decodePayload(data) { return result }
        }
        return nil
    }

    /// Tested with AirPods Pro 3 (9A348). Model bytes are not an allowlist;
    /// payload length, reserved fields, and battery ranges must still match.
    private static func decodeStatus(_ data: Data) -> CaseAdvertisement? {
        let p = [UInt8](data)
        guard p.count == 16,
              p[8] == 0, p[10] <= 1, p[11] == 0,
              let percent = battery(p[3]),
              p[4] == 0xff || battery(p[4]) != nil,
              p[5] == 0xff || battery(p[5]) != nil
        else { return nil }
        return CaseAdvertisement(isOpen: p[2] & 0x08 == 0,
                                 openCounter: p[2] & 0x07,
                                 batteryPercent: percent,
                                 earbudsInCase: [p[4], p[5]].filter { $0 != 0xff }.count)
    }

    private static func battery(_ byte: UInt8) -> Int? {
        guard byte != 0xff, byte & 0x7f <= 100 else { return nil }
        return Int(byte & 0x7f)
    }
}
