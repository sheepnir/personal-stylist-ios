import SwiftUI
import UIKit

enum SyntheticSample: String, CaseIterable, Identifiable {
    case light = "Light on light", dark = "Dark on dark", sleeves = "Sleeves"
    case shoe = "Single shoe", pair = "Shoe pair", pattern = "Patterned fabric"
    case edges = "Fine edges", multiple = "Multiple objects", empty = "Empty background"
    var id: String { rawValue }

    func jpeg() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1600), format: format).image { context in
            let background: UIColor = self == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.94, alpha: 1)
            background.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1600))
            guard self != .empty else { return }
            let color: UIColor = self == .dark ? UIColor(white: 0.18, alpha: 1)
                : self == .light ? UIColor(white: 0.98, alpha: 1) : .systemBlue
            color.setFill()
            if self == .shoe || self == .pair {
                UIBezierPath(roundedRect: CGRect(x: 280, y: 400, width: 900, height: 290), cornerRadius: 110).fill()
                if self == .pair { UIBezierPath(roundedRect: CGRect(x: 370, y: 850, width: 900, height: 290), cornerRadius: 110).fill() }
            } else {
                let shirt = UIBezierPath()
                shirt.move(to: CGPoint(x: 550, y: 300))
                for point in [CGPoint(x: 320, y: 470), CGPoint(x: 450, y: 740), CGPoint(x: 560, y: 630),
                              CGPoint(x: 560, y: 1280), CGPoint(x: 1040, y: 1280), CGPoint(x: 1040, y: 630),
                              CGPoint(x: 1150, y: 740), CGPoint(x: 1280, y: 470), CGPoint(x: 1050, y: 300)] { shirt.addLine(to: point) }
                shirt.close(); shirt.fill()
                background.setFill(); UIBezierPath(ovalIn: CGRect(x: 690, y: 230, width: 220, height: 180)).fill()
                if self == .pattern {
                    UIColor.systemYellow.setFill()
                    for y in stride(from: 480, through: 1200, by: 100) {
                        context.fill(CGRect(x: 580, y: CGFloat(y), width: 440, height: 20))
                    }
                }
                if self == .edges {
                    color.setStroke()
                    for x in stride(from: 575, through: 1025, by: 30) {
                        let line = UIBezierPath(); line.lineWidth = 5
                        line.move(to: CGPoint(x: CGFloat(x), y: 1250)); line.addLine(to: CGPoint(x: CGFloat(x), y: 1410)); line.stroke()
                    }
                }
                if self == .multiple {
                    UIColor.systemOrange.setFill()
                    UIBezierPath(ovalIn: CGRect(x: 80, y: 980, width: 280, height: 280)).fill()
                }
            }
        }
        return image.jpegData(compressionQuality: 0.95)!
    }
}

@main struct HarnessApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @StateObject private var model = ProbeModel(source: SyntheticSample.light.jpeg())
    @State private var sample: SyntheticSample = .light
    @State private var insetCrop = false
    @State private var darkPreview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Feasibility harness only. In-memory results. Drawings are insufficient for the physical photo-quality gate.").font(.callout)
                    Picker("Synthetic sample", selection: $sample) {
                        ForEach(SyntheticSample.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Crop 10% after full-source mask", isOn: $insetCrop)
                        .disabled(model.busy)
                    Toggle("Dark preview surround", isOn: $darkPreview)
                    preview(model.source, label: "Original")
                    if let candidate = model.candidate { preview(candidate, label: "Candidate — solid neutral JPEG") }
                    Text(model.status).accessibilityIdentifier("probe.status")
                    HStack {
                        Button("Run") { model.run(insetCrop: insetCrop) }.disabled(model.busy)
                        Button("Cancel") { model.cancel() }.disabled(!model.busy)
                        Button("Restore preview") { model.setSource(sample.jpeg()) }.disabled(model.busy)
                    }
                    Text("No Save, Photos import, camera, network, permission prompts or production wardrobe access.").font(.footnote)
                }.padding()
            }
            .navigationTitle("Foreground mask probe")
            .onChange(of: sample) { _, value in model.setSource(value.jpeg()) }
            .onChange(of: insetCrop) { _, _ in model.setSource(sample.jpeg()) }
            .onDisappear { model.cancel() }
        }
    }

    private func preview(_ data: Data, label: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.headline)
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300)
                    .padding(8).background(darkPreview ? Color.black : Color.white)
                    .accessibilityLabel(label)
            }
        }
    }
}
