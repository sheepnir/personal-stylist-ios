import SwiftUI
import UIKit

/// UIKit-backed control so VoiceOver and hosted XCTest can discover, measure,
/// and activate wear actions. Visuals stay SwiftUI; the outer `UIButton` is the
/// accessibility and hit target (same idea as the #278 photo-replace preview).
struct DailyWearA11yButton<Content: View>: UIViewRepresentable {
    var identifier: String
    var label: String
    var hint: String? = nil
    var value: String? = nil
    var isSelected: Bool = false
    var isEnabled: Bool = true
    var minHeight: CGFloat = 44
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> HostedDailyWearA11yButton {
        let button = HostedDailyWearA11yButton()
        apply(button, coordinator: context.coordinator)
        button.setContent(content())
        return button
    }

    func updateUIView(_ button: HostedDailyWearA11yButton, context: Context) {
        context.coordinator.action = action
        apply(button, coordinator: context.coordinator)
        button.setContent(content())
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HostedDailyWearA11yButton, context: Context) -> CGSize {
        let width = proposal.width ?? 375
        let size = CGSize(width: width, height: uiView.preferredHeight(forWidth: width))
        uiView.bounds.size = size
        return size
    }

    private func apply(_ button: HostedDailyWearA11yButton, coordinator: Coordinator) {
        button.minHeight = minHeight
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.accessibilityHint = hint
        button.accessibilityValue = value
        button.allowsActivation = isEnabled
        button.isEnabled = isEnabled
        button.isAccessibilityElement = true
        var traits: UIAccessibilityTraits = .button
        if isSelected { traits.insert(.selected) }
        if !isEnabled { traits.insert(.notEnabled) }
        button.accessibilityTraits = traits
        button.onTap = { coordinator.action() }
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
    }
}

final class HostedDailyWearA11yButton: UIButton {
    var minHeight: CGFloat = 44
    var onTap: (() -> Void)?
    /// Own flag — SwiftUI writes `UIControl.isEnabled` back to `true` after `updateUIView`.
    var allowsActivation = true
    private var host: UIHostingController<AnyView>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        contentHorizontalAlignment = .fill
        contentVerticalAlignment = .fill
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    @objc private func handleTap() {
        guard allowsActivation else { return }
        onTap?()
    }

    required init?(coder: NSCoder) { nil }

    func setContent<V: View>(_ view: V) {
        let erase = AnyView(view.accessibilityHidden(true))
        if let host {
            host.rootView = erase
        } else {
            let hosted = UIHostingController(rootView: erase)
            hosted.view.backgroundColor = .clear
            hosted.view.isUserInteractionEnabled = false
            hosted.view.isAccessibilityElement = false
            hosted.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosted.view)
            NSLayoutConstraint.activate([
                hosted.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosted.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosted.view.topAnchor.constraint(equalTo: topAnchor),
                hosted.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            host = hosted
        }
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight(forWidth: bounds.width))
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let usable = width > 0 ? width : 375
        let fitted = host?.sizeThatFits(in: CGSize(width: usable, height: .greatestFiniteMagnitude)).height ?? minHeight
        return max(minHeight, fitted)
    }

    override func accessibilityActivate() -> Bool {
        guard allowsActivation else { return false }
        onTap?()
        return true
    }
}

/// Spoken success/failure heading that hosted XCTest can find (SwiftUI `Text` is not in the UIKit tree).
struct DailyWearA11yHeading: UIViewRepresentable {
    var text: String
    var identifier: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isAccessibilityElement = true
        apply(label)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        apply(label)
    }

    private func apply(_ label: UILabel) {
        label.text = text
        label.accessibilityLabel = text
        label.accessibilityIdentifier = identifier
        label.accessibilityTraits.insert(.header)
    }
}
