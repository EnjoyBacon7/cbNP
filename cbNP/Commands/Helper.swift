//
//  Helper.swift
//  cbNP
//
//  Created by Camille Bizeul on 8/8/25.
//

import Foundation

private let fieldSeparator = "␟"

struct MusicField {

    var key: String
    var variable: String
    var script: String
    var appendSeparator: Bool = true
    var coerceToString: Bool = true
    var allowFailure: Bool = false

    func declare() -> String {
        let assignment: String
        if coerceToString {
            assignment = "set \(variable) to (\(script)) as string"
        } else {
            assignment = "set \(variable) to \(script)"
        }

        if allowFailure {
            return """
                try
                    \(assignment)
                on error
                    set \(variable) to ""
                end try
                """
        }

        return assignment
    }

    func append() -> String {
        if appendSeparator {
            return "set \(variable) to \(variable) & \"\(fieldSeparator)\""
        } else {
            return ""
        }
    }
}

private let appleMusicFields = [
    MusicField(
        key: "track",
        variable: "trackName",
        script: "name of current track"
    ),
    MusicField(
        key: "artist",
        variable: "trackArtist",
        script: "artist of current track"
    ),
    MusicField(
        key: "album",
        variable: "trackAlbum",
        script: "album of current track"
    ),
    MusicField(
        key: "id",
        variable: "trackId",
        script: "id of current track as string"
    ),
    MusicField(
        key: "artwork",
        variable: "artworkData",
        script: "get raw data of artwork 1 of current track",
        appendSeparator: false,
        allowFailure: true
    ),
]

private let spotifyFields = [
    MusicField(
        key: "track",
        variable: "trackName",
        script: "name of current track"
    ),
    MusicField(
        key: "artist",
        variable: "trackArtist",
        script: "artist of current track"
    ),
    MusicField(
        key: "album",
        variable: "trackAlbum",
        script: "album of current track"
    ),
    MusicField(
        key: "id",
        variable: "trackId",
        script: "id of current track as string"
    ),
    MusicField(
        key: "artwork",
        variable: "artworkData",
        script: "get artwork url of current track",
        appendSeparator: false,
        allowFailure: true
    ),
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
                    \(createCommand(fields: fields, mediaPlayer: mediaPlayer))
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
               brief.localizedCaseInsensitiveContains("isn't running") || brief.localizedCaseInsensitiveContains("is not running") {
                throw AppleScriptError.noTrackPlaying
            }
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -1743 {
                throw AppleScriptError.permissionDenied(mediaPlayer.rawValue)
            }
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -600 {
                throw AppleScriptError.noTrackPlaying
            }
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -1728 {
                throw AppleScriptError.noTrackPlaying
            }
            throw AppleScriptError.executionFailed(String(describing: error))
        }

        // When the app is not running the outer if block falls through and returns nothing;
        // NSAppleScript gives us an empty-string descriptor in that case.
        return output.stringValue ?? ""
    }

    func createCommand(fields: [String], mediaPlayer: MediaPlayer) -> String {

        let fieldsArray = fieldsMap[mediaPlayer]!
        var fieldDict = [String: MusicField]()
        for field in fieldsArray {
            fieldDict[field.key] = field
        }

        var commands: [String] = []

        // Declare each variable
        for key in fields {
            if let field = fieldDict[key] {
                commands.append(field.declare())
            }
        }

        // Append separators between text fields (artwork has appendSeparator: false)
        for key in fields {
            if let field = fieldDict[key] {
                let sep = field.append()
                if !sep.isEmpty {
                    commands.append(sep)
                }
            }
        }

        // Build a single concatenated string return value so that
        // NSAppleEventDescriptor.stringValue is always non-nil.
        // Artwork (last field, no separator) is concatenated last without a separator.
        let textVars = fields.compactMap { key -> String? in
            guard let field = fieldDict[key], field.appendSeparator else { return nil }
            return field.variable
        }
        let artworkVar = fields.compactMap { key -> String? in
            guard let field = fieldDict[key], !field.appendSeparator else { return nil }
            return field.variable
        }.first

        var resultParts = textVars
        if let aw = artworkVar {
            resultParts.append(aw)
        }

        if resultParts.isEmpty {
            commands.append("return \"\"")
        } else {
            commands.append("return " + resultParts.joined(separator: " & "))
        }

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
