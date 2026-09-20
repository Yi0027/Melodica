// Views/TrackContextMenuBuilder.swift
import AppKit

// MARK: - ClosureMenuItem

/// NSMenuItem с замыканием вместо target/action.
/// Одинаково используется и в обычной теме, и в LiquidGlass.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.handler = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func invoke() {
        MainActor.assumeIsolated { handler() }
    }
}

/// Удобный хелпер: пункт меню с иконкой и замыканием.
func closureItem(
    title: String,
    systemImage: String,
    action: @escaping () -> Void
) -> NSMenuItem {
    let item = ClosureMenuItem(title: title, action: action)
    if let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
        item.image = img
    }
    return item
}

// MARK: - TrackContextMenuBuilder

/// Единый билдер правого меню для списка треков.
/// Работает как с одиночным, так и с множественным выделением.
///
/// Использование (пример для обычной темы):
/// ```
/// TrackContextMenuBuilder.build(
///     tracks: tracks,
///     libraryVM: libraryVM,
///     playerVM: playerVM,
///     onRemoveFromPlaylist: { tracks in ... },   // nil — пункт скрыт
///     onShowInAlbum: { track in ... }            // nil / multi — пункт скрыт
/// )
/// ```
enum TrackContextMenuBuilder {

    static func build(
        tracks: [Track],
        libraryVM: LibraryViewModel,
        playerVM: PlayerViewModel,
        onRemoveFromPlaylist: (([Track]) -> Void)? = nil,
        onShowInAlbum: ((Track) -> Void)? = nil
    ) -> NSMenu {
        let menu = NSMenu()
        guard !tracks.isEmpty else { return menu }
        let isMulti = tracks.count > 1
        let hasCue = tracks.contains { $0.cueStartTime != nil }

        // 1. Показать в альбоме — только одиночный и не cue
        if !isMulti, !hasCue, let track = tracks.first, let onShowInAlbum {
            menu.addItem(closureItem(
                title: NSLocalizedString("show_in_album", comment: ""),
                systemImage: "rectangle.stack"
            ) {
                onShowInAlbum(track)
            })
            menu.addItem(.separator())
        }

        // 2. Удалить из плейлиста (если контекст плейлиста передан)
        if let onRemoveFromPlaylist {
            menu.addItem(closureItem(
                title: NSLocalizedString("remove_from_playlist", comment: ""),
                systemImage: "minus.circle"
            ) {
                onRemoveFromPlaylist(tracks)
            })
        }

        // 3. Избранное
        addFavoriteItem(to: menu, tracks: tracks, playerVM: playerVM)

        // 4. Рейтинг — не поддерживается для cue (рейтинг пишется в тег файла,
        //    а у cue один файл на весь альбом).
        if !hasCue {
            addRatingItem(to: menu, tracks: tracks, libraryVM: libraryVM)
        }

        // 5. Очередь
        addQueueItem(to: menu, tracks: tracks, playerVM: playerVM)

        // 6. Добавить в плейлист — не поддерживается для cue (экспорт в m3u
        //    ссылается на файл целиком, а не на фрагмент).
        if !hasCue {
            menu.addItem(.separator())
            addPlaylistItem(to: menu, tracks: tracks, libraryVM: libraryVM)
        }

        menu.addItem(.separator())

        // 7. Показать в Finder — все файлы выделения
        menu.addItem(closureItem(
            title: NSLocalizedString("show_in_finder", comment: ""),
            systemImage: "folder"
        ) {
            NSWorkspace.shared.activateFileViewerSelecting(tracks.map(\.url))
        })

        // 8. Копировать название — все названия через перевод строки
        menu.addItem(closureItem(
            title: NSLocalizedString("copy_title", comment: ""),
            systemImage: "doc.on.doc"
        ) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                tracks.map(\.title).joined(separator: "\n"),
                forType: .string
            )
        })

        return menu
    }

    // MARK: - Favorites

    private static func addFavoriteItem(
        to menu: NSMenu,
        tracks: [Track],
        playerVM: PlayerViewModel
    ) {
        let states = tracks.map { playerVM.isFavorite($0) }
        let allFav  = states.allSatisfy { $0 }
        let noneFav = states.allSatisfy { !$0 }

        if allFav {
            menu.addItem(closureItem(
                title: NSLocalizedString("remove_from_favorites", comment: ""),
                systemImage: "star.slash"
            ) {
                tracks.forEach { playerVM.toggleFavorite($0) }
            })
        } else if noneFav {
            menu.addItem(closureItem(
                title: NSLocalizedString("add_to_favorites", comment: ""),
                systemImage: "star"
            ) {
                tracks.forEach { playerVM.toggleFavorite($0) }
            })
        } else {
            // Смешанное состояние → подменю с двумя действиями
            let root = NSMenuItem(
                title: NSLocalizedString("favorites", comment: ""),
                action: nil, keyEquivalent: ""
            )
            root.image = NSImage(
                systemSymbolName: "star.leadinghalf.filled",
                accessibilityDescription: nil
            )
            let sub = NSMenu()
            sub.addItem(closureItem(
                title: NSLocalizedString("add_to_favorites", comment: ""),
                systemImage: "star"
            ) {
                tracks
                    .filter { !playerVM.isFavorite($0) }
                    .forEach { playerVM.toggleFavorite($0) }
            })
            sub.addItem(closureItem(
                title: NSLocalizedString("remove_from_favorites", comment: ""),
                systemImage: "star.slash"
            ) {
                tracks
                    .filter { playerVM.isFavorite($0) }
                    .forEach { playerVM.toggleFavorite($0) }
            })
            root.submenu = sub
            menu.addItem(root)
        }
    }

    // MARK: - Rating

    private static func addRatingItem(
        to menu: NSMenu,
        tracks: [Track],
        libraryVM: LibraryViewModel
    ) {
        let root = NSMenuItem(
            title: NSLocalizedString("rating", comment: ""),
            action: nil, keyEquivalent: ""
        )
        root.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        let sub = NSMenu()

        let anyRated = tracks.contains { ($0.rating ?? 0) > 0 }
        if anyRated {
            sub.addItem(closureItem(
                title: NSLocalizedString("clear_rating", comment: ""),
                systemImage: "xmark.circle"
            ) {
                tracks.forEach { libraryVM.setRating(nil, for: $0) }
            })
            sub.addItem(.separator())
        }

        for stars in 1...5 {
            sub.addItem(closureItem(
                title: String(repeating: "★", count: stars),
                systemImage: "star.fill"
            ) {
                tracks.forEach { libraryVM.setRating(stars, for: $0) }
            })
        }
        root.submenu = sub
        menu.addItem(root)
    }

    // MARK: - Queue

    private static func addQueueItem(
        to menu: NSMenu,
        tracks: [Track],
        playerVM: PlayerViewModel
    ) {
        let states = tracks.map { track in
            playerVM.queue.contains(where: { $0.id == track.id })
        }
        let allIn  = states.allSatisfy { $0 }
        let noneIn = states.allSatisfy { !$0 }

        if allIn {
            menu.addItem(closureItem(
                title: NSLocalizedString("remove_from_queue", comment: ""),
                systemImage: "minus.circle"
            ) {
                tracks.forEach { playerVM.removeFromQueue($0) }
            })
        } else if noneIn {
            menu.addItem(closureItem(
                title: NSLocalizedString("add_to_queue", comment: ""),
                systemImage: "plus.circle"
            ) {
                tracks.forEach { playerVM.addToQueue($0) }
            })
        } else {
            let root = NSMenuItem(
                title: NSLocalizedString("queue", comment: ""),
                action: nil, keyEquivalent: ""
            )
            root.image = NSImage(
                systemSymbolName: "text.badge.plus",
                accessibilityDescription: nil
            )
            let sub = NSMenu()
            sub.addItem(closureItem(
                title: NSLocalizedString("add_to_queue", comment: ""),
                systemImage: "plus.circle"
            ) {
                tracks
                    .filter { t in !playerVM.queue.contains(where: { $0.id == t.id }) }
                    .forEach { playerVM.addToQueue($0) }
            })
            sub.addItem(closureItem(
                title: NSLocalizedString("remove_from_queue", comment: ""),
                systemImage: "minus.circle"
            ) {
                tracks
                    .filter { t in playerVM.queue.contains(where: { $0.id == t.id }) }
                    .forEach { playerVM.removeFromQueue($0) }
            })
            root.submenu = sub
            menu.addItem(root)
        }
    }

    // MARK: - Playlist

    private static func addPlaylistItem(
        to menu: NSMenu,
        tracks: [Track],
        libraryVM: LibraryViewModel
    ) {
        let root = NSMenuItem(
            title: NSLocalizedString("add_to_playlist", comment: ""),
            action: nil, keyEquivalent: ""
        )
        let sub = NSMenu()

        sub.addItem(closureItem(
            title: NSLocalizedString("new_playlist", comment: ""),
            systemImage: "plus"
        ) {
            showNewPlaylistDialog(for: tracks, libraryVM: libraryVM)
        })

        if !libraryVM.playlists.isEmpty {
            sub.addItem(.separator())
            for (idx, pl) in libraryVM.playlists.enumerated() {
                sub.addItem(closureItem(
                    title: pl.name,
                    systemImage: "music.note.list"
                ) {
                    libraryVM.playlists[idx].tracks.append(contentsOf: tracks)
                    libraryVM.savePlaylistsToCache()
                })
            }
        }

        root.submenu = sub
        menu.addItem(root)
    }

    private static func showNewPlaylistDialog(
        for tracks: [Track],
        libraryVM: LibraryViewModel
    ) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("new_playlist_title", comment: "")
        alert.informativeText = NSLocalizedString("new_playlist_desc", comment: "")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = NSLocalizedString("playlist_name_placeholder", comment: "")
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("create", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("cancel", comment: ""))
        alert.window.initialFirstResponder = textField
        if alert.runModal() == .alertFirstButtonReturn {
            var name = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { name = "Playlist \(libraryVM.playlists.count + 1)" }
            libraryVM.playlists.append((name, tracks))
            libraryVM.savePlaylistsToCache()
        }
    }
}
