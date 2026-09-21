import SwiftUI
import UIKit

/// Production camera chrome. `WardrobeGridView` embeds this; hosted tests mount it
/// in a `UIWindow`. Same `fullScreenCover(item:onDismiss:)`, `sheet(item:)`, root
/// alerts, Coordinator `onImage`, and `CameraIntakeSession.apply` persist path.
struct CameraIntakeHost<Content: View>: View {
    @ObservedObject var session: CameraIntakeSession
    var onTryAgain: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .fullScreenCover(item: coverBinding, onDismiss: {
                session.apply(.coverDismissed)
            }) { cover in
                coverContent(cover)
            }
            .sheet(item: detailsBinding, onDismiss: {
                session.apply(.detailsDismissed)
            }) { pending in
                FinishDetailsSheet(
                    model: session.requireModel(),
                    garmentId: pending.id,
                    mode: .cameraIntake,
                    cameraPending: pending
                ) {
                    session.apply(.detailsDismissed)
                }
            }
            .alert(
                session.state.alert?.title ?? "",
                isPresented: Binding(
                    get: { session.state.alert != nil },
                    set: { if !$0 { session.apply(.clearAlert) } }
                )
            ) {
                if session.state.alert?.showsOpenSettings == true {
                    Button(CameraIntakeCopy.openSettings) { openAppSettings() }
                }
                if session.state.alert?.showsTryAgain == true {
                    Button("Try again") {
                        if let onTryAgain {
                            onTryAgain()
                        } else {
                            session.apply(.startCapture)
                        }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(session.state.alert?.message ?? "")
            }
    }

    private var coverBinding: Binding<CameraIntakeCover?> {
        Binding(
            get: { session.state.cover },
            set: { newValue in
                // SwiftUI writes nil when the capture cover dismisses. That write
                // can arrive after persist already installed a preview payload.
                if newValue == nil { return }
                session.state.cover = newValue
            }
        )
    }

    private var detailsBinding: Binding<CameraPending?> {
        Binding(
            get: { session.state.details },
            set: { session.state.details = $0 }
        )
    }

    @ViewBuilder
    private func coverContent(_ cover: CameraIntakeCover) -> some View {
        switch cover {
        case .capture:
            SystemCameraPicker(
                onImage: { image in
                    session.state.incomingImage = image
                    session.apply(.nativeUsePhoto)
                },
                onCancel: {
                    session.apply(.nativeCancel)
                }
            )
            .ignoresSafeArea()
        case .preview(let payload):
            CameraPhotoPreview(
                image: payload.image,
                onRetake: { session.apply(.previewRetake) },
                onUsePhoto: { session.apply(.previewUsePhoto) },
                onCancel: { session.apply(.previewCancel) }
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
