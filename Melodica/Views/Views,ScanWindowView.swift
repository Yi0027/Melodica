// Views/ScanWindowView.swift
import SwiftUI

// MARK: - Theme Router

struct ScanWindowView: View {
    @Bindable var session: ScanSession
    let onClose: () -> Void

    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        if settings.activeTheme == "liquid_glass" {
            if #available(macOS 26.0, *) {
                LiquidGlassScanWindowView(session: session, onClose: onClose)
            } else {
                StandardScanWindowView(session: session, onClose: onClose)
            }
        } else {
            StandardScanWindowView(session: session, onClose: onClose)
        }
    }
}

// MARK: - Standard Theme Scanning View

struct StandardScanWindowView: View {
    @Bindable var session: ScanSession
    let onClose: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @State private var headerIsOffscreen: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    header
                    Divider()
                        .background(Color.white.opacity(0.1))
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.items.enumerated()), id: \.element.id) { idx, item in
                            StandardScanItemRow(item: item, index: idx)
                            Divider()
                                .background(Color.white.opacity(0.06))
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

            // Custom close button
            StandardCloseButton(action: onClose)
                .padding(.top, 14)
                .padding(.leading, 14)

            // Compact header badge
            if headerIsOffscreen && session.state != .idle {
                StandardCompactHeaderBadge(
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
        .ignoresSafeArea()
        .frame(minWidth: 480, idealWidth: 600, minHeight: 560, idealHeight: 600)
        .background(Color.darkBg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 44)

            StandardScanRing(
                progress: session.currentTrackFraction,
                finished: session.state == .finished,
                stage: session.state == .scanning ? session.currentStageLabel : nil,
                completed: session.completedCount,
                total: session.total
            )
            .frame(width: 200, height: 200)

            Text(queueLabel)
                .font(.system(size: 13))
                .foregroundColor(Color.textMuted)
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

// MARK: - Standard Close Button

struct StandardCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(hovered ? Color.textMain : Color.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.darkSurface)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(hovered ? 0.2 : 0.1), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .help(NSLocalizedString("close", comment: ""))
    }
}

// MARK: - Standard Scan Ring

struct StandardScanRing: View {
    let progress: Double
    let finished: Bool
    let stage: String?
    let completed: Int
    let total: Int

    private let animationDuration: Double = 1.4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.darkSurface, lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    finished
                        ? Color(nsColor: .systemGreen)
                        : Color.accent,
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
                        .foregroundColor(Color.textMuted)
                } else {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Color.textMain)
                        .contentTransition(.numericText(value: progress))
                        .animation(.linear(duration: animationDuration), value: progress)

                    if let stage, !stage.isEmpty {
                        Text(stage)
                            .font(.system(size: 11))
                            .foregroundColor(Color.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 140)
                    }
                }

                Text("\(completed) / \(total)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.textMuted.opacity(0.6))
            }
        }
        .padding(8)
    }
}

// MARK: - Standard Compact Header Badge

struct StandardCompactHeaderBadge: View {
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
                .foregroundColor(Color.textMain)
                .contentTransition(.numericText(value: progress))
                .animation(.linear(duration: animationDuration), value: progress)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(
                        finished
                            ? Color(nsColor: .systemGreen)
                            : Color.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: animationDuration), value: progress)
            }
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.darkSurface)
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Standard Item Row

struct StandardScanItemRow: View {
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
                StandardScanItemDetail(result: result)
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
                    .foregroundColor(Color.textMain)
                    .lineLimit(1)
                Text(item.track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(Color.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(trailingText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.textMuted)
                .lineLimit(1)

            if item.result != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.textMuted.opacity(0.5))
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
                ? Color.darkSurface.opacity(0.6)
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
                .foregroundColor(Color.textMuted.opacity(0.4))
        case .scanning:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .tint(Color.accent)
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
        case .notAssessed:           return Color.textMuted
        }
    }
}

// MARK: - Standard Item Detail

struct StandardScanItemDetail: View {
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
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)
                Text(NSLocalizedString("scan_reasons", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.textMuted)
                ForEach(result.reasons.prefix(8), id: \.self) { reason in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: 11))
                            .foregroundColor(Color.textMuted)
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundColor(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.darkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(size: 11))
                .foregroundColor(Color.textMuted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(Color.textMain)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
