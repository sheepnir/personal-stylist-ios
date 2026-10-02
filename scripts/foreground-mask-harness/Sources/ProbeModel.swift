import Foundation
import SwiftUI

@MainActor final class ProbeModel: ObservableObject {
    @Published private(set) var source: Data
    @Published private(set) var candidate: Data?
    @Published private(set) var busy = false
    @Published private(set) var status = "Not run. Drawings do not establish photo quality."
    private let processor: MaskProcessing
    private var generation = UUID()
    private var active: UUID?
    private var began = Date()
    // Test observer fires only after worker completion is consumed on the main actor.
    var didComplete: (() -> Void)?

    init(source: Data, processor: MaskProcessing = VisionMaskProcessor()) {
        self.source = source
        self.processor = processor
    }

    func setSource(_ value: Data) {
        cancel()
        source = value
        candidate = nil
        status = "Source changed. Previous result invalidated."
    }

    func run(insetCrop: Bool) {
        guard !busy else { return }
        let token = UUID()
        generation = token
        active = token
        busy = true
        began = Date()
        status = "Processing on serial worker…"
        processor.start(source: source, insetCrop: insetCrop) { [weak self] result in
            Task { @MainActor in self?.finish(token: token, result: result) }
        }
    }

    func cancel() {
        generation = UUID()
        if busy { processor.cancel() }
        status = busy ? "Cancelled. Waiting for worker to release resources." : "Cancelled. Original unchanged."
        // Keep busy until actual completion: never enqueue a second request while cancelling.
    }

    private func finish(token: UUID, result: Result<Data, Error>) {
        guard active == token else { return }
        active = nil
        busy = false
        defer { didComplete?() }
        guard generation == token else {
            status = "Late result discarded. Original unchanged."
            return
        }
        switch result {
        case .success(let data):
            guard !data.isEmpty else {
                status = "No safe result. Original and previous preview unchanged."
                return
            }
            candidate = data
            status = String(format: "Candidate: %.2f seconds. Inspect quality; no photo saved.", Date().timeIntervalSince(began))
        case .failure:
            status = "No safe result (empty, ambiguous, unsupported or failed). Original unchanged."
        }
    }
}
