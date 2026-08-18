// Views,LiquidGlass,LiquidGlassSpectrumView.swift
import SwiftUI

struct LiquidGlassSpectrumView: View {
    let data: [Float]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<data.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3, height: max(4, CGFloat(data[i]) * 30))
            }
        }
        .animation(.easeOut(duration: 0.05), value: data)
    }
}

struct LiquidGlassRotatedSpectrumView: View {
    let data: [Float]
    let mirrored: Bool
    var color: Color = .white
    
    var body: some View {
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
        .animation(.easeOut(duration: 0.05), value: data)
    }
}
