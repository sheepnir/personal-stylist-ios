import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Test seam so hosted tests can invoke the live Coordinator Use Photo callback.
enum SystemCameraPickerHooks {
    static var lastCoordinator: SystemCameraPicker.Coordinator?

    static func reset() {
        lastCoordinator = nil
    }
}

/// System still-photo camera. Video and microphone stay off. Does not save to Photos.
struct SystemCameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onImage: onImage, onCancel: onCancel)
        SystemCameraPickerHooks.lastCoordinator = coordinator
        return coordinator
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.onImage = onImage
        context.coordinator.onCancel = onCancel
        SystemCameraPickerHooks.lastCoordinator = context.coordinator
        if Self.presentsLiveCamera {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier]
            picker.allowsEditing = false
            picker.cameraCaptureMode = .photo
            picker.delegate = context.coordinator
            picker.view.accessibilityIdentifier = "camera.intake.capture"
            return picker
        }
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .systemBackground
        placeholder.view.accessibilityIdentifier = "camera.intake.capture"
        return placeholder
    }

    /// Live shutter stays off under XCTest — hosted tests inject Use Photo via the Coordinator.
    private static var presentsLiveCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onImage = onImage
        context.coordinator.onCancel = onCancel
        SystemCameraPickerHooks.lastCoordinator = context.coordinator
        if let picker = uiViewController as? UIImagePickerController {
            picker.delegate = context.coordinator
        }
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage) -> Void
        var onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Native Use Photo. Do not dismiss the UIKit picker — SwiftUI's cover does.
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }
    }
}

/// Preview after a still capture. Retake / Cancel abandon pending; Use photo continues.
/// UIKit actions so the hosted-view harness can see and tap real controls.
struct CameraPhotoPreview: UIViewControllerRepresentable {
    let image: UIImage
    var onRetake: () -> Void
    var onUsePhoto: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> PreviewActions {
        PreviewActions(onRetake: onRetake, onUsePhoto: onUsePhoto, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        context.coordinator.onRetake = onRetake
        context.coordinator.onUsePhoto = onUsePhoto
        context.coordinator.onCancel = onCancel
        let root = CameraPhotoPreviewController(image: image, actions: context.coordinator)
        let nav = UINavigationController(rootViewController: root)
        nav.view.accessibilityIdentifier = "camera.intake.preview"
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onRetake = onRetake
        context.coordinator.onUsePhoto = onUsePhoto
        context.coordinator.onCancel = onCancel
        if let root = uiViewController.viewControllers.first as? CameraPhotoPreviewController {
            root.previewImage = image
        }
    }

    final class PreviewActions: NSObject {
        var onRetake: () -> Void
        var onUsePhoto: () -> Void
        var onCancel: () -> Void

        init(onRetake: @escaping () -> Void, onUsePhoto: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onRetake = onRetake
            self.onUsePhoto = onUsePhoto
            self.onCancel = onCancel
        }

        @objc func retake() { onRetake() }
        @objc func usePhoto() { onUsePhoto() }
        @objc func cancel() { onCancel() }
    }
}

private final class CameraPhotoPreviewController: UIViewController {
    var previewImage: UIImage {
        didSet { imageView.image = previewImage }
    }
    private let actions: CameraPhotoPreview.PreviewActions
    private let imageView = UIImageView()

    init(image: UIImage, actions: CameraPhotoPreview.PreviewActions) {
        self.previewImage = image
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "camera.intake.preview"
        title = CameraIntakeCopy.takePhoto
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: CameraIntakeCopy.cancel,
            style: .plain,
            target: actions,
            action: #selector(CameraPhotoPreview.PreviewActions.cancel)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = CameraIntakeCopy.cancel

        imageView.image = previewImage
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = false

        let use = actionButton(CameraIntakeCopy.usePhoto, identifier: "camera.intake.usePhoto", action: #selector(CameraPhotoPreview.PreviewActions.usePhoto))
        let retake = actionButton(CameraIntakeCopy.retake, identifier: "camera.intake.retake", action: #selector(CameraPhotoPreview.PreviewActions.retake))
        let cancel = actionButton(CameraIntakeCopy.cancel, identifier: "camera.intake.cancel", action: #selector(CameraPhotoPreview.PreviewActions.cancel))
        let stack = UIStackView(arrangedSubviews: [imageView, use, retake, cancel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            use.heightAnchor.constraint(equalToConstant: 44),
            retake.heightAnchor.constraint(equalToConstant: 44),
            cancel.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func actionButton(_ title: String, identifier: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.addTarget(actions, action: action, for: .touchUpInside)
        return button
    }
}
