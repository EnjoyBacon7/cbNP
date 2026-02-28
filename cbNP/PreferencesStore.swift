import Foundation

struct PreferencesStore {
    private let fm = FileManager.default

    var appSupportDirectory: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cbNP", isDirectory: true)
    }

    var preferencesURL: URL {
        appSupportDirectory.appendingPathComponent("Pref.json")
    }

    var logURL: URL {
        appSupportDirectory.appendingPathComponent("error.log")
    }

    func ensureRuntimePaths() throws {
        try fm.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }

    func loadPreferences() throws -> AppPreferences {
        try ensureRuntimePaths()

        if !fm.fileExists(atPath: preferencesURL.path) {
            try savePreferences(.default)
            return .default
        }

        let data = try Data(contentsOf: preferencesURL)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        let validated = decoded.validated()
        if validated != decoded {
            try savePreferences(validated)
        }
        return validated
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        try ensureRuntimePaths()
        let data = try JSONEncoder.pretty.encode(preferences.validated())
        try data.write(to: preferencesURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
