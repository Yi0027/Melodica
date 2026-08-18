// LiquidGlassAlbumCell.swift
import SwiftUI

struct LiquidGlassAlbumCell: View {
    let group: (album: String, artist: String, tracks: [Track], artURL: URL?)
    @ObservedObject private var settings = SettingsManager.shared
    
    private var tileSize: CGFloat { settings.albumGridSize - 10 }
    
    var body: some View {
        VStack(spacing: 4) {
            CachedImage(url: group.tracks.first?.thumbURL(size: "400") ?? group.artURL,
                       size: CGSize(width: tileSize, height: tileSize))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(group.album)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)
            
            Text(group.artist)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)
            
            Text("\(group.tracks.count) \(NSLocalizedString("tracks", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)
        }
    }
}
struct LiquidGlassCUECell: View {
    let album: CUEAlbum
    @ObservedObject private var settings = SettingsManager.shared

    private var tileSize: CGFloat { settings.albumGridSize - 10 }

    var body: some View {
        VStack(spacing: 4) {
            if let artURL = album.albumArtURL {
                CachedImage(url: artURL, size: CGSize(width: tileSize, height: tileSize))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: tileSize, height: tileSize)
                    Image(systemName: "music.note.list")
                        .font(.system(size: tileSize * 0.25))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            Text(album.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text(album.performer)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: tileSize, alignment: .leading)

            Text("\(album.tracks.count) \(NSLocalizedString("tracks", comment: ""))")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(maxWidth: tileSize, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

