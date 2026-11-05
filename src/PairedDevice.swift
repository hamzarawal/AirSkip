import Foundation

public struct PairedDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let isConnected: Bool

    public init(id: String, name: String, isConnected: Bool) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
    }

    /// A renamed device remains recognizable once explicitly chosen. Never pick
    /// an unrelated Bluetooth accessory or guess between multiple connected pairs.
    public static func preferred(in devices: [Self], rememberedID: String?) -> Self? {
        let candidates = devices.filter {
            $0.name.localizedCaseInsensitiveContains("AirPods") || $0.id == rememberedID
        }
        let connected = candidates.filter(\.isConnected)
        if connected.count == 1 { return connected[0] }
        if let remembered = connected.first(where: { $0.id == rememberedID }) { return remembered }
        if !connected.isEmpty { return nil }
        if let remembered = candidates.first(where: { $0.id == rememberedID }) { return remembered }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
