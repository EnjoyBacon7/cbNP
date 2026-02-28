import Foundation

// Bundle identifiers for known music apps — only these are forwarded as now-playing.
// Mirrors COMMON_MEDIAREMOTE_BUNDLES in the Python implementation.
private let allowedBundles: Set<String> = [
    "com.apple.Music",
    "com.spotify.client",
    "com.tidal.desktop",
    "com.deezer.DeezerDesktop",
    "com.ciderapp.Cider",
    "com.voxapp.mac",
]

struct MediaRemoteService {

    // MARK: - Public

    /// Fetches the current now-playing track via the MediaRemote adapter.
    /// Returns `nil` if nothing is playing or the playing app is not in the allowlist.
    /// Throws `MediaRemoteError` on hard failures.
    func fetchTrack() async throws -> Track? {
        let payload = try await runAdapter()
        guard let payload else { return nil }

        let bundle = (payload["parentApplicationBundleIdentifier"] as? String)
            ?? (payload["bundleIdentifier"] as? String)
            ?? ""

        guard !bundle.isEmpty, allowedBundles.contains(bundle) else {
            return nil
        }

        let title = (payload["title"] as? String) ?? ""
        let artist = (payload["artist"] as? String) ?? ""
        let album = (payload["album"] as? String) ?? ""
        let id = (payload["uniqueIdentifier"] as? String) ?? ""

        let artworkBase64: String
        if let artworkString = payload["artworkData"] as? String,
           let artworkData = Data(base64Encoded: artworkString, options: .ignoreUnknownCharacters) {
            artworkBase64 = artworkData.base64EncodedString()
        } else {
            artworkBase64 = ""
        }

        return Track(name: title, artist: artist, album: album, artwork: artworkBase64, id: id)
    }

    // MARK: - Private

    private func runAdapter() async throws -> [String: Any]? {
        guard
            let scriptURL = Bundle.main.url(
                forResource: "mediaremote-adapter",
                withExtension: "pl",
                subdirectory: "mediaremote_adapter"
            ),
            let fmwkURL = Bundle.main.url(
                forResource: "MediaRemoteAdapter",
                withExtension: "fmwk",
                subdirectory: "mediaremote_adapter"
            ),
            let clientURL = Bundle.main.url(
                forResource: "MediaRemoteAdapterTestClient",
                withExtension: nil,
                subdirectory: "mediaremote_adapter"
            )
        else {
            throw MediaRemoteError.adapterNotFound
        }

        // The Perl script requires the framework path to end in ".framework".
        // We expose the bundled .fmwk directory via a temporary symlink with the
        // correct extension, then clean it up after the process exits.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cbNP-mediaremote-\(UUID().uuidString)", isDirectory: true)
        let frameworkLinkURL = tempDir.appendingPathComponent("MediaRemoteAdapter.framework")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: frameworkLinkURL, withDestinationURL: fmwkURL)
        } catch {
            throw MediaRemoteError.launchFailed("Could not create framework symlink: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                process.arguments = [
                    scriptURL.path,
                    frameworkLinkURL.path,
                    clientURL.path,
                    "get",
                ]

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                // Enforce a 2-second timeout
                let timeoutItem = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeoutItem)

                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutItem.cancel()
                } catch {
                    timeoutItem.cancel()
                    continuation.resume(throwing: MediaRemoteError.launchFailed(error.localizedDescription))
                    return
                }

                guard process.terminationStatus == 0 else {
                    let errOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: MediaRemoteError.adapterFailed(errOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }

                let raw = stdout.fileHandleForReading.readDataToEndOfFile()
                let trimmed = raw.trimmingWhitespace()
                if trimmed.isEmpty {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: trimmed)
                    if let dict = json as? [String: Any] {
                        continuation.resume(returning: dict)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(throwing: MediaRemoteError.invalidJSON(error.localizedDescription))
                }
            }
        }
    }
}

enum MediaRemoteError: LocalizedError {
    case adapterNotFound
    case launchFailed(String)
    case adapterFailed(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .adapterNotFound:
            return "MediaRemote adapter resources not found in app bundle."
        case .launchFailed(let msg):
            return "Failed to launch MediaRemote adapter: \(msg)"
        case .adapterFailed(let msg):
            return "MediaRemote adapter exited with error: \(msg)"
        case .invalidJSON(let msg):
            return "MediaRemote adapter returned invalid JSON: \(msg)"
        }
    }
}

private extension Data {
    func trimmingWhitespace() -> Data {
        var start = startIndex
        var end = endIndex
        let whitespace = CharacterSet.whitespacesAndNewlines
        while start < end, whitespace.contains(Unicode.Scalar(self[start])) {
            start = index(after: start)
        }
        while end > start, whitespace.contains(Unicode.Scalar(self[index(before: end)])) {
            end = index(before: end)
        }
        return self[start..<end]
    }
}
