// Views,FolderManagerView.swift
import SwiftUI

struct FolderManagerView: View {
    let folders: [(url: URL, isVisible: Bool)]
    let onRemove: (URL) -> Void
    let onToggle: ((URL) -> Void)?
    let onAdd: () -> Void
    let onRescan: () -> Void
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Text(LocalizedStringKey("folder_manager"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textMain)
                .padding(12)
            
            Divider().background(Color.white.opacity(0.1))
            
            if folders.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24))
                        .foregroundColor(.textMuted.opacity(0.3))
                    Text(LocalizedStringKey("no_folders"))
                        .font(.system(size: 12))
                        .foregroundColor(.textMuted.opacity(0.5))
                    Spacer()
                }
            } else {
                List {
                    ForEach(folders, id: \.url) { folder in
                        HStack {
                            Button(action: { onToggle?(folder.url) }) {
                                Image(systemName: folder.isVisible ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(folder.isVisible ? .accent : .textMuted.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accent)
                            Text(folder.url.lastPathComponent)
                                .font(.system(size: 12))
                                .foregroundColor(.textMain)
                                .lineLimit(1)
                            Spacer()
                            Button(action: { onRemove(folder.url) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textMuted.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Кнопки на одном уровне
            HStack(spacing: 0) {
                Button(action: onAdd) {
                    HStack {
                        Image(systemName: "externaldrive.badge.plus")
                        Text(LocalizedStringKey("add_folder"))
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 20)
                
                Button(action: onRescan) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(LocalizedStringKey("rescan"))
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Скорость создания миниатюр
            VStack(spacing: 8) {
                Text(LocalizedStringKey("thumbnail_speed"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMain)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                HStack(spacing: 4) {
                    ForEach([0, 0.02, 0.05, 0.1, 0.15, 0.2], id: \.self) { speed in
                        Button(action: {
                            SettingsManager.shared.setThumbnailCreationSpeed(speed)
                        }) {
                            Text("\(Int(speed * 1000))")
                                .font(.system(size: 11, weight: settings.thumbnailCreationSpeed == speed ? .bold : .regular))
                                .foregroundColor(settings.thumbnailCreationSpeed == speed ? .white : .textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(settings.thumbnailCreationSpeed == speed ? Color.accent : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                
                Text(LocalizedStringKey("thumbnail_speed_hint"))
                    .font(.system(size: 9))
                    .foregroundColor(.textMuted.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 8)
        }
        .background(Color.darkBg)
    }
}
