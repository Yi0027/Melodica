// Views,LiquidGlass,LiquidGlassEnrichDetailsView.swift
import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassEnrichDetailsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var settings = SettingsManager.shared

    private var phaseName: String {
        switch libraryVM.enrichPhase {
        case 1: return NSLocalizedString("phase_scanning", comment: "")
        case 2: return NSLocalizedString("phase_thumbnails", comment: "")
        case 3: return NSLocalizedString("phase_waveforms", comment: "")
        default: return "..."
        }
    }

    private var phaseIcon: String {
        switch libraryVM.enrichPhase {
        case 1: return "doc.text.magnifyingglass"
        case 2: return "photo.stack.fill"
        case 3: return "waveform.path"
        default: return "hourglass"
        }
    }

    private var percentCompleted: Double {
        guard libraryVM.enrichProgress.total > 0 else { return 0 }
        return Double(libraryVM.enrichProgress.current) / Double(libraryVM.enrichProgress.total)
    }

    private var maxPhases: Int {
        SettingsManager.shared.waveformCacheMode == "active" ? 3 : 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.primary.opacity(0.1))

            ScrollView {
                VStack(spacing: 14) {
                    phaseBadge
                    progressSection
                    timeSection

                    if libraryVM.folderQueueCount > 0 {
                        queueInfo
                    }

                    phasesList
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: libraryVM.folderQueueCount > 0 ? 420 : 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: phaseIcon)
                .font(.system(size: 13))
                .foregroundColor(Color.accentColor)

            Text(LocalizedStringKey("enrichment_progress"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(16)
    }

    private var phaseBadge: some View {
        VStack(spacing: 4) {
            Text(String(format: NSLocalizedString("phase_format", comment: ""), libraryVM.enrichPhase, maxPhases))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.accentColor)

            Text(phaseName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * percentCompleted, height: 8)
                        .animation(.easeOut(duration: 0.3), value: percentCompleted)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(libraryVM.enrichProgress.current) / \(libraryVM.enrichProgress.total)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%.0f%%", percentCompleted * 100))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }

    private var timeSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))

                Text(LocalizedStringKey("estimated_time"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Text(libraryVM.enrichFormattedTime)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var queueInfo: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 9))
                .foregroundColor(Color.accentColor.opacity(0.6))

            Text(String(format: NSLocalizedString("queue_folders_count", comment: ""), libraryVM.folderQueueCount))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var phasesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            phaseRow(
                phase: 1,
                icon: "doc.text.magnifyingglass",
                title: NSLocalizedString("phase_scanning", comment: ""),
                desc: NSLocalizedString("phase_scanning_desc", comment: ""),
                isActive: libraryVM.enrichPhase == 1,
                isDone: libraryVM.enrichPhase > 1
            )

            phaseRow(
                phase: 2,
                icon: "photo.stack.fill",
                title: NSLocalizedString("phase_thumbnails", comment: ""),
                desc: NSLocalizedString("phase_thumbnails_desc", comment: ""),
                isActive: libraryVM.enrichPhase == 2,
                isDone: libraryVM.enrichPhase > 2
            )

            if SettingsManager.shared.waveformCacheMode == "active" {
                phaseRow(
                    phase: 3,
                    icon: "waveform.path",
                    title: NSLocalizedString("phase_waveforms", comment: ""),
                    desc: NSLocalizedString("phase_waveforms_desc", comment: ""),
                    isActive: libraryVM.enrichPhase == 3,
                    isDone: false
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func phaseRow(phase: Int, icon: String, title: String, desc: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.accentColor.opacity(0.3) : (isActive ? Color.accentColor.opacity(0.2) : Color.clear))
                    .frame(width: 22, height: 22)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.accentColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? Color.accentColor : .secondary.opacity(0.4))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary.opacity(0.6))

                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.4))
            }

            Spacer()
        }
    }
}
