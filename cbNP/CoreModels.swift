import Foundation

enum MediaSource: String, CaseIterable, Codable {
    case music = "Music"
    case spotify = "Spotify"
    case mediaRemote = "MediaRemote"

    static var supportedInSwiftApp: [MediaSource] {
        [.music, .spotify, .mediaRemote]
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

    init(endpoint: String, token: String, interval: Int, mediaPlayer: MediaSource) {
        self.endpoint = endpoint
        self.token = token
        self.interval = interval
        self.mediaPlayer = mediaPlayer
    }

    // Decode each field independently with a fallback to the default, so a
    // single missing/invalid key never discards the entire preferences file.
    // The media-player key is read in both the current camelCase spelling and
    // the snake_case `media_player` written by the predecessor implementation.
    enum CodingKeys: String, CodingKey {
        case endpoint, token, interval, mediaPlayer
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case mediaPlayer = "media_player"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppPreferences.default
        endpoint = (try? container.decode(String.self, forKey: .endpoint)) ?? fallback.endpoint
        token = (try? container.decode(String.self, forKey: .token)) ?? fallback.token
        interval = (try? container.decode(Int.self, forKey: .interval)) ?? fallback.interval

        if let source = try? container.decode(MediaSource.self, forKey: .mediaPlayer) {
            mediaPlayer = source
        } else if let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self),
                  let source = try? legacy.decode(MediaSource.self, forKey: .mediaPlayer) {
            mediaPlayer = source
        } else {
            mediaPlayer = fallback.mediaPlayer
        }
    }

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
        guard let host = url.host, !host.isEmpty else {
            return false
        }
        // Unencrypted ws:// transmits the auth token in cleartext, so it is
        // only permitted for loopback hosts. Remote endpoints must use wss://.
        if scheme == "ws", !isLoopbackHost(host) {
            return false
        }
        return true
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
            || normalized.hasSuffix(".localhost")
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
