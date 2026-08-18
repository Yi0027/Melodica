//Views,SmartPlaylistRow
import SwiftUI

struct SmartPlaylistRow: View {
    let playlist: SmartPlaylist
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: playlist.icon)
                .foregroundColor(.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textMain)
                    .lineLimit(1)

                Text("\(playlist.rules.count) \(NSLocalizedString("rules", comment: ""))")
                    .font(.system(size: 10))
                    .foregroundColor(.textMuted)
            }

            Spacer()

            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.textMuted)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
        )
    }
}
