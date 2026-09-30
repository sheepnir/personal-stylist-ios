import Foundation
import UIKit
import ImageIO
import Vision
import CoreImage

enum MaskFailure: Error { case decode, empty, ambiguous, cancelled, render }

protocol MaskProcessing: AnyObject {
    func start(source: Data, insetCrop: Bool, completion: @escaping (Result<Data, Error>) -> Void)
    func cancel()
}

/// A single serial worker. Cancellation is cooperative; callers must also reject stale results.
final class VisionMaskProcessor: MaskProcessing {
    private let queue = DispatchQueue(label: "com.example.mask-probe", qos: .userInitiated)
    private let lock = NSLock()
    private var request: VNGenerateForegroundInstanceMaskRequest?
    private var cancelled = false

    static func select(_ instances: IndexSet) throws -> IndexSet {
        guard !instances.isEmpty else { throw MaskFailure.empty }
        guard instances.count == 1 else { throw MaskFailure.ambiguous }
        return instances
    }

    func start(source: Data, insetCrop: Bool, completion: @escaping (Result<Data, Error>) -> Void) {
        lock.lock(); cancelled = false; lock.unlock()
        queue.async {
            let result: Result<Data, Error> = Result {
                try autoreleasepool {
                    try self.checkCancellation()
                    guard let decoder = CGImageSourceCreateWithData(source as CFData, nil),
                          let bitmap = CGImageSourceCreateThumbnailAtIndex(decoder, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1600,
                            kCGImageSourceShouldCacheImmediately: true,
                          ] as CFDictionary) else { throw MaskFailure.decode }
                    let handler = VNImageRequestHandler(cgImage: bitmap, orientation: .up)
                    let request = VNGenerateForegroundInstanceMaskRequest()
                    self.lock.lock()
                    self.request = request
                    let shouldCancel = self.cancelled
                    self.lock.unlock()
                    if shouldCancel { throw MaskFailure.cancelled }
                    try handler.perform([request])
                    try self.checkCancellation()
                    guard let observations = request.results, !observations.isEmpty else { throw MaskFailure.empty }
                    guard observations.count == 1 else { throw MaskFailure.ambiguous }
                    let observation = observations[0]
                    let instances = try Self.select(observation.allInstances)
                    let buffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
                    try self.checkCancellation()
                    let fullSource = CIImage(cgImage: bitmap)
                    let fullMask = CIImage(cvPixelBuffer: buffer)
                    guard fullMask.extent == fullSource.extent else { throw MaskFailure.render }
                    // Segmentation is in full normalized source space; crop BOTH with one rect.
                    let rect = insetCrop
                        ? fullSource.extent.insetBy(dx: fullSource.extent.width * 0.1, dy: fullSource.extent.height * 0.1).integral
                        : fullSource.extent
                    let image = fullSource.cropped(to: rect)
                    let mask = fullMask.cropped(to: rect)
                    let neutral = CIImage(color: CIColor(red: 242.0/255, green: 242.0/255, blue: 242.0/255)).cropped(to: rect)
                    let composite = image.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: neutral, kCIInputMaskImageKey: mask,
                    ])
                    let context = CIContext(options: [.cacheIntermediates: false])
                    guard let rendered = context.createCGImage(composite, from: rect),
                          let jpeg = UIImage(cgImage: rendered).jpegData(compressionQuality: 0.82)
                    else { throw MaskFailure.render }
                    try self.checkCancellation()
                    return jpeg
                }
            }
            self.lock.lock(); self.request = nil; self.lock.unlock()
            completion(result)
        }
    }

    func cancel() {
        lock.lock(); cancelled = true; let active = request; lock.unlock()
        active?.cancel()
    }

    private func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw MaskFailure.cancelled }
    }
}
