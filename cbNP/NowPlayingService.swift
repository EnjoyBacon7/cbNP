import Foundation

struct NowPlayingService {
    private let helper = AppleScriptHelper.shared
    private let separator = "␟"
    private let defaultArtworkBase64 = ""

    func fetchTrack(source: MediaSource) async throws -> Track {
        switch source {
        case .music:
            let output = try await executeAppleScript(
                fields: ["track", "artist", "album", "id", "artwork"],
                mediaPlayer: .appleMusic
            )
            return try await parseOutput(output, source: .music)
        case .spotify:
            let output = try await executeAppleScript(
                fields: ["track", "artist", "album", "id", "artwork"],
                mediaPlayer: .spotify
            )
            return try await parseOutput(output, source: .spotify)
        case .mediaRemote:
            throw NowPlayingError.unsupportedSource("MediaRemote is not implemented in Swift yet.")
        }
    }

    private func parseOutput(_ output: String, source: MediaSource) async throws -> Track {
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NowPlayingError.noTrackPlaying
        }

        let fields = split(output, separator: separator, maxSplits: 4)
        guard fields.count == 5 else {
            throw NowPlayingError.invalidFormat(output)
        }

        let name = fields[0]
        let artist = fields[1]
        let album = fields[2]
        let id = fields[3]
        let artworkRaw = fields[4]
        let artwork = try await extractArtwork(source: source, artworkRaw: artworkRaw)

        return Track(name: name, artist: artist, album: album, artwork: artwork, id: id)
    }

    private func executeAppleScript(fields: [String], mediaPlayer: MediaPlayer) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let output = try helper.execute(fields: fields, mediaPlayer: mediaPlayer)
                    continuation.resume(returning: output)
                } catch AppleScriptError.permissionDenied(let app) {
                    continuation.resume(throwing: NowPlayingError.permissionDenied(app))
                } catch AppleScriptError.noTrackPlaying {
                    continuation.resume(throwing: NowPlayingError.noTrackPlaying)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func extractArtwork(source: MediaSource, artworkRaw: String) async throws -> String {
        if artworkRaw.isEmpty || artworkRaw == "missing value" {
            return defaultArtworkBase64
        }

        switch source {
        case .spotify:
            guard let url = URL(string: artworkRaw) else {
                return defaultArtworkBase64
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                return data.base64EncodedString()
            } catch {
                return defaultArtworkBase64
            }
        case .music:
            let cleaned = artworkRaw
                .replacingOccurrences(of: "«data ", with: "")
                .replacingOccurrences(of: "»", with: "")
                .replacingOccurrences(of: "[^0-9A-Fa-f]", with: "", options: .regularExpression)

            if cleaned.isEmpty {
                return defaultArtworkBase64
            }

            let evenLengthHex = cleaned.count.isMultiple(of: 2) ? cleaned : String(cleaned.dropLast())
            guard let data = Data(hexString: evenLengthHex) else {
                return defaultArtworkBase64
            }
            return data.base64EncodedString()
        case .mediaRemote:
            return defaultArtworkBase64
        }
    }

    private func split(_ input: String, separator: String, maxSplits: Int) -> [String] {
        guard maxSplits > 0 else {
            return [input]
        }

        var parts: [String] = []
        var remainder = input[...]

        for _ in 0..<maxSplits {
            guard let range = remainder.range(of: separator) else {
                break
            }
            parts.append(String(remainder[..<range.lowerBound]))
            remainder = remainder[range.upperBound...]
        }

        parts.append(String(remainder))
        return parts
    }
}

enum NowPlayingError: LocalizedError {
    case noTrackPlaying
    case permissionDenied(String)
    case invalidFormat(String)
    case unsupportedSource(String)

    var errorDescription: String? {
        switch self {
        case .noTrackPlaying:
            return "No track is currently playing."
        case .permissionDenied(let app):
            return "Automation permission denied for \(app)."
        case .invalidFormat:
            return "Could not parse now-playing data from AppleScript."
        case .unsupportedSource(let message):
            return message
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = Array(hexString)
        guard hex.count.isMultiple(of: 2) else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)

        var index = 0
        while index < hex.count {
            let first = String(hex[index])
            let second = String(hex[index + 1])
            guard let byte = UInt8(first + second, radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index += 2
        }

        self.init(bytes)
    }
}
