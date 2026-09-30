// Standalone macOS 14+ feasibility probe. Excluded from project.yml source roots.
// Synthetic images only. Never modifies app storage or the input file.
import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ProbeFailure: Error { case usage, decode, empty, ambiguous, render, encode, existingOutput }

func selectInstance(_ ids: IndexSet) throws -> IndexSet {
    guard !ids.isEmpty else { throw ProbeFailure.empty }
    guard ids.count == 1 else { throw ProbeFailure.ambiguous }
    return ids
}

if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] {
    // Deterministic policy tests, not segmentation-quality evidence.
    let singleton = try selectInstance(IndexSet(integer: 7))
    assert(singleton == IndexSet(integer: 7))
    for ids in [IndexSet(), IndexSet([1, 2])] {
        do { _ = try selectInstance(ids); fatalError("Expected refusal") }
        catch ProbeFailure.empty { assert(ids.isEmpty) }
        catch ProbeFailure.ambiguous { assert(ids.count > 1) }
    }
    print("PASS: empty and ambiguous results refused; singleton retained")
} else {
    guard CommandLine.arguments.count == 3 else { throw ProbeFailure.usage }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    guard input.standardizedFileURL != output.standardizedFileURL,
          !FileManager.default.fileExists(atPath: output.path) else { throw ProbeFailure.existingOutput }
    guard #available(macOS 14, *) else { throw ProbeFailure.usage }
    let began = Date()
    try autoreleasepool {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { throw ProbeFailure.decode }
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { throw ProbeFailure.empty }
        let selected = try selectInstance(observation.allInstances)
        let maskBuffer = try observation.generateScaledMaskForImage(forInstances: selected, from: handler)
        let foreground = CIImage(cgImage: image)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        // JPEG cannot retain transparency. Preserve canvas size; flatten onto fixed #F2F2F2.
        let background = CIImage(color: CIColor(red: 242.0/255, green: 242.0/255, blue: 242.0/255))
            .cropped(to: foreground.extent)
        let candidate = foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask,
        ])
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(candidate, from: foreground.extent),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ProbeFailure.render }
        CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ProbeFailure.encode }
        try (destinationData as Data).write(to: output, options: [.withoutOverwriting])
        print("Candidate produced in \(Date().timeIntervalSince(began)) seconds; quality requires human inspection.")
    }
}
