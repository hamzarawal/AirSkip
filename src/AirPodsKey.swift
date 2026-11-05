import Foundation

public enum AirPodsKey {
    public static func parse(_ text: String) -> Data? {
        let compact = text.filter { !$0.isWhitespace && $0 != "-" && $0 != ":" }
        guard compact.count == 32, compact.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        var bytes = [UInt8]()
        var index = compact.startIndex
        for _ in 0..<16 {
            let end = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        return Data(bytes)
    }
}
