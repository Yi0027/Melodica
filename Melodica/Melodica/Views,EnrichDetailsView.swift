// Views,EnrichDetailsView.swift
import SwiftUI

struct EnrichDetailsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var settings = SettingsManager.shared
    
    private var phaseName: String {
        switch libraryVM.enrichPhase {
        case 1: return NSLocalizedString("phase_tags", comment: "")
        case 2: return NSLocalizedString("phase_artworks", comment: "")
        case 3: return NSLocalizedString("phase_thumbnails", comment: "")
        default: return "..."
        }
    }
    
    private var phaseIcon: String {
        switch libraryVM.enrichPhase {
        case 1: return "tag.fill"
        case 2: return "photo.fill"
        case 3: return "photo.stack.fill"
        default: return "hourglass"
        }
    }
    
    private var percentCompleted: Double {
        guard libraryVM.enrichProgress.total > 0 else { return 0 }
        return Double(libraryVM.enrichProgress.current) / Double(libraryVM.enrichProgress.total)
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
                        Text(String(format: NSLocalizedString("phase_format", comment: ""), libraryVM.enrichPhase, libraryVM.folderQueueCount == 0 ? 3 : 2))
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
                    
                    // Очередь папок (компактно)
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
                    
                    // Описание текущей и следующей фазы
                    // Описание фаз
                    VStack(alignment: .leading, spacing: 4) {
                        phaseRow(phase: 1, icon: "tag.fill", title: NSLocalizedString("phase_tags", comment: ""), desc: NSLocalizedString("phase_tags_desc", comment: ""), isActive: libraryVM.enrichPhase == 1)
                        phaseRow(phase: 2, icon: "photo.fill", title: NSLocalizedString("phase_artworks", comment: ""), desc: NSLocalizedString("phase_artworks_desc", comment: ""), isActive: libraryVM.enrichPhase == 2)
                        
                        // Третье поле — только если очередь пуста
                        if libraryVM.folderQueueCount == 0 {
                            phaseRow(phase: 3, icon: "photo.stack.fill", title: NSLocalizedString("phase_thumbnails", comment: ""), desc: NSLocalizedString("phase_thumbnails_desc", comment: ""), isActive: libraryVM.enrichPhase == 3)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(settings.darkSurface.opacity(0.3)))
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 460)
        .background(settings.darkBg)
    }
    
    // MARK: - Helpers
    
    private func iconForPhase(_ phase: Int) -> String {
        switch phase {
        case 1: return "tag.fill"
        case 2: return "photo.fill"
        case 3: return "photo.stack.fill"
        default: return "hourglass"
        }
    }
    
    private func nameForPhase(_ phase: Int) -> String {
        switch phase {
        case 1: return NSLocalizedString("phase_tags", comment: "")
        case 2: return NSLocalizedString("phase_artworks", comment: "")
        case 3: return NSLocalizedString("phase_thumbnails", comment: "")
        default: return "..."
        }
    }
    
    private func phaseDescription(for phase: Int) -> String {
        switch phase {
        case 1: return NSLocalizedString("phase_tags_desc", comment: "")
        case 2: return NSLocalizedString("phase_artworks_desc", comment: "")
        case 3: return NSLocalizedString("phase_thumbnails_desc", comment: "")
        default: return ""
        }
    }
    
    private func phaseRow(phase: Int, icon: String, title: String, desc: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(isActive ? settings.accent : settings.textMuted.opacity(0.4))
                .frame(width: 18)
            
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
