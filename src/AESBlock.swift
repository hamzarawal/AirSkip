import Foundation
import CommonCrypto

enum AESBlock {
    static func decrypt(_ data: Data, key: Data) -> Data? {
        crypt(data, key: key, operation: CCOperation(kCCDecrypt))
    }

    static func encrypt(_ data: Data, key: Data) -> Data? {
        crypt(data, key: key, operation: CCOperation(kCCEncrypt))
    }

    private static func crypt(_ data: Data, key: Data, operation: CCOperation) -> Data? {
        guard data.count == kCCBlockSizeAES128, key.count == kCCKeySizeAES128 else { return nil }
        var output = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { input in
                CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, key.count, nil, input.baseAddress, data.count,
                        &output, output.count, &written)
            }
        }
        guard status == kCCSuccess, written == kCCBlockSizeAES128 else { return nil }
        return Data(output.prefix(written))
    }
}
