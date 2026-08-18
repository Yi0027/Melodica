//Models,SmartPlaylist
import Foundation

struct SmartPlaylist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var rules: [SmartPlaylistRule]
    var matchAll: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "sparkles",
        rules: [SmartPlaylistRule],
        matchAll: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.rules = rules
        self.matchAll = matchAll
    }
}
