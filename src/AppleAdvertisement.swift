import Foundation

public enum AppleAdvertisement {
    /// Split Apple's type/length/value messages, retaining the company ID on each.
    public static func proximityPackets(in data: Data) -> [Data] {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] == 0x4c, b[1] == 0 else { return [] }
        var offset = 2
        var packets: [Data] = []
        while offset < b.count {
            guard offset + 2 <= b.count else { return [] }
            let end = offset + 2 + Int(b[offset + 1])
            guard end <= b.count else { return [] }
            if b[offset] == 0x07 {
                packets.append(Data([0x4c, 0]) + Data(b[offset..<end]))
            }
            offset = end
        }
        return packets
    }
}
