import PhotosUI
import SwiftUI
import UIKit

/// Test seam so hosted tests can invoke the live library-picker callback.
enum PhotoReplaceLibraryPickerHooks {
    static var lastCoordinator: PhotoReplaceLibraryPicker.Coordinator?

    static func reset() {
        lastCoordinator = nil
    }
}

/// Out-of-process Photos picker (PHPicker). No PHPhotoLibrary permission.
struct PhotoReplaceLibraryPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onImage: onImage, onCancel: onCancel)
        PhotoReplaceLibraryPickerHooks.lastCoordinator = coordinator
        return coordinator
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.onImage = onImage
        context.coordinator.onCancel = onCancel
        PhotoReplaceLibraryPickerHooks.lastCoordinator = context.coordinator
        if Self.presentsLivePicker {
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = context.coordinator
            picker.view.accessibilityIdentifier = "photo.replace.photos"
            return picker
        }
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .systemBackground
        placeholder.view.accessibilityIdentifier = "photo.replace.photos"
        return placeholder
    }

    /// Live library picker stays off under XCTest — hosted tests inject via the Coordinator.
    private static var presentsLivePicker: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onImage = onImage
        context.coordinator.onCancel = onCancel
        PhotoReplaceLibraryPickerHooks.lastCoordinator = context.coordinator
        if let picker = uiViewController as? PHPickerViewController {
            picker.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onImage: (UIImage) -> Void
        var onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            finishPicking(itemProviders: results.map(\.itemProvider))
        }

        /// Production decode used by the PHPicker delegate. Hosted tests call this with a
        /// real `NSItemProvider` because `PHPickerResult` has no public initializer.
        func finishPicking(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first else {
                onCancel()
                return
            }
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                onCancel()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self?.onImage(image)
                    } else {
                        self?.onCancel()
                    }
                }
            }
        }
    }
}

/// Preview after Photos or camera. Save commits; Cancel / Choose another abandon staging.
struct PhotoReplacePreview: UIViewControllerRepresentable {
    let image: UIImage
    var onChooseAnother: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> PreviewActions {
        PreviewActions(onChooseAnother: onChooseAnother, onSave: onSave, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        context.coordinator.onChooseAnother = onChooseAnother
        context.coordinator.onSave = onSave
        context.coordinator.onCancel = onCancel
        let root = PhotoReplacePreviewController(image: image, actions: context.coordinator)
        let nav = UINavigationController(rootViewController: root)
        nav.view.accessibilityIdentifier = "photo.replace.preview"
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onChooseAnother = onChooseAnother
        context.coordinator.onSave = onSave
        context.coordinator.onCancel = onCancel
        if let root = uiViewController.viewControllers.first as? PhotoReplacePreviewController {
            root.previewImage = image
        }
    }

    final class PreviewActions: NSObject {
        var onChooseAnother: () -> Void
        var onSave: () -> Void
        var onCancel: () -> Void

        init(onChooseAnother: @escaping () -> Void, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onChooseAnother = onChooseAnother
            self.onSave = onSave
            self.onCancel = onCancel
        }

        @objc func chooseAnother() { onChooseAnother() }
        @objc func save() { onSave() }
        @objc func cancel() { onCancel() }
    }
}

private final class PhotoReplacePreviewController: UIViewController {
    var previewImage: UIImage {
        didSet { imageView.image = previewImage }
    }
    private let actions: PhotoReplacePreview.PreviewActions
    private let imageView = UIImageView()

    init(image: UIImage, actions: PhotoReplacePreview.PreviewActions) {
        self.previewImage = image
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "photo.replace.preview"
        title = PhotoReplaceCopy.previewTitle
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: PhotoReplaceCopy.cancel,
            style: .plain,
            target: actions,
            action: #selector(PhotoReplacePreview.PreviewActions.cancel)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = PhotoReplaceCopy.cancel
        navigationItem.leftBarButtonItem?.accessibilityHint = PhotoReplaceCopy.previewNavCancelHint
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "photo.replace.cancel.nav"

        imageView.image = previewImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = PhotoReplaceCopy.previewTitle

        let save = actionButton(
            PhotoReplaceCopy.save,
            identifier: "photo.replace.save",
            hint: PhotoReplaceCopy.saveHint,
            action: #selector(PhotoReplacePreview.PreviewActions.save)
        )
        let another = actionButton(
            PhotoReplaceCopy.chooseAnother,
            identifier: "photo.replace.chooseAnother",
            hint: PhotoReplaceCopy.chooseAnotherHint,
            action: #selector(PhotoReplacePreview.PreviewActions.chooseAnother)
        )
        let cancel = actionButton(
            PhotoReplaceCopy.cancel,
            identifier: "photo.replace.cancel",
            hint: PhotoReplaceCopy.previewFooterCancelHint,
            action: #selector(PhotoReplacePreview.PreviewActions.cancel)
        )
        let footnote = UILabel()
        footnote.text = PhotoReplaceCopy.staysOnDevice
        footnote.font = .preferredFont(forTextStyle: .footnote)
        footnote.textColor = .secondaryLabel
        footnote.numberOfLines = 0
        footnote.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [imageView, save, another, cancel, footnote])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.accessibilityIdentifier = "photo.replace.preview.scroll"
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            save.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            another.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func actionButton(_ title: String, identifier: String, hint: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
        button.accessibilityHint = hint
        button.accessibilityIdentifier = identifier
        button.accessibilityTraits.insert(.button)
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        button.addTarget(actions, action: action, for: .touchUpInside)
        return button
    }
}

/// Production replace chrome. Review embeds this; hosted tests mount it in a `UIWindow`.
struct PhotoReplaceHost<Content: View>: View {
    @ObservedObject var session: PhotoReplaceSession
    var onTryAgain: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .fullScreenCover(item: coverBinding, onDismiss: {
                session.apply(.coverDismissed)
            }) { cover in
                coverContent(cover)
            }
            .alert(
                session.state.alert?.title ?? "",
                isPresented: Binding(
                    get: { session.state.alert != nil },
                    set: { if !$0 { session.apply(.clearAlert) } }
                )
            ) {
                if session.state.alert?.showsOpenSettings == true {
                    Button(PhotoReplaceCopy.openSettings) { openAppSettings() }
                }
                if session.state.alert?.showsTryAgain == true {
                    Button("Try again") {
                        if let onTryAgain {
                            onTryAgain()
                        } else if let source = session.state.lastSource,
                                  let garmentId = session.state.garmentId {
                            session.apply(.chooseSource(source, garmentId: garmentId))
                        }
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(session.state.alert?.message ?? "")
            }
            .onChange(of: session.state.alert) { _, alert in
                if let alert {
                    AccessibilityNotification.Announcement(alert.message).post()
                }
            }
    }

    private var coverBinding: Binding<PhotoReplaceCover?> {
        Binding(
            get: { session.state.cover },
            set: { newValue in
                if newValue == nil { return }
                session.state.cover = newValue
            }
        )
    }

    @ViewBuilder
    private func coverContent(_ cover: PhotoReplaceCover) -> some View {
        switch cover {
        case .photos:
            PhotoReplaceLibraryPicker(
                onImage: { image in
                    session.state.incomingImage = image
                    session.apply(.nativeUsePhoto)
                },
                onCancel: {
                    session.apply(.nativeCancel)
                }
            )
            .ignoresSafeArea()
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
            PhotoReplacePreview(
                image: payload.image,
                onChooseAnother: { session.apply(.previewChooseAnother) },
                onSave: { session.apply(.previewSave) },
                onCancel: { session.apply(.previewCancel) }
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
