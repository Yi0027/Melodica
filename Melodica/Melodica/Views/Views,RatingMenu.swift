// Views,RatingMenu.swift
import SwiftUI

/// Готовое контекстное меню для оценки трека.
/// Использование:
/// ```
/// .contextMenu {
///     TrackRatingMenu(track: track)
///     // ... остальные пункты ...
/// }
/// ```
struct TrackRatingMenu: View {
    let track: Track
    @ObservedObject private var libraryVM: LibraryViewModel

    init(track: Track, libraryVM: LibraryViewModel = LibraryViewModel.shared!) {
        self.track = track
        self._libraryVM = ObservedObject(wrappedValue: libraryVM)
    }

    var body: some View {
        Menu {
            ForEach(1...5, id: \.self) { star in
                Button {
                    Task { @MainActor in
                        libraryVM.setRating(star, for: track)
                    }
                } label: {
                    let filled = track.starRating >= star
                    Label(
                        String(repeating: "★", count: star) +
                        String(repeating: "☆", count: 5 - star),
                        systemImage: filled ? "star.fill" : "star"
                    )
                }
            }
            if track.rating != nil {
                Divider()
                Button(role: .destructive) {
                    Task { @MainActor in
                        libraryVM.setRating(nil, for: track)
                    }
                } label: {
                    Label(LocalizedStringKey("clear_rating"), systemImage: "star.slash")
                }
            }
        } label: {
            Label(LocalizedStringKey("rate_track"), systemImage: "star")
        }
    }
}

/// Готовый модификатор — вешает контекстное меню с рейтингом на любую вьюху.
/// ```
/// TrackRowView(track: track)
///     .withRatingContextMenu(track)
/// ```
struct RatingContextMenuModifier: ViewModifier {
    let track: Track

    func body(content: Content) -> some View {
        content.contextMenu {
            TrackRatingMenu(track: track)
        }
    }
}

extension View {
    func withRatingContextMenu(_ track: Track) -> some View {
        modifier(RatingContextMenuModifier(track: track))
    }
}
