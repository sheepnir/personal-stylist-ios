import SwiftUI

/// TestFlight / Release one-shot device-token seed (#89 / D-46).
/// Paste an enrollment secret or an already-issued device token; never ships defaults.
struct DeviceAccessSection: View {
    @ObservedObject var model: LoopDemoModel

    enum Mode: String, CaseIterable, Identifiable {
        case enrollmentSecret = "Enrollment secret"
        case deviceToken = "Device token"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .enrollmentSecret
    @State private var pasteBuffer: String = ""
    @State private var isBusy = false
    @State private var connected = DeviceTokenStore.hasToken
    @State private var showClearConfirm = false

    var body: some View {
        Section {
            Text(connected
                 ? DressingCopy.deviceAccessReady
                 : DressingCopy.deviceAccessNotSetUp)
                .accessibilityLabel(connected
                                    ? DressingCopy.deviceAccessReady
                                    : DressingCopy.deviceAccessNotSetUp)

            if !connected {
                Picker("Paste kind", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Paste kind")

                SecureField(
                    mode == .enrollmentSecret
                        ? "Paste enrollment secret once"
                        : "Paste device token once",
                    text: $pasteBuffer
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(
                    mode == .enrollmentSecret ? "Enrollment secret" : "Device token"
                )

                Button {
                    Task { await submit() }
                } label: {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text(mode == .enrollmentSecret
                             ? "Enroll with enrollment secret"
                             : "Save pasted token")
                    }
                }
                .disabled(isBusy)
                .accessibilityLabel(
                    mode == .enrollmentSecret
                        ? "Enroll with enrollment secret"
                        : "Save pasted token"
                )
            } else {
                Button("Clear device access", role: .destructive) {
                    showClearConfirm = true
                }
                .accessibilityLabel("Clear device access")
            }
        } header: {
            Text("Device access")
        } footer: {
            Text("Needed for outfit builds on this phone. Tokens stay in Keychain only — never in the app package.")
                .font(.caption2)
        }
        .onAppear { connected = DeviceTokenStore.hasToken }
        .onDisappear { pasteBuffer = "" }
        .confirmationDialog(
            "Clear device access?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear device access", role: .destructive) {
                _ = DeviceTokenStore.clear()
                connected = DeviceTokenStore.hasToken
                pasteBuffer = ""
                model.showToast(DressingCopy.deviceAccessCleared)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll need to paste a token or enroll again before remote outfit builds work.")
        }
    }

    @MainActor
    private func submit() async {
        let raw = pasteBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        pasteBuffer = ""

        switch mode {
        case .deviceToken:
            guard !raw.isEmpty else {
                model.showToast(DressingCopy.deviceAccessPasteEmpty)
                return
            }
            if DeviceTokenStore.save(raw) {
                connected = true
                model.showToast(DressingCopy.deviceAccessPasteSuccess)
            } else {
                model.showToast(DressingCopy.deviceAccessEnrollFailure)
            }

        case .enrollmentSecret:
            guard !raw.isEmpty else {
                model.showToast(DressingCopy.deviceAccessEnrollEmpty)
                return
            }
            isBusy = true
            defer { isBusy = false }
            let ok = await DeviceTokenEnrollment.enrollAndSave(
                baseURL: EngineConfig.baseURL,
                enrollmentSecret: raw
            )
            connected = DeviceTokenStore.hasToken
            model.showToast(
                ok
                    ? DressingCopy.deviceAccessEnrollSuccess
                    : DressingCopy.deviceAccessEnrollFailure
            )
        }
    }
}
