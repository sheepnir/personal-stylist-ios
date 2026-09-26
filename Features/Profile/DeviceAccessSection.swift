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
    @State private var wrongShapeMessage: String?

    private var showsEnrollForm: Bool {
        !connected || model.deviceAccessRejected
    }

    private var statusText: String {
        if model.deviceAccessRejected {
            return DressingCopy.deviceAccessNotAccepted
        }
        return connected ? DressingCopy.deviceAccessReady : DressingCopy.deviceAccessNotSetUp
    }

    private var modeHelperText: String {
        mode == .enrollmentSecret
            ? DressingCopy.deviceAccessModeHelpSecret
            : DressingCopy.deviceAccessModeHelpToken
    }

    var body: some View {
        Section {
            Text(statusText)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(statusText)

            if model.deviceAccessRejected {
                Text(DressingCopy.deviceAccessNotAcceptedHelp)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(DressingCopy.deviceAccessNotAcceptedHelp)
            }

            if !connected || model.deviceAccessRejected {
                Text(DressingCopy.deviceAccessAskOwner)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(DressingCopy.deviceAccessAskOwner)
            }

            if showsEnrollForm {
                Picker("Paste kind", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Paste kind")
                .accessibilityValue(modeHelperText)

                Text(modeHelperText)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(modeHelperText)

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
                .onChange(of: pasteBuffer) { _, _ in wrongShapeMessage = nil }

                if let wrongShapeMessage {
                    Text(wrongShapeMessage)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(wrongShapeMessage)
                }

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
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(
                    mode == .enrollmentSecret
                        ? "Enroll with enrollment secret"
                        : "Save pasted token"
                )
            }

            if connected || model.deviceAccessRejected {
                Button("Clear device access", role: .destructive) {
                    showClearConfirm = true
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel("Clear device access")
            }
        } header: {
            Text("Device access")
        } footer: {
            Text("Needed for outfit builds on this phone. Tokens stay in Keychain only — never in the app package.")
                .font(.caption2)
        }
        .id(ProfileDraftView.deviceAccessSectionID)
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

        switch mode {
        case .deviceToken:
            guard !raw.isEmpty else {
                model.showToast(DressingCopy.deviceAccessPasteEmpty)
                return
            }
            guard DeviceTokenFormat.isIssuedShape(raw) else {
                wrongShapeMessage = DressingCopy.deviceAccessWrongShape
                pasteBuffer = ""
                AccessibilityNotification.Announcement(DressingCopy.deviceAccessWrongShape).post()
                return
            }
            pasteBuffer = ""
            if DeviceTokenStore.save(raw) {
                connected = true
                model.clearDeviceAccessRejected()
                model.showToast(DressingCopy.deviceAccessPasteSuccess)
            } else {
                model.showToast(DressingCopy.deviceAccessEnrollFailure)
            }

        case .enrollmentSecret:
            guard !raw.isEmpty else {
                model.showToast(DressingCopy.deviceAccessEnrollEmpty)
                return
            }
            pasteBuffer = ""
            isBusy = true
            defer { isBusy = false }
            let ok = await DeviceTokenEnrollment.enrollAndSave(
                baseURL: EngineConfig.baseURL,
                enrollmentSecret: raw
            )
            connected = DeviceTokenStore.hasToken
            if ok {
                model.clearDeviceAccessRejected()
                model.showToast(DressingCopy.deviceAccessEnrollSuccess, announce: false)
                AccessibilityNotification.Announcement(DressingCopy.deviceAccessEnrollSuccessAnnouncement)
                    .post()
            } else {
                model.showToast(DressingCopy.deviceAccessEnrollFailure)
            }
        }
    }
}
