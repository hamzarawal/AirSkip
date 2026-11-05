import Foundation

/// Times use a monotonic clock (system uptime), so changing the wall clock cannot
/// prolong a stale open-lid reading. Tick at a short interval; never catch up missed ticks.
public struct SkipController {
    public static let signalTimeout: TimeInterval = 3
    public var interval: TimeInterval = 0.5
    public private(set) var latest: CaseAdvertisement?
    public private(set) var lastSeen: TimeInterval?
    public private(set) var hasSeenOpen = false
    public private(set) var hasSeenClosed = false
    public private(set) var verified = false
    public private(set) var source: UUID?
    private var lastPress: TimeInterval?

    public init() {}

    /// Pin one peripheral so separate nearby cases cannot combine lid states or
    /// drive an already verified session. A new address needs fresh verification.
    @discardableResult
    public mutating func observe(_ advertisement: CaseAdvertisement, at now: TimeInterval, source: UUID) -> Bool {
        guard self.source == nil || self.source == source else { return false }
        self.source = source
        latest = advertisement
        lastSeen = now
        hasSeenOpen = hasSeenOpen || advertisement.isOpen
        hasSeenClosed = hasSeenClosed || !advertisement.isOpen
        if !advertisement.isOpen { lastPress = nil }
        return true
    }

    public mutating func selectSource(_ source: UUID?) {
        guard self.source != source else { return }
        let delay = interval
        reset()
        interval = delay
        self.source = source
    }

    public mutating func verify() -> Bool {
        guard hasSeenOpen, hasSeenClosed else { return false }
        verified = true
        return true
    }

    public mutating func restoreVerification(for source: UUID) {
        selectSource(source)
        clearSignal()
        verified = true
    }

    public func isFresh(at now: TimeInterval) -> Bool {
        guard let lastSeen else { return false }
        return now >= lastSeen && now - lastSeen < Self.signalTimeout
    }

    public mutating func shouldPress(at now: TimeInterval, enabled: Bool, targetReady: Bool) -> Bool {
        guard enabled, verified, targetReady, isFresh(at: now), latest?.isOpen == true else {
            lastPress = nil
            return false
        }
        let safeInterval = interval.isFinite ? min(2, max(0.15, interval)) : 0.5
        if let lastPress, now - lastPress < safeInterval { return false }
        lastPress = now
        return true
    }

    /// Clear the live signal on disable or sleep while retaining verification.
    public mutating func clearSignal() {
        latest = nil
        lastSeen = nil
        lastPress = nil
    }

    public mutating func reset() { self = Self() }
}
