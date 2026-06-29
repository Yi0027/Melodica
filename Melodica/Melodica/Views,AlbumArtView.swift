import SwiftUI

struct AlbumArtView: View {
    let image: NSImage?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let nsImage = image {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color.darkSurface, Color.darkBg], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note.list").font(.system(size: size * 0.22, weight: .thin)).foregroundColor(.textMuted.opacity(0.3))
                }
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 25, y: 12)
    }
}
