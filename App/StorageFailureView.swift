import SwiftUI

/// Blocks the core loop. There is no store to edit.
struct StorageFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(StorageFailureCopy.title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}
