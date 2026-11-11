import AppKit
import CoreBluetooth
import Combine
import Security

struct NearbyCase: Identifiable {
    let id: UUID
    let name: String
    var rssi: Int
}

final class AppModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var enabled = false
    @Published var interval = 0.5 {
        didSet {
            controller.interval = interval
            defaults.set(interval, forKey: "repeatInterval")
        }
    }
    @Published var pairedDevices: [PairedDevice] = []
    @Published private(set) var selectedAddress = ""
    @Published private(set) var deviceStatus = "Finding your AirPods…"
    @Published var deviceName = "AirPods"
    @Published var keyReady = false
    @Published var loadingKey = false
    @Published var scanning = false
    @Published var bluetoothStatus = "Bluetooth starts when you listen"
    @Published var accessibilityReady = false
    @Published var signal: CaseAdvertisement?
    @Published var signalFresh = false
    @Published var sawOpen = false
    @Published var sawClosed = false
    @Published var verified = false
    @Published var activity = "Open and close your case once"
    @Published var message: String?
    @Published var sentCount = 0
    @Published private(set) var listeningRequested = false
    @Published private(set) var scanDiagnostics = ""
    @Published private(set) var nearbyCases: [NearbyCase] = []
    @Published private(set) var selectedCaseID: UUID?

    private var central: CBCentralManager?
    private var key: Data?
    private var deviceKeys: [String: Data] = [:]
    private var currentKeyReader: CurrentKeyReader?
    private var keyRevision = 0
    private var controller = SkipController()
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var unlockedObserver: NSObjectProtocol?
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var sessionLocked = false
    private var asleep = false
    private var casePackets = 0
    private var advertisementCount = 0
    private var decodedCasePackets = 0
    private var plaintextCasePackets = 0
    private var closestCaseRSSI: Int?
    private var scanStartedAt: TimeInterval?
    private var setupStarted = false
    private var lastDeviceRefresh: TimeInterval = 0
    private var manuallySelectedDevice = false
    private var savedKeyAttempts: Set<String> = []
    private var pairedKeyAttempts: Set<String> = []
    private var currentKeyAttempts: Set<String> = []
    private let defaults: UserDefaults
    private let deviceProvider: () -> [PairedDevice]
    private static let lidMatchKey = "verifiedLidMatch"

    override convenience init() {
        self.init(defaults: .standard, deviceProvider: PairedDevice.list)
    }

    func openAccessibilitySettings() {
        ChromeKeySender.requestAccessibility { [weak self] opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                self?.message = "Couldn’t open System Settings. Open it from the Apple menu, then choose Privacy & Security → Accessibility and allow AirSkip."
            }
        }
    }

    init(defaults: UserDefaults, deviceProvider: @escaping () -> [PairedDevice]) {
        self.defaults = defaults
        self.deviceProvider = deviceProvider
        super.init()
        let savedInterval = defaults.double(forKey: "repeatInterval")
        if savedInterval.isFinite, (0.15...2).contains(savedInterval) { interval = savedInterval }
        controller.interval = interval
        deviceName = defaults.string(forKey: "caseName") ?? "AirPods"
        accessibilityReady = ChromeKeySender.hasAccessibility
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true
            self?.pauseForSession()
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false
            self?.activity = "Enable again after waking your Mac"
        }
        lockObserver = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionLocked = true
            self?.pauseForSession()
        }
        unlockedObserver = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionLocked = false
        }
        screenLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.sessionLocked = true
            self?.pauseForSession()
        }
        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.sessionLocked = false }
    }

    deinit {
        timer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        for observer in [sleepObserver, wakeObserver, lockObserver, unlockedObserver].compactMap({ $0 }) {
            center.removeObserver(observer)
        }
        for observer in [screenLockObserver, screenUnlockObserver].compactMap({ $0 }) {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    func beginSetup() {
        guard !setupStarted else { return }
        setupStarted = true
        refreshPairedDevices()
        startListening()
    }

    func refreshPairedDevices() {
        pairedDevices = deviceProvider()
        guard !enabled, !verified, !loadingKey else { return }
        if !manuallySelectedDevice {
            let remembered = defaults.string(forKey: "pairedAddress")
            applyDevice(PairedDevice.preferred(in: pairedDevices, rememberedID: remembered)?.id ?? "")
        }
        if let device = pairedDevices.first(where: { $0.id == selectedAddress }) {
            deviceStatus = device.isConnected ? "Connected to \(device.name)" : "Using \(device.name) · earbuds disconnected"
        } else {
            deviceStatus = pairedDevices.contains(where: { $0.name.localizedCaseInsensitiveContains("AirPods") })
                ? "More than one pair found. Choose yours in Troubleshooting."
                : "Connect your AirPods to this Mac. Renamed pair? Choose it in Troubleshooting."
        }
    }

    func retryAutomaticSetup() {
        guard !loadingKey else { return }
        // End the existing scan so Retry setup actually starts discovery again,
        // even when CoreBluetooth still reports a stalled scan as active.
        stopListening()
        manuallySelectedDevice = false
        savedKeyAttempts = []
        pairedKeyAttempts = []
        currentKeyAttempts = []
        selectCase(nil)
        refreshPairedDevices()
        startListening()
    }

    func selectPairedDevice(_ address: String) {
        guard !loadingKey else { return }
        manuallySelectedDevice = true
        if selectedAddress != address { defaults.removeObject(forKey: Self.lidMatchKey) }
        applyDevice(address)
        refreshPairedDevices()
        startListening()
    }

    private func applyDevice(_ address: String) {
        guard selectedAddress != address else { return }
        let resume = listeningRequested
        stopListening()
        keyRevision += 1
        key = nil
        keyReady = false
        controller.reset()
        controller.interval = interval
        nearbyCases = []
        selectedAddress = address
        key = deviceKeys[address]
        keyReady = key != nil
        if let device = pairedDevices.first(where: { $0.id == address }) {
            deviceName = device.name
            defaults.set(address, forKey: "pairedAddress")
        }
        restoreSavedLidMatch()
        publishSignal()
        if resume { startListening() }
    }

    /// Device discovery can finish after beginSetup. Restore when the pair becomes
    /// available, before automatic key recovery can reset the session.
    private func restoreSavedLidMatch() {
        guard !selectedAddress.isEmpty,
              let match = defaults.dictionary(forKey: Self.lidMatchKey) as? [String: String],
              match["address"] == selectedAddress,
              let source = match["source"].flatMap(UUID.init(uuidString:)) else { return }
        controller.restoreVerification(for: source)
        activity = "Case verified. Turn on AirSkip when ready."
    }

    /// Each stage runs once per device per launch. Failed automatic access never
    /// produces a prompt loop; explicit retries live in Troubleshooting.
    private func recoverKeyIfNeeded() {
        guard scanning, !loadingKey,
              let device = pairedDevices.first(where: { $0.id == selectedAddress }) else { return }
        if key == nil, !savedKeyAttempts.contains(device.id), signal == nil {
            savedKeyAttempts.insert(device.id)
            retrieveKey(for: device, paired: false)
        } else if !enabled, signal == nil, decodedCasePackets == 0, casePackets > 0,
                  let scanStartedAt,
                  ProcessInfo.processInfo.systemUptime - scanStartedAt > 5 {
            if !pairedKeyAttempts.contains(device.id) {
                pairedKeyAttempts.insert(device.id)
                retrieveKey(for: device, paired: true)
            } else if device.isConnected, !currentKeyAttempts.contains(device.id) {
                currentKeyAttempts.insert(device.id)
                readCurrentKey(automatically: true)
            }
        }
    }

    private func retrieveKey(for device: PairedDevice, paired: Bool) {
        loadingKey = true
        keyRevision += 1
        let revision = keyRevision
        if paired { activity = "Finishing AirPods setup. Approve macOS access if asked." }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () throws -> Data? in
                if paired {
                    let loaded = try CaseKeyStore.loadPairedKey(address: device.id)
                    try CaseKeyStore.save(loaded, address: device.id)
                    return loaded
                }
                return try CaseKeyStore.loadSavedKey(address: device.id, allowPrompt: false)
            }
            DispatchQueue.main.async {
                guard let self, self.keyRevision == revision, self.selectedAddress == device.id else { return }
                self.loadingKey = false
                switch result {
                case .success(let loaded):
                    if let loaded {
                        let resume = self.listeningRequested
                        self.acceptKey(loaded, name: device.name, preserveVerification: true)
                        if resume && !self.listeningRequested { self.startListening() }
                    }
                case .failure(let error):
                    // Cancellation is final for this automatic attempt. Do not
                    // follow a denied credential prompt with another method.
                    if case CaseKeyStore.Failure.keychain(let status) = error,
                       status == errSecUserCanceled || status == errSecAuthFailed {
                        self.currentKeyAttempts.insert(device.id)
                    }
                    if paired { self.message = "AirPods setup needs attention. Open Troubleshooting to retry." }
                }
            }
        }
    }

    func loadPairedKey() {
        guard let device = pairedDevices.first(where: { $0.id == selectedAddress }), !loadingKey else { return }
        loadingKey = true
        keyRevision += 1
        message = nil
        stopListening()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let loaded = try CaseKeyStore.loadPairedKey(address: device.id)
                try CaseKeyStore.save(loaded, address: device.id)
                DispatchQueue.main.async { self?.acceptKey(loaded, name: device.name) }
            } catch {
                DispatchQueue.main.async {
                    self?.loadingKey = false
                    self?.message = error.localizedDescription
                }
            }
        }
    }

    func importKey(_ text: String) -> Bool {
        guard let imported = AirPodsKey.parse(text) else {
            message = "Enter the 16-byte MagicAccEncKey (32 hexadecimal digits)."
            return false
        }
        keyRevision += 1
        do {
            try CaseKeyStore.save(imported, address: selectedAddress)
            acceptKey(imported, name: deviceName)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func readCurrentKey(automatically: Bool = false) {
        guard !loadingKey, let device = pairedDevices.first(where: { $0.id == selectedAddress }) else { return }
        loadingKey = true
        keyRevision += 1
        let revision = keyRevision
        let oldKey = key
        let resume = automatically && listeningRequested
        stopListening()
        message = "Reading the broadcast key from your connected AirPods…"
        let reader = CurrentKeyReader()
        currentKeyReader = reader
        reader.start(address: device.id) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.keyRevision == revision else { return }
                self.currentKeyReader = nil
                switch result {
                case .failure(let error):
                    self.loadingKey = false
                    self.message = automatically ? "Couldn’t finish AirPods setup. Open Troubleshooting to retry." : error.localizedDescription
                    if resume { self.startListening(); self.message = "Couldn’t finish AirPods setup. Open Troubleshooting to retry." }
                case .success(let current):
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        do {
                            try CaseKeyStore.save(current, address: device.id)
                            DispatchQueue.main.async {
                                guard let self, self.keyRevision == revision else { return }
                                self.acceptKey(current, name: device.name, preserveVerification: automatically)
                                if resume { self.startListening() }
                                self.message = automatically ? nil : current == oldKey
                                    ? "AirPods returned the same broadcast key already saved. Listen again to check the packets."
                                    : "Loaded the current broadcast key directly from AirPods. Listen again and verify the lid."
                            }
                        } catch {
                            DispatchQueue.main.async {
                                guard let self, self.keyRevision == revision else { return }
                                self.loadingKey = false
                                if resume { self.startListening() }
                                self.message = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }

    func acceptKey(_ value: Data, name: String, preserveVerification: Bool = false) {
        let keepMatch = preserveVerification && controller.verified
        if !keepMatch { stopListening() }
        key = value
        if !selectedAddress.isEmpty { deviceKeys[selectedAddress] = value }
        keyReady = true
        deviceName = name
        defaults.set(name, forKey: "caseName")
        loadingKey = false
        message = nil
        guard !keepMatch else { return }
        // Automatic recovery must not erase a persisted match, even if device
        // discovery has not restored it into this session yet.
        if !preserveVerification { defaults.removeObject(forKey: Self.lidMatchKey) }
        let source = controller.source
        controller.reset()
        controller.interval = interval
        controller.selectSource(source)
        if preserveVerification { restoreSavedLidMatch() }
        publishSignal()
        activity = verified ? "Case verified. Turn on AirSkip when ready." : "Open and close your case once"
    }

    func forgetKey() {
        keyRevision += 1
        stopListening()
        do { try CaseKeyStore.forget(address: selectedAddress) } catch { message = error.localizedDescription; return }
        defaults.removeObject(forKey: Self.lidMatchKey)
        deviceKeys.removeValue(forKey: selectedAddress)
        savedKeyAttempts.insert(selectedAddress)
        pairedKeyAttempts.insert(selectedAddress)
        currentKeyAttempts.insert(selectedAddress)
        key = nil
        keyReady = false
        controller.reset()
        controller.interval = interval
        publishSignal()
        message = nil
        activity = "Open and close your case once"
    }

    func selectCase(_ id: UUID?) {
        guard id != controller.source else { return }
        enabled = false
        defaults.removeObject(forKey: Self.lidMatchKey)
        controller.selectSource(id)
        if id == nil { nearbyCases = [] }
        message = nil
        publishSignal()
        activity = "Open and close the selected case to verify it"
    }

    func loadSavedKey() {
        guard !loadingKey else { return }
        loadingKey = true
        stopListening()
        keyRevision += 1
        let revision = keyRevision
        let address = selectedAddress
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let saved = try CaseKeyStore.loadSavedKey(address: address)
                DispatchQueue.main.async {
                    guard let self, self.keyRevision == revision else { return }
                    if let saved { self.acceptKey(saved, name: self.deviceName) }
                    else {
                        self.loadingKey = false
                        self.message = "No saved key is available. Listening can still detect a case decoded by macOS."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.keyRevision == revision else { return }
                    self.loadingKey = false
                    self.message = error.localizedDescription
                }
            }
        }
    }

    func startListening() {
        guard !loadingKey, !sessionLocked, !asleep else { return }
        listeningRequested = true
        message = nil
        casePackets = 0
        advertisementCount = 0
        decodedCasePackets = 0
        plaintextCasePackets = 0
        closestCaseRSSI = nil
        scanDiagnostics = "Starting Bluetooth…"
        scanStartedAt = ProcessInfo.processInfo.systemUptime
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else { updateScanning() }
    }

    func stopListening() {
        enabled = false
        listeningRequested = false
        central?.stopScan()
        scanning = false
        scanStartedAt = nil
        controller.clearSignal()
        publishSignal()
    }

    func setEnabled(_ value: Bool) {
        if value {
            guard verified, ChromeKeySender.hasAccessibility, !asleep, !sessionLocked else { return }
            enabled = true
            if !scanning { startListening() }
        } else {
            stopListening()
            activity = "Disabled"
        }
    }

    func confirmCase() {
        guard signalFresh, !loadingKey, let source = controller.source else { return }
        verified = controller.verify()
        if verified {
            defaults.set(["address": selectedAddress, "source": source.uuidString], forKey: Self.lidMatchKey)
            activity = "Case verified. Turn on AirSkip when ready."
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = "Bluetooth ready"
        case .poweredOff: bluetoothStatus = "Turn Bluetooth on in System Settings"
        case .unauthorized: bluetoothStatus = "Allow AirSkip in Privacy & Security → Bluetooth"
        case .unsupported: bluetoothStatus = "Bluetooth LE is unavailable on this Mac"
        case .resetting: bluetoothStatus = "Bluetooth is restarting"
        case .unknown: bluetoothStatus = "Waiting for Bluetooth"
        @unknown default: bluetoothStatus = "Bluetooth unavailable"
        }
        updateScanning()
    }

    private func updateScanning() {
        guard let central else { return }
        if listeningRequested, central.state == .poweredOn, !asleep, !sessionLocked {
            if !central.isScanning {
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            }
            scanning = true
        } else {
            central.stopScan()
            scanning = false
            controller.clearSignal()
            publishSignal()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        advertisementCount += 1
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        for packet in AppleAdvertisement.proximityPackets(in: data) {
            let inspection = CaseAdvertisement.inspect(manufacturerData: packet, key: key)
            if inspection != .notCase {
                casePackets += 1
                let rssi = RSSI.intValue
                if (-127..<0).contains(rssi) { closestCaseRSSI = max(closestCaseRSSI ?? rssi, rssi) }
            }
            guard case .decoded(let decoded) = inspection else { continue }
            decodedCasePackets += 1
            if decoded.deliveredPlaintext { plaintextCasePackets += 1 }
            if let index = nearbyCases.firstIndex(where: { $0.id == peripheral.identifier }) {
                nearbyCases[index].rssi = RSSI.intValue
            } else if nearbyCases.count < 20 {
                nearbyCases.append(NearbyCase(id: peripheral.identifier,
                                             name: "Case \(nearbyCases.count + 1)", rssi: RSSI.intValue))
            }
            guard controller.observe(decoded, at: ProcessInfo.processInfo.systemUptime,
                                     source: peripheral.identifier) else { continue }
            message = nil
            publishSignal()
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if listeningRequested, now - lastDeviceRefresh > 5 {
            lastDeviceRefresh = now
            refreshPairedDevices()
        }
        recoverKeyIfNeeded()
        if listeningRequested {
            let summary = "\(bluetoothStatus)\nAdvertisements: \(advertisementCount) · case packets: \(casePackets) · decoded: \(decodedCasePackets)\nAlready decoded by macOS: \(plaintextCasePackets) · decrypted with key: \(decodedCasePackets - plaintextCasePackets)"
                + (closestCaseRSSI.map { "\nStrongest case signal: \($0) dBm" } ?? "")
            if scanDiagnostics != summary { scanDiagnostics = summary }
        }
        let trusted = ChromeKeySender.hasAccessibility
        if accessibilityReady != trusted { accessibilityReady = trusted }
        let fresh = controller.isFresh(at: now)
        if signalFresh != fresh { signalFresh = fresh }
        if scanning, !loadingKey, signal == nil, let scanStartedAt, now - scanStartedAt > 15, message == nil {
            message = casePackets > 0
                ? "Case packets are arriving but their layout is not recognized. Open Troubleshooting to retry AirPods setup."
                : "No compatible case broadcast received yet. Keep the case nearby and open/close it. This Mac or firmware may not expose the required broadcast."
        }
        let target = enabled ? ChromeKeySender.target() : ChromeKeySender.Target(pid: nil, reason: "Disabled")
        let ready = target.pid != nil && !asleep && !sessionLocked
        if controller.shouldPress(at: now, enabled: enabled, targetReady: ready), let pid = target.pid {
            if ChromeKeySender.pressRightArrow(pid: pid) { sentCount += 1 }
        }
        let nextActivity: String
        if enabled {
            if !scanning { nextActivity = bluetoothStatus }
            else if !signalFresh { nextActivity = "Waiting for a fresh case signal" }
            else if signal?.isOpen != true { nextActivity = "Lid closed · playback unchanged" }
            else if !ready { nextActivity = target.reason }
            else { nextActivity = "Fast-forwarding · right arrow every \(String(format: "%.2f", interval)) s" }
        } else if loadingKey {
            nextActivity = "Setting up your AirPods… Approve macOS access if asked."
        } else if listeningRequested && !scanning {
            nextActivity = bluetoothStatus
        } else if scanning {
            nextActivity = verified ? "Case verified. Turn on AirSkip when ready." : "Open and close the lid to verify your case"
        } else { nextActivity = activity }
        if activity != nextActivity { activity = nextActivity }
    }

    private func publishSignal() {
        selectedCaseID = controller.source
        signal = controller.latest
        signalFresh = controller.isFresh(at: ProcessInfo.processInfo.systemUptime)
        sawOpen = controller.hasSeenOpen
        sawClosed = controller.hasSeenClosed
        verified = controller.verified
    }

    private func pauseForSession() {
        stopListening()
        activity = "Paused while your Mac is asleep or locked"
    }
}
