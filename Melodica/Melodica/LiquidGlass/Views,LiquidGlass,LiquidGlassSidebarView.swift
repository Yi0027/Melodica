// Views,LiquidGlass,LiquidGlassSidebarView.swift

import SwiftUI

@available(macOS 26.0, *)
struct LiquidGlassSidebarView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @Binding var selectedTrackID: UUID?
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var selectedAlbum: String?
    @Binding var selectedPlaylist: Int?
    @Binding var selectedSmartPlaylistID: UUID?
    @Binding var selectedArtist: String?
    @Binding var selectedGenre: String?
    @Binding var selectedCUEAlbum: CUEAlbum?

    @Binding var showFavoritesOnly: Bool

    private var visibleSortFields: [Track.SortField] {
        Track.SortField.allCases.filter { field in
            switch field {
            case .cue:
                return !libraryVM.cueAlbums.isEmpty
            case .playlists:
                return !libraryVM.playlists.isEmpty
            case .smart:
                return true
            case .rating:
                return libraryVM.tracks.contains { ($0.rating ?? 0) > 0 }
            default:
                return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 40)

            VStack(spacing: 2) {
                ForEach(visibleSortFields, id: \.self) { field in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            libraryVM.sortField = field
                            selectedAlbum = nil
                            selectedPlaylist = nil
                            selectedSmartPlaylistID = nil
                            showFavoritesOnly = false
                            selectedArtist = nil
                            selectedGenre = nil
                            selectedCUEAlbum = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: iconForSortField(field))
                                .font(.system(size: 11))
                                .frame(width: 16)
                            Text(LocalizedStringKey(field.localizedKey))
                                .font(.system(size: 11, weight: libraryVM.sortField == field && !showFavoritesOnly ? .semibold : .regular))
                        }
                        .foregroundColor(libraryVM.sortField == field && !showFavoritesOnly ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if !playerVM.favorites.isEmpty || !playerVM.missingFavorites.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showFavoritesOnly.toggle()
                            selectedAlbum = nil
                            selectedPlaylist = nil
                            selectedSmartPlaylistID = nil
                            selectedArtist = nil
                            selectedGenre = nil
                            selectedCUEAlbum = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .frame(width: 16)
                            Text(LocalizedStringKey("favorites"))
                                .font(.system(size: 11, weight: showFavoritesOnly ? .semibold : .regular))
                        }
                        .foregroundColor(showFavoritesOnly ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .glassEffect(in: .rect(cornerRadius: 15))
    }

    private func iconForSortField(_ field: Track.SortField) -> String {
        switch field {
        case .title: return "textformat"
        case .artist: return "person"
        case .album: return "rectangle.stack"
        case .genre: return "tag"
        case .year: return "calendar"
        case .rating: return "star"
        case .duration: return "clock"
        case .playlists: return "music.note.list"
        case .smart: return "sparkles"
        case .cue: return "list.number"
        }
    }
}
