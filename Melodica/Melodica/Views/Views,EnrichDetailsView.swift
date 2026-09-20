// Views,EnrichDetailsView.swift
import SwiftUI

struct EnrichDetailsView: View {
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
        var count = 2 // scan, thumbnails

        if SettingsManager.shared.waveformCacheMode == "active" {
            count = 3 // + waveforms
        }

        return count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: phaseIcon)
                    .font(.system(size: 13))
                    .foregroundColor(settings.accent)

                Text(LocalizedStringKey("enrichment_progress"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(settings.textMain)

                Spacer()
            }
            .padding(16)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(String(format: NSLocalizedString("phase_format", comment: ""), libraryVM.enrichPhase, maxPhases))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(settings.accent)

                        Text(phaseName)
                            .font(.system(size: 12))
                            .foregroundColor(settings.textMuted)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(RoundedRectangle(cornerRadius: 10).fill(settings.darkSurface))

                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(settings.darkSurface)
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(settings.accent)
                                    .frame(width: geo.size.width * percentCompleted, height: 8)
                                    .animation(.easeOut(duration: 0.3), value: percentCompleted)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("\(libraryVM.enrichProgress.current) / \(libraryVM.enrichProgress.total)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(settings.textMuted)

                            Spacer()

                            Text(String(format: "%.0f%%", percentCompleted * 100))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(settings.textMain)
                        }
                    }

                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundColor(settings.textMuted.opacity(0.6))

                            Text(LocalizedStringKey("estimated_time"))
                                .font(.system(size: 11))
                                .foregroundColor(settings.textMuted.opacity(0.6))
                        }

                        Text(libraryVM.enrichFormattedTime)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.textMain)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(settings.darkSurface.opacity(0.5)))

                    if libraryVM.folderQueueCount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 9))
                                .foregroundColor(settings.accent.opacity(0.6))

                            Text(String(format: NSLocalizedString("queue_folders_count", comment: ""), libraryVM.folderQueueCount))
                                .font(.system(size: 10))
                                .foregroundColor(settings.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(settings.darkSurface.opacity(0.4)))
                    }

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
                    .background(RoundedRectangle(cornerRadius: 8).fill(settings.darkSurface.opacity(0.3)))
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: libraryVM.folderQueueCount > 0 ? 420 : 480)
        .background(settings.darkBg)
    }

    private func phaseRow(phase: Int, icon: String, title: String, desc: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? settings.accent.opacity(0.3) : (isActive ? settings.accent.opacity(0.2) : Color.clear))
                    .frame(width: 22, height: 22)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(settings.accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? settings.accent : settings.textMuted.opacity(0.4))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? settings.textMain : settings.textMuted.opacity(0.6))

                Text(desc)
                    .font(.system(size: 9))
                    .foregroundColor(settings.textMuted.opacity(0.4))
            }
        }
    }
}
