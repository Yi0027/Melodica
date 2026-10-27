// LiquidGlass/LiquidGlassScanWindowView.swift
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassScanWindowView: View {
    @Bindable var session: ScanSession
    let onClose: () -> Void

    @State private var headerIsOffscreen: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    header
                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.items.enumerated()), id: \.element.id) { idx, item in
                            LiquidGlassScanItemRow(item: item, index: idx)
                            Divider()
                                .overlay(Color.primary.opacity(0.05))
                        }
                    }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, newOffset in
                let offscreen = newOffset > 20
                if offscreen != headerIsOffscreen {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        headerIsOffscreen = offscreen
                    }
                }
            }

            LiquidGlassCloseButton(action: onClose)
                .padding(.top, 14)
                .padding(.leading, 14)

            if headerIsOffscreen && session.state != .idle {
                LiquidGlassCompactHeaderBadge(
                    progress: session.currentTrackFraction,
                    finished: session.state == .finished,
                    completed: session.completedCount,
                    total: session.total
                )
                .padding(.top, 14)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 480, idealWidth: 600, minHeight: 560, idealHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 44)

            LiquidGlassScanRing(
                progress: session.currentTrackFraction,
                finished: session.state == .finished,
                stage: session.state == .scanning ? session.currentStageLabel : nil,
                completed: session.completedCount,
                total: session.total
            )
            .frame(width: 200, height: 200)

            Text(queueLabel)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .monospacedDigit()

            Spacer().frame(height: 14)
        }
        .frame(maxWidth: .infinity)
    }

    private var queueLabel: String {
        switch session.state {
        case .idle:
            return NSLocalizedString("scan_ready", comment: "")
        case .scanning:
            return String(format: NSLocalizedString("scan_remaining", comment: ""),
                          session.remainingCount, session.total)
        case .finished:
            return String(format: NSLocalizedString("scan_complete", comment: ""),
                          session.total)
        }
    }
}

// MARK: - Liquid Glass Close Button

@available(macOS 26.0, *)
struct LiquidGlassCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(hovered ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(true), in: .circle)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(hovered ? 0.2 : 0.1), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .help(NSLocalizedString("close", comment: ""))
    }
}

// MARK: - Liquid Glass Scan Ring

@available(macOS 26.0, *)
struct LiquidGlassScanRing: View {
    let progress: Double
    let finished: Bool
    let stage: String?
    let completed: Int
    let total: Int

    private let animationDuration: Double = 1.4

    var body: some View {
        ZStack {
            // Liquid Glass background disc
            Circle()
                .glassEffect(in: .circle)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    finished
                        ? Color(nsColor: .systemGreen)
                        : Color.accentColor,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: animationDuration), value: progress)

            VStack(spacing: 4) {
                if finished {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(Color(nsColor: .systemGreen))
                    Text(NSLocalizedString("scan_done_short", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .contentTransition(.numericText(value: progress))
                        .animation(.linear(duration: animationDuration), value: progress)

                    if let stage, !stage.isEmpty {
                        Text(stage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 140)
                    }
                }

                Text("\(completed) / \(total)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(8)
    }
}

// MARK: - Liquid Glass Compact Header Badge

@available(macOS 26.0, *)
struct LiquidGlassCompactHeaderBadge: View {
    let progress: Double
    let finished: Bool
    let completed: Int
    let total: Int

    private let animationDuration: Double = 1.4

    var body: some View {
        HStack(spacing: 8) {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
                .contentTransition(.numericText(value: progress))
                .animation(.linear(duration: animationDuration), value: progress)

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(
                        finished
                            ? Color(nsColor: .systemGreen)
                            : Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: animationDuration), value: progress)
            }
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Liquid Glass Item Row

@available(macOS 26.0, *)
struct LiquidGlassScanItemRow: View {
    let item: ScanSession.Item
    let index: Int

    @State private var expanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard item.result != nil else { return }
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                rowContent
            }
            .buttonStyle(.plain)

            if expanded, let result = item.result {
                LiquidGlassScanItemDetail(result: result)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.track.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(trailingText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            if item.result != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            isHovered
                ? Color.primary.opacity(0.06)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "circle.dashed")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.4))
        case .scanning:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .tint(Color.accentColor)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(nsColor: .systemOrange))
        case .done:
            if let r = item.result {
                Image(systemName: symbol(for: r.verdict))
                    .font(.system(size: 14))
                    .foregroundColor(color(for: r.verdict))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(nsColor: .systemGreen))
            }
        }
    }

    private var trailingText: String {
        if let r = item.result {
            let bitrate = r.declaredKbps.map { "\($0) kbps" } ?? "—"
            return "\(bitrate) · \(r.verdict.localized)"
        }
        if item.status == .scanning {
            return item.stageLabel
        }
        return ""
    }

    private func symbol(for v: VerdictResult) -> String {
        switch v {
        case .authentic:             return "checkmark.circle.fill"
        case .warning:               return "exclamationmark.circle.fill"
        case .suspicious:            return "exclamationmark.triangle.fill"
        case .fakeCertain:           return "xmark.octagon.fill"
        case .suspectedDoubleEncode: return "arrow.triangle.2.circlepath.circle.fill"
        case .notAssessed:           return "questionmark.circle.fill"
        }
    }

    private func color(for v: VerdictResult) -> Color {
        switch v {
        case .authentic:             return Color(nsColor: .systemGreen)
        case .warning:               return Color(nsColor: .systemYellow)
        case .suspicious:            return Color(nsColor: .systemOrange)
        case .fakeCertain:           return Color(nsColor: .systemRed)
        case .suspectedDoubleEncode: return Color(nsColor: .systemOrange)
        case .notAssessed:           return Color(nsColor: .secondaryLabelColor)
        }
    }
}

// MARK: - Liquid Glass Item Detail

@available(macOS 26.0, *)
struct LiquidGlassScanItemDetail: View {
    let result: BitrateAnalyzer.Result

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            detailRow(NSLocalizedString("scan_file", comment: ""),
                      result.track.url.lastPathComponent)
            detailRow(NSLocalizedString("scan_format", comment: ""),
                      result.containerFormat)
            detailRow(NSLocalizedString("scan_sample_rate", comment: ""),
                      "\(result.sampleRate) Hz")
            if let kbps = result.declaredKbps {
                detailRow(NSLocalizedString("scan_declared", comment: ""),
                          "\(kbps) kbps (\(result.declaredSource))")
            }
            if result.effectiveKbps > 0 {
                detailRow(NSLocalizedString("scan_effective", comment: ""),
                          "~\(result.effectiveKbps) kbps")
            }
            if result.cutoffHz > 0 {
                detailRow(NSLocalizedString("scan_cutoff", comment: ""),
                          String(format: "%.1f kHz", result.cutoffHz / 1000.0))
            }
            if !result.evidenceFamilies.isEmpty {
                detailRow(NSLocalizedString("scan_families", comment: ""),
                          result.evidenceFamilies.sorted().joined(separator: ", "))
            }
            detailRow(NSLocalizedString("scan_score", comment: ""),
                      "\(result.score)/86")

            if !result.reasons.isEmpty {
                Divider()
                    .overlay(Color.primary.opacity(0.08))
                    .padding(.vertical, 4)
                Text(NSLocalizedString("scan_reasons", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(result.reasons.prefix(8), id: \.self) { reason in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
