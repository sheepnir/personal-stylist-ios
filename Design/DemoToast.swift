import SwiftUI

/// Transient confirmation toast — auto-dismiss ~2.5s (#105 / claude-review-batch §5).
struct DemoToastHost: ViewModifier {
    @ObservedObject var model: LoopDemoModel

    func body(content: Content) -> some View {
        // GH #100: use a bottom safeAreaInset so the toast reserves space under the
        // board action bar (and scales with Dynamic Type / home indicator) instead of
        // overlaying a fixed offset across "Try another" / "Wearing this".
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let message = model.activeToast {
                    HStack(spacing: 12) {
                        Text(message)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                        if model.toastUndoAvailable {
                            Button("Undo") {
                                model.performSwapUndo()
                            }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel("Undo swap")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: model.activeToast)
            .animation(.easeInOut(duration: 0.22), value: model.toastUndoAvailable)
    }
}

extension View {
    func demoToastHost(model: LoopDemoModel) -> some View {
        modifier(DemoToastHost(model: model))
    }
}

#if DEBUG
/// DEBUG-only log of former status-strip strings (#105).
struct DemoDiagnosticsSheet: View {
    @ObservedObject var model: LoopDemoModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.generationLatencySamples.isEmpty {
                    Section("Generation latency (PRD ≤4s / ≤8s)") {
                        ForEach(model.generationLatencySamples.reversed()) { sample in
                            Text("\(sample.outcome): \(sample.milliseconds) ms — \(sample.note)")
                                .font(.caption)
                        }
                    }
                }
                Section("Log") {
                    if model.diagnosticLog.isEmpty {
                        Text("No diagnostic lines yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(model.diagnosticLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear") { model.clearDiagnosticLog() }
                }
            }
        }
    }
}
#endif
