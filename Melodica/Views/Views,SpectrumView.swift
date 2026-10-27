//Views,SpectrumView
import SwiftUI

struct SpectrumView: View {
    @ObservedObject private var spectrumHolder = VisualizationEngine.shared.spectrumHolder
    var data: [Float]? = nil
    var bands: Int = 32

    init(bands: Int = 32) {
        self.data = nil
        self.bands = bands
    }

    init(data: [Float]? = nil, bands: Int = 32) {
        self.data = data
        self.bands = bands
    }

    private var currentData: [Float] {
        let raw = data ?? spectrumHolder.data
        if bands <= 8 && raw.count >= 8 {
            return downsample(raw, to: 8)
        } else if bands <= 16 && raw.count >= 16 {
            return downsample(raw, to: 16)
        }
        return raw
    }

    private func downsample(_ input: [Float], to targetCount: Int) -> [Float] {
        let stride = input.count / targetCount
        guard stride > 1 else { return Array(input.prefix(targetCount)) }
        var result = [Float](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let start = i * stride
            let end = min(start + stride, input.count)
            let slice = input[start..<end]
            let maxVal = slice.max() ?? 0
            let avgVal = slice.reduce(0, +) / Float(slice.count)
            result[i] = maxVal * 0.7 + avgVal * 0.3
        }
        return result
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<currentData.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accent.opacity(0.7))
                    .frame(width: 3, height: max(4, CGFloat(currentData[i]) * 30))
            }
        }
        .id(currentData.count)
        .animation(.easeOut(duration: 0.05), value: currentData)
    }
}

struct RotatedSpectrumView: View {
    @ObservedObject private var spectrumHolder = VisualizationEngine.shared.spectrumHolder
    var data: [Float]? = nil
    let mirrored: Bool
    var color: Color = .white

    init(mirrored: Bool, color: Color = .white) {
        self.data = nil
        self.mirrored = mirrored
        self.color = color
    }

    init(data: [Float]? = nil, mirrored: Bool, color: Color = .white) {
        self.data = data
        self.mirrored = mirrored
        self.color = color
    }

    private var currentData: [Float] {
        data ?? spectrumHolder.data
    }

    var body: some View {
        let data = currentData
        Canvas { context, size in
            let barCount = data.count
            let barHeight: CGFloat = max(1, (size.height - CGFloat(barCount - 1) * 2) / CGFloat(barCount))

            for i in 0..<barCount {
                let amp = CGFloat(data[i])
                let barWidth = max(2, amp * size.width)
                let y = CGFloat(i) * (barHeight + 2)
                let x: CGFloat = mirrored ? (size.width - barWidth) : 0

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1)
                context.fill(path, with: .color(color.opacity(0.7)))
            }
        }
    }
}
