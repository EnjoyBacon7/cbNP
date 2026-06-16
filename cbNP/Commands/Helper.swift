import Foundation

struct MusicField {
    var key: String
    var variable: String
    var script: String
    var appendSeparator: Bool = true
    var coerceToString: Bool = true
    var allowFailure: Bool = false

    func declare() -> String {
        let assignment = coerceToString
            ? "set \(variable) to (\(script)) as string"
            : "set \(variable) to \(script)"

        guard allowFailure else { return assignment }
        return """
            try
                \(assignment)
            on error
                set \(variable) to ""
            end try
            """
    }

    func separatorCommand() -> String {
        appendSeparator ? "set \(variable) to \(variable) & \"\(fieldSeparator)\"" : ""
    }
}

private let appleMusicFields: [MusicField] = [
    MusicField(key: "track",   variable: "trackName",   script: "name of current track"),
    MusicField(key: "artist",  variable: "trackArtist", script: "artist of current track"),
    MusicField(key: "album",   variable: "trackAlbum",  script: "album of current track"),
    MusicField(key: "id",      variable: "trackId",     script: "id of current track as string"),
    MusicField(key: "artwork", variable: "artworkData",
               script: "get raw data of artwork 1 of current track",
               appendSeparator: false, allowFailure: true),
]

private let spotifyFields: [MusicField] = [
    MusicField(key: "track",   variable: "trackName",   script: "name of current track"),
    MusicField(key: "artist",  variable: "trackArtist", script: "artist of current track"),
    MusicField(key: "album",   variable: "trackAlbum",  script: "album of current track"),
    MusicField(key: "id",      variable: "trackId",     script: "id of current track as string"),
    MusicField(key: "artwork", variable: "artworkData",
               script: "get artwork url of current track",
               appendSeparator: false, allowFailure: true),
]

enum MediaPlayer: String {
    case appleMusic = "Music"
    case spotify = "Spotify"
}

class AppleScriptHelper {
    static let shared = AppleScriptHelper()
    private init() {}

    private let fieldsMap: [MediaPlayer: [MusicField]] = [
        .appleMusic: appleMusicFields,
        .spotify: spotifyFields,
    ]

    func execute(fields: [String], mediaPlayer: MediaPlayer) throws -> String {
        let script = """
            if application "\(mediaPlayer.rawValue)" is running then
                tell application "\(mediaPlayer.rawValue)"
                    \(buildCommand(fields: fields, mediaPlayer: mediaPlayer))
                end tell
            end if
            """

        guard let appleScript = NSAppleScript(source: script) else {
            throw AppleScriptError.invalidScript
        }

        var errorDict: NSDictionary?
        let output = appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            if let brief = error[NSAppleScript.errorBriefMessage] as? String,
               brief.localizedCaseInsensitiveContains("isn't running") ||
               brief.localizedCaseInsensitiveContains("is not running") {
                throw AppleScriptError.noTrackPlaying
            }
            if let code = error[NSAppleScript.errorNumber] as? Int {
                switch code {
                case -1743: throw AppleScriptError.permissionDenied(mediaPlayer.rawValue)
                case -600, -1728: throw AppleScriptError.noTrackPlaying
                default: break
                }
            }
            throw AppleScriptError.executionFailed(String(describing: error))
        }

        // When the app is not running the outer `if` falls through with no result;
        // NSAppleScript returns an empty-string descriptor in that case.
        return output.stringValue ?? ""
    }

    // Builds a single-string AppleScript return value so that
    // NSAppleEventDescriptor.stringValue is always non-nil.
    private func buildCommand(fields: [String], mediaPlayer: MediaPlayer) -> String {
        let allFields = fieldsMap[mediaPlayer]!
        var fieldDict = [String: MusicField]()
        for field in allFields { fieldDict[field.key] = field }

        var commands: [String] = []

        // 1. Declare each variable
        for key in fields {
            if let field = fieldDict[key] { commands.append(field.declare()) }
        }
        // 2. Append ␟ separator to text fields
        for key in fields {
            if let field = fieldDict[key] {
                let sep = field.separatorCommand()
                if !sep.isEmpty { commands.append(sep) }
            }
        }
        // 3. Concatenate everything into one string and return
        let textVars   = fields.compactMap { fieldDict[$0].flatMap { $0.appendSeparator  ? $0.variable : nil } }
        let artworkVar = fields.compactMap { fieldDict[$0].flatMap { !$0.appendSeparator ? $0.variable : nil } }.first
        var parts = textVars
        if let aw = artworkVar { parts.append(aw) }
        commands.append(parts.isEmpty ? "return \"\"" : "return \(parts.joined(separator: " & "))")

        return commands.joined(separator: "\n")
    }
}

enum AppleScriptError: LocalizedError {
    case invalidScript
    case permissionDenied(String)
    case noTrackPlaying
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidScript:
            return "Failed to build AppleScript command."
        case .permissionDenied(let app):
            return "Automation permission denied for \(app). Allow access in System Settings > Privacy & Security > Automation."
        case .noTrackPlaying:
            return "No track is currently playing."
        case .executionFailed(let error):
            return "AppleScript error: \(error)"
        }
    }
}
