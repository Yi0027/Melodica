// Views,LiquidGlass,LiquidGlassWaveformView.swift
import SwiftUI

struct LiquidGlassWaveformView: View {
    let data: [Float]
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard data.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(data.count - 1)
                let midY = geo.size.height / 2
                
                path.move(to: CGPoint(x: 0, y: midY - CGFloat(data[0]) * midY))
                for i in 1..<data.count {
                    let x = CGFloat(i) * stepX
                    let y = midY - CGFloat(data[i]) * midY
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
            .animation(.easeOut(duration: 0.05), value: data)
        }
    }
}

struct LiquidGlassWaveformProgressView: View {
    let data: [Float]
    let progress: Double
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (Double) -> Void
    var accentColor: Color = Color.accentColor
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = isHovering ? 24 : 20
                
                ZStack(alignment: .leading) {
                    LiquidGlassWaveformLine(data: data, color: Color.primary.opacity(0.15), fill: true)
                        .frame(width: width, height: height)
                    
                    LiquidGlassWaveformLine(data: data, color: accentColor, fill: true)
                        .frame(width: width, height: height)
                        .mask(
                            HStack(spacing: 0) {
                                Color.black
                                    .frame(width: max(0, width * CGFloat(progress)))
                                Color.clear
                            }
                        )
                }
                .frame(height: height)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onSeek(value.location.x / width)
                        }
                )
            }
            .frame(height: 24)
        }
    }
}

struct LiquidGlassWaveformLine: View {
    let data: [Float]
    let color: Color
    var fill: Bool = false
    
    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }
            
            var path = Path()
            let stepX = size.width / CGFloat(data.count - 1)
            let midY = size.height / 2
            
            path.move(to: CGPoint(x: 0, y: midY - CGFloat(data[0]) * midY))
            for i in 1..<data.count {
                let x = CGFloat(i) * stepX
                let y = midY - CGFloat(data[i]) * midY
                path.addLine(to: CGPoint(x: x, y: y))
            }
            
            if fill {
                path.addLine(to: CGPoint(x: size.width, y: midY))
                path.addLine(to: CGPoint(x: 0, y: midY))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.3)))
            }
            
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
