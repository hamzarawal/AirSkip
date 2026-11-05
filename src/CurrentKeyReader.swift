import Foundation
import IOBluetooth

/// One user-requested AAP session, limited to reading proximity keys.
/// Never disconnects the device, retries, changes audio settings, or logs packets.
final class CurrentKeyReader: NSObject, IOBluetoothL2CAPChannelDelegate {
    private enum Stage { case opening, handshake, features, key, finished }
    private var stage = Stage.opening
    private var channel: IOBluetoothL2CAPChannel?
    private var timeout: Timer?
    private var featureFallback: Timer?
    private var completion: ((Result<Data, Error>) -> Void)?

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    func start(address: String, completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        guard let device = IOBluetoothDevice(addressString: address), device.isPaired(), device.isConnected() else {
            finish(.failure(Failure(errorDescription: "Connect your AirPods to this Mac first, with the earbuds out of the case, then read the current key.")))
            return
        }
        timeout = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.finish(.failure(Failure(errorDescription: self.stage == .key
                ? "AirPods did not return a broadcast key. Your saved key was kept."
                : "AirPods did not complete the control handshake. macOS may already hold this connection; your saved key was kept.")))
        }
        if let timeout { RunLoop.main.add(timeout, forMode: .common) }
        let result = device.openL2CAPChannelAsync(&channel, withPSM: 0x1001, delegate: self)
        if result != kIOReturnSuccess {
            finish(.failure(Failure(errorDescription: "Could not open the AirPods key connection (\(result)). Your saved key was kept.")))
        }
    }

    func l2capChannelOpenComplete(_ l2capChannel: IOBluetoothL2CAPChannel!, status error: IOReturn) {
        guard stage != .finished else { l2capChannel?.close(); return }
        guard error == kIOReturnSuccess, let l2capChannel else {
            finish(.failure(Failure(errorDescription: "AirPods refused the key connection (\(error)). Your saved key was kept.")))
            return
        }
        channel = l2capChannel
        stage = .handshake
        send([0, 0, 4, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    func l2capChannelData(_ l2capChannel: IOBluetoothL2CAPChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard stage != .finished, let dataPointer, dataLength > 0, dataLength <= 1024 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        if stage == .handshake, data.starts(with: [1, 0, 4, 0]) {
            stage = .features
            send([4, 0, 4, 0, 0x4d, 0, 0xd7, 0, 0, 0, 0, 0, 0, 0])
            guard stage != .finished else { return }
            featureFallback = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in self?.requestKey() }
            if let featureFallback { RunLoop.main.add(featureFallback, forMode: .common) }
        } else if stage == .features, data.starts(with: [4, 0, 4, 0, 0x2b, 0]) {
            requestKey()
        } else if stage == .key, data.starts(with: [4, 0, 4, 0, 0x31, 0]) {
            guard let key = ProximityKeyReply.encryptionKey(in: data) else {
                finish(.failure(Failure(errorDescription: "AirPods returned an unsupported key reply. Your saved key was kept.")))
                return
            }
            finish(.success(key))
        }
    }

    func l2capChannelClosed(_ l2capChannel: IOBluetoothL2CAPChannel!) {
        guard stage != .finished else { return }
        finish(.failure(Failure(errorDescription: "The AirPods key connection closed before a key arrived. Your saved key was kept.")))
    }

    private func requestKey() {
        guard stage == .features else { return }
        featureFallback?.invalidate()
        stage = .key
        send([4, 0, 4, 0, 0x0f, 0, 0xff, 0xff, 0xff, 0xff, 0xff])
        guard stage != .finished else { return }
        send([4, 0, 4, 0, 0x30, 0, 5, 0])
    }

    private func send(_ bytes: [UInt8]) {
        guard let channel, stage != .finished else { return }
        var data = bytes
        let result = data.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
        if result != kIOReturnSuccess {
            finish(.failure(Failure(errorDescription: "Could not send the AirPods key request (\(result)). Your saved key was kept.")))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard stage != .finished else { return }
        stage = .finished
        timeout?.invalidate()
        featureFallback?.invalidate()
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        let callback = completion
        completion = nil
        callback?(result)
    }
}
