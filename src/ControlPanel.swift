import AppKit
import SwiftUI

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    @State private var manualKey = ""
    @State private var showImport = false
    @State private var showTroubleshooting = false

    private var enableHelp: String {
        if !model.verified { return "Open and close your case, then confirm the animation matches." }
        if !model.accessibilityReady { return "Allow AirSkip in Accessibility Settings to enable it." }
        return "Open the lid to skip. Close it to stop."
    }

    var body: some View {
        Group {
            if showTroubleshooting {
                troubleshootingScreen
            } else {
                mainScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { model.beginSetup() }
        .onChange(of: showTroubleshooting) { visible in
            if visible { model.refreshPairedDevices() }
        }
    }

    private var mainScreen: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: BrandIcon.menuBarImage())
                    .resizable().scaledToFit()
                    .frame(width: 32, height: 26)
                    .accessibilityHidden(true)
                Text("AirSkip")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Toggle("Enable AirSkip", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!model.enabled && (!model.verified || !model.accessibilityReady))
                    .help(enableHelp)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 12) {
                        CaseAnimation(isOpen: model.signalFresh && model.signal?.isOpen == true,
                                      earbuds: model.signalFresh ? (model.signal?.earbudsInCase ?? 2) : 2,
                                      active: model.enabled && model.signalFresh && model.signal?.isOpen == true)
                            .frame(height: 160)
                            .accessibilityElement()
                            .accessibilityLabel("AirPods case")
                            .accessibilityValue(model.signalFresh ? (model.signal?.isOpen == true ? "Lid open" : "Lid closed") : "Waiting for lid signal")
                            .help(model.activity)
                        repeatDelay
                    }

                    Text(model.activity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !model.verified {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Match your lid").fontWeight(.medium)
                            Text("Open and close the case. Confirm the animation follows.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 18) {
                                verificationMark("Open", done: model.sawOpen)
                                verificationMark("Closed", done: model.sawClosed)
                            }
                            HStack {
                                if !model.listeningRequested {
                                    Button("Find my AirPods") { model.refreshPairedDevices(); model.startListening() }
                                        .disabled(model.loadingKey)
                                }
                                Button("The lid matches") { model.confirmCase() }
                                    .disabled(!model.sawOpen || !model.sawClosed || !model.signalFresh || model.loadingKey)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if !model.accessibilityReady {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "cursorarrow.click").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Keyboard access").fontWeight(.medium)
                                Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                                    .help("Allow AirSkip in System Settings → Privacy & Security → Accessibility.")
                            }
                        }
                    }

                    if let message = model.message {
                        Label(message, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        showTroubleshooting = true
                    } label: {
                        HStack {
                            Label("Troubleshoot", systemImage: "wrench.and.screwdriver")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.caption)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens troubleshooting controls")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 4)
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var repeatDelay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Repeat delay").font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.2f s", model.interval))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $model.interval, in: 0.15...2, step: 0.05)
                .accessibilityLabel("Delay between right arrow presses")
            HStack {
                Text("Faster")
                Spacer()
                Text("Slower")
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var troubleshootingScreen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    showTroubleshooting = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Back to AirSkip")
                Text("Troubleshoot")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(22)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    troubleshootingCard("Try first", icon: "arrow.clockwise") {
                        recoveryAction("Restart discovery", detail: "Open the case nearby to find its signal.", button: "Retry setup", disabled: model.loadingKey) {
                            model.retryAutomaticSetup()
                        }
                    }

                    troubleshootingCard("Choose your AirPods", icon: "airpodspro") {
                        Text("Select your pair so only your case controls AirSkip.")
                            .foregroundStyle(.secondary)
                        Picker("Paired device", selection: Binding(get: { model.selectedAddress }, set: { model.selectPairedDevice($0) })) {
                            Text(model.pairedDevices.isEmpty ? "No paired devices" : "Choose a device…").tag("")
                            ForEach(model.pairedDevices) { device in
                                Text(device.name + (device.isConnected ? " · Connected" : "")).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .disabled(model.loadingKey)
                        Text(model.deviceStatus).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Refresh devices") { model.refreshPairedDevices() }
                            .disabled(model.loadingKey)
                            .help("Pair your AirPods in Bluetooth Settings, then refresh this list.")
                        if let selected = model.selectedCaseID {
                            Divider().padding(.vertical, 2)
                            Text("Nearby case").fontWeight(.medium)
                            Picker("Nearby case", selection: Binding(get: { selected }, set: { model.selectCase($0) })) {
                                ForEach(model.nearbyCases) { candidate in
                                    Text("\(candidate.name) · \(candidate.rssi) dBm").tag(candidate.id)
                                }
                            }
                            .labelsHidden()
                            .disabled(model.loadingKey)
                            Text("Wrong case? Find it again, then recheck the lid.")
                                .foregroundStyle(.secondary)
                            Button("Find case again") { model.selectCase(nil) }
                                .disabled(model.loadingKey)
                        }
                    }

                    troubleshootingCard("Keyboard access", icon: "cursorarrow.click") {
                        recoveryAction(model.accessibilityReady ? "Access allowed" : "Allow arrow keys", detail: "Turn on AirSkip in Accessibility so it can skip.", button: "Settings") {
                            model.openAccessibilitySettings()
                        }
                        Text(model.keyboardStatus)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Arrow key pairs posted: \(model.sentCount)")
                            .foregroundStyle(.secondary)
                        Text("Close these controls, bring YouTube in Chrome to the front, and click the video player. A posted key does not confirm the video received it.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    troubleshootingCard("If AirSkip can’t read the lid", icon: "key") {
                        Text("Your case sends its lid state over Bluetooth. Some signals are encrypted (scrambled). A key is a code that lets AirSkip read whether the lid is open or closed.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If the lid display already follows your case, skip this section. macOS may provide a readable signal, and AirSkip tries to find a key automatically when needed.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Still no lid reading? Try the sources below in order; stop once the lid display responds. These are different ways to get the same kind of key. Keys stay in Keychain on this Mac.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if model.keyReady {
                            Label("Key loaded", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        keySetup
                    }

                    if let message = model.message {
                        Label(message, systemImage: "info.circle")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.scanDiagnostics.isEmpty {
                        DisclosureGroup("Bluetooth diagnostics") {
                            Text("Signal counts help explain detection failures.")
                                .foregroundStyle(.secondary).padding(.top, 8)
                            Text(model.scanDiagnostics)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }

    private func troubleshootingCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func recoveryAction(_ title: String, detail: String, button: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                Text(button).frame(width: 88)
            }
            .disabled(disabled)
        }
    }

    private var keySetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            recoveryAction("1 · From AirSkip", detail: "Try the key AirSkip previously saved for your AirPods, if any.", button: "Load saved", disabled: model.loadingKey) {
                model.loadSavedKey()
            }
            Divider()
            recoveryAction("2 · From macOS", detail: "Try the key macOS stored when you paired your AirPods. Approve Keychain access if asked.", button: "Load paired", disabled: model.selectedAddress.isEmpty || model.loadingKey) {
                model.loadPairedKey()
            }
            Divider()
            recoveryAction("3 · From your AirPods", detail: "Request the current key directly. Take both earbuds out and connect them to this Mac first.", button: model.loadingKey ? "Reading…" : "Read key", disabled: model.selectedAddress.isEmpty || model.loadingKey) {
                model.readCurrentKey()
            }

            DisclosureGroup("Import key manually", isExpanded: $showImport) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use this only if the buttons above fail. In Keychain Access → System, find the MobileBluetooth item for your AirPods and show its password. Copy only MagicAccEncKey, the code used to read the encrypted signal, into the field below.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("MagicAccEncKey · 32 hex digits", text: $manualKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save key") {
                            if model.importKey(manualKey) {
                                manualKey = ""
                                showTroubleshooting = false
                                showImport = false
                            }
                        }.disabled(model.loadingKey)
                        if model.keyReady {
                            Button("Forget saved key") { model.forgetKey() }
                                .disabled(model.loadingKey)
                                .help("Remove AirSkip’s saved copy to start fresh.")
                        }
                    }
                }.padding(.top, 8)
            }
        }
    }

    private func verificationMark(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .font(.caption2).foregroundStyle(done ? Color.green : Color.secondary)
            .accessibilityValue(done ? "Received" : "Waiting")
    }

}
