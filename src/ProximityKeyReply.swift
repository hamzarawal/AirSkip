import Foundation

public enum ProximityKeyReply {
    /// Returns only the 16-byte encryption key from a complete AAP key reply.
    public static func encryptionKey(in packet: Data) -> Data? {
        let b = [UInt8](packet)
        guard b.count >= 7, b.starts(with: [4, 0, 4, 0, 0x31, 0]) else { return nil }
        var offset = 7
        var key: Data?
        for _ in 0..<Int(b[6]) {
            guard offset + 4 <= b.count else { return nil }
            let type = b[offset]
            let length = Int(b[offset + 2])
            offset += 4
            guard offset + length <= b.count else { return nil }
            if type == 4 {
                guard length == 16, key == nil else { return nil }
                key = Data(b[offset..<offset + length])
            }
            offset += length
        }
        guard offset == b.count else { return nil }
        return key
    }
}
