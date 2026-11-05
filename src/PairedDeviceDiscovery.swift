import Foundation
import IOBluetooth

extension PairedDevice {
    static func list() -> [Self] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.compactMap { device in
            guard let address = device.addressString else { return nil }
            return Self(id: address.replacingOccurrences(of: "-", with: ":").uppercased(),
                        name: device.name ?? "Bluetooth device", isConnected: device.isConnected())
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
