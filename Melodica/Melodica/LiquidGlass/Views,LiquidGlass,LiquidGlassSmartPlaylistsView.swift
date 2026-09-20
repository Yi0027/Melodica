// Views,LiquidGlass,LiquidGlassSmartPlaylistsView.swift
import SwiftUI
import UniformTypeIdentifiers
import Combine

@available(macOS 26.0, *)
struct LiquidGlassSmartPlaylistsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var vm: SmartPlaylistViewModel

    @Binding var selectedSmartPlaylistID: UUID?

    @State private var showingEditor = false
    @State private var editingPlaylist: SmartPlaylist?

    @State private var presetPickerType: UserArtworkManager.ArtworkType?
    @ObservedObject private var settings = SettingsManager.shared
    @State private var artworkVersion = 0

    var body: some View {
        Group {
            if let id = selectedSmartPlaylistID,
               let playlist = vm.playlists.first(where: { $0.id == id }) {
                smartPlaylistDetail(playlist)
            } else {
                smartPlaylistGrid
            }
        }
        .sheet(isPresented: $showingEditor) {
            LiquidGlassSmartPlaylistEditorView(vm: vm, playlist: editingPlaylist)
        }
        .sheet(item: $presetPickerType) { type in
            LiquidGlassArtworkPresetPickerView(type: type)
                .onDisappear {
                    artworkVersion += 1
                }
        }
    }

    // MARK: - Grid

    private var smartPlaylistGrid: some View {
        let cellSize = settings.albumGridSize
        let cellW = cellSize
        let cellH = cellSize + 62
        let maxPixel = cellSize * 2

        // Виртуальный элемент для кнопки создания
        let items: [SmartPlaylist?] = vm.playlists.map { Optional($0) } + [nil]

        return LiquidGlassAppKitGridView(
            items: items,
            itemSize: CGSize(width: cellW, height: cellH),
            itemSpacing: 12,
            sectionInset: NSEdgeInsets(top: 40, left: 12, bottom: 80, right: 12),
            scrollKey: "liquid_smart_grid",
            reloadToken: artworkVersion,
            identifier: { item in
                if let playlist = item {
                    return playlist.id.uuidString
                } else {
                    return "create_smart_playlist"
                }
            },
            onSelect: { item in
                if let playlist = item {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedSmartPlaylistID = playlist.id
                    }
                } else {
                    editingPlaylist = nil
                    showingEditor = true
                }
            },
            contextMenu: { item in
                guard let playlist = item else { return nil }

                let menu = NSMenu()

                menu.addItem(closureItem(
                    title: NSLocalizedString("edit", comment: ""),
                    systemImage: "pencil"
                ) {
                    editingPlaylist = playlist
                    showingEditor = true
                })

                menu.addItem(closureItem(
                    title: NSLocalizedString("add_artwork", comment: ""),
                    systemImage: "photo"
                ) {
                    chooseArtwork(for: .smartPlaylist(playlist.id))
                })

                menu.addItem(closureItem(
                    title: NSLocalizedString("choose_from_presets", comment: ""),
                    systemImage: "photo.on.rectangle"
                ) {
                    presetPickerType = .smartPlaylist(playlist.id)
                })

                if UserArtworkManager.load(for: .smartPlaylist(playlist.id)) != nil {
                    menu.addItem(closureItem(
                        title: NSLocalizedString("remove_custom_artwork", comment: ""),
                        systemImage: "trash"
                    ) {
                        UserArtworkManager.delete(for: .smartPlaylist(playlist.id))
                        artworkVersion += 1
                    })
                }

                menu.addItem(.separator())

                let exportRoot = NSMenuItem(
                    title: NSLocalizedString("export_playlist", comment: ""),
                    action: nil,
                    keyEquivalent: ""
                )
                let exportSub = NSMenu()
                exportSub.addItem(closureItem(
                    title: NSLocalizedString("export_absolute", comment: ""),
                    systemImage: "arrow.up.doc"
                ) {
                    exportSmartPlaylist(playlist, useAbsolutePaths: true)
                })
                exportSub.addItem(closureItem(
                    title: NSLocalizedString("export_relative", comment: ""),
                    systemImage: "arrow.up.doc"
                ) {
                    exportSmartPlaylist(playlist, useAbsolutePaths: false)
                })
                exportRoot.submenu = exportSub
                menu.addItem(exportRoot)

                menu.addItem(.separator())

                menu.addItem(closureItem(
                    title: NSLocalizedString("delete_playlist", comment: ""),
                    systemImage: "trash"
                ) {
                    vm.delete(playlist)
                })

                return menu
            },
            configure: { cell, item in
                if let playlist = item {
                    let count = smartTracksCount(for: playlist)
                    let art = UserArtworkManager.imageURL(for: .smartPlaylist(playlist.id))

                    cell.configure(
                        title: playlist.name,
                        subtitle: "\(playlist.rules.count) \(NSLocalizedString("rules", comment: ""))",
                        tertiary: "\(count) \(NSLocalizedString("tracks", comment: ""))",
                        placeholderSymbol: playlist.icon,
                        artworkURL: art,
                        maxPixel: maxPixel
                    )
                } else {
                    cell.configure(
                        title: NSLocalizedString("create", comment: ""),
                        subtitle: NSLocalizedString("smart_playlist", comment: ""),
                        tertiary: " ",
                        placeholderSymbol: "plus",
                        artworkURL: nil,
                        maxPixel: maxPixel
                    )
                }
            }
        )
    }

    // MARK: - Detail

    private func smartPlaylistDetail(_ playlist: SmartPlaylist) -> some View {
        let tracks = smartTracks(for: playlist)

        return LiquidGlassTrackListRepresentable(
            tracks: tracks,
            rowHeight: 44,
            scrollKey: "liquid_smart_detail_\(playlist.id.uuidString)",
            currentTrackID: playerVM.currentTrack?.id,
            isPlaying: playerVM.isPlaying,
            showRating: false,
            contentInsets: NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
            menuProvider: { tracks in
                self.buildTrackMenu(tracks: tracks)
            },
            onDoubleClick: { track in
                playerVM.playbackMode = .playlist(tracks, name: playlist.name)
                playerVM.playerTracks = tracks
                playerVM.play(track) {
                    playerVM.playNextTrack()
                }
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Track context menu

    private func buildTrackMenu(track: Track) -> NSMenu {
        buildTrackMenu(tracks: [track])
    }

    private func buildTrackMenu(tracks: [Track]) -> NSMenu {
        TrackContextMenuBuilder.build(
            tracks: tracks,
            libraryVM: libraryVM,
            playerVM: playerVM,
            onRemoveFromPlaylist: nil,
            onShowInAlbum: nil   // у Smart Playlists «Show in Album» изначально не было
        )
    }

    // MARK: - Helpers

    private func chooseArtwork(for type: UserArtworkManager.ArtworkType) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK,
               let url = panel.url,
               let image = NSImage(contentsOf: url) {
                UserArtworkManager.save(image, for: type)
                artworkVersion += 1
            }
        }
    }

    private func favoriteURLs() -> Set<String> {
        Set(playerVM.favorites.map { $0.url.standardizedFileURL.path })
    }

    private func smartTracks(for playlist: SmartPlaylist) -> [Track] {
        vm.tracks(for: playlist, library: libraryVM.tracks, favoriteURLs: favoriteURLs())
    }

    private func smartTracksCount(for playlist: SmartPlaylist) -> Int {
        smartTracks(for: playlist).count
    }

    private func exportSmartPlaylist(_ playlist: SmartPlaylist, useAbsolutePaths: Bool) {
        let tracks = smartTracks(for: playlist)
        let panel = NSSavePanel()
        panel.title = NSLocalizedString("export_playlist_title", comment: "")
        panel.nameFieldStringValue = "\(playlist.name).m3u"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                M3UParser.export(
                    playlist: (name: playlist.name, tracks: tracks),
                    to: url,
                    useAbsolutePaths: useAbsolutePaths
                )
            }
        }
    }
}
