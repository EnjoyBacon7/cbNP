import Foundation

enum MediaSource: String, CaseIterable, Codable {
    case music = "Music"
    case spotify = "Spotify"
    case mediaRemote = "MediaRemote"

    static var supportedInSwiftApp: [MediaSource] {
        [.music, .spotify]
    }
}

struct AppPreferences: Codable, Equatable {
    var endpoint: String
    var token: String
    var interval: Int
    var mediaPlayer: MediaSource

    static let `default` = AppPreferences(
        endpoint: "ws://localhost:8000",
        token: "",
        interval: 15,
        mediaPlayer: .music
    )

    func validated() -> AppPreferences {
        var clean = AppPreferences.default

        if Self.isValidEndpoint(endpoint) {
            clean.endpoint = endpoint
        }
        clean.token = token
        if interval >= 1 {
            clean.interval = interval
        }
        clean.mediaPlayer = mediaPlayer

        return clean
    }

    static func isValidEndpoint(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return false
        }
        guard let scheme = url.scheme?.lowercased(), ["ws", "wss"].contains(scheme) else {
            return false
        }
        return url.host?.isEmpty == false
    }
}

struct Track: Codable, Equatable {
    var name: String
    var artist: String
    var album: String
    var artwork: String
    var id: String

    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }
}
