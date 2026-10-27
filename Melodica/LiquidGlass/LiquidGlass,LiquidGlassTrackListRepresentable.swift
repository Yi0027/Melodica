// Views/LiquidGlass/LiquidGlassTrackListRepresentable.swift
import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct LiquidGlassTrackListRepresentable: View {
    let tracks: [Track]
    let rowHeight: CGFloat
    let scrollKey: String?
    let scrollToTopTrigger: AnyHashable?
    let scrollToID: Track.ID?
    let highlightedTrackID: UUID?
    let currentTrackID: UUID?
    let isPlaying: Bool
    let showRating: Bool
    let isFavorite: ((Track) -> Bool)?
    let onToggleFavorite: ((Track) -> Void)?
    let contentInsets: NSEdgeInsets
    let menuProvider: (([Track]) -> NSMenu?)?
    let onDoubleClick: (Track) -> Void

    init(
        tracks: [Track],
        rowHeight: CGFloat = 44,
        scrollKey: String? = nil,
        scrollToTopTrigger: AnyHashable? = nil,
        scrollToID: Track.ID? = nil,
        highlightedTrackID: UUID? = nil,
        currentTrackID: UUID? = nil,
        isPlaying: Bool = false,
        showRating: Bool = false,
        isFavorite: ((Track) -> Bool)? = nil,
        onToggleFavorite: ((Track) -> Void)? = nil,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 80, left: 0, bottom: 80, right: 0),
        menuProvider: (([Track]) -> NSMenu?)? = nil,
        onDoubleClick: @escaping (Track) -> Void
    ) {
        self.tracks = tracks
        self.rowHeight = rowHeight
        self.scrollKey = scrollKey
        self.scrollToTopTrigger = scrollToTopTrigger
        self.scrollToID = scrollToID
        self.highlightedTrackID = highlightedTrackID
        self.currentTrackID = currentTrackID
        self.isPlaying = isPlaying
        self.showRating = showRating
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
        self.contentInsets = contentInsets
        self.menuProvider = menuProvider
        self.onDoubleClick = onDoubleClick
    }

    var body: some View {
        TrackListRepresentable(
            tracks: tracks,
            rowHeight: rowHeight,
            scrollKey: scrollKey,
            scrollToTopTrigger: scrollToTopTrigger,
            scrollToID: scrollToID,
            highlightedTrackID: highlightedTrackID,
            currentTrackID: currentTrackID,
            contentInsets: contentInsets,
            menuProvider: menuProvider,
            onDoubleClick: onDoubleClick,
            makeCell: { tableView, row, track in
                let cell = (tableView.makeView(
                    withIdentifier: LiquidGlassAppKitTrackRowCell.reuseIdentifier,
                    owner: nil
                ) as? LiquidGlassAppKitTrackRowCell) ?? {
                    let c = LiquidGlassAppKitTrackRowCell()
                    c.identifier = LiquidGlassAppKitTrackRowCell.reuseIdentifier
                    return c
                }()
                let isFav = isFavorite?(track) ?? false
                cell.configure(
                    track: track,
                    isCurrent: track.id == currentTrackID,
                    isPlaying: isPlaying,
                    isEven: row % 2 == 0,
                    isFavorite: isFav,
                    showRating: showRating,
                    onFavorite: onToggleFavorite != nil ? { onToggleFavorite?(track) } : nil
                )
                return cell
            },
            updateCell: { cell, track, row in
                if let c = cell as? LiquidGlassAppKitTrackRowCell {
                    let isFav = isFavorite?(track) ?? false
                    c.configure(
                        track: track,
                        isCurrent: track.id == currentTrackID,
                        isPlaying: isPlaying,
                        isEven: row % 2 == 0,
                        isFavorite: isFav,
                        showRating: showRating,
                        onFavorite: onToggleFavorite != nil ? { onToggleFavorite?(track) } : nil
                    )
                }
            }
        )
    }
}
