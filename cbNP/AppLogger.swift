import Foundation

final class AppLogger {
    private let logURL: URL
    private let queue = DispatchQueue(label: "cbNP.logger")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(logURL: URL) {
        self.logURL = logURL
    }

    func info(_ message: String) { write(level: "INFO", message: message) }
    func warning(_ message: String) { write(level: "WARNING", message: message) }
    func error(_ message: String) { write(level: "ERROR", message: message) }

    func redactToken(in message: String, token: String) -> String {
        guard !token.isEmpty else { return message }
        return message.replacingOccurrences(of: token, with: "\(token.prefix(4))...")
    }

    private func write(level: String, message: String) {
        let line = "\(Self.dateFormatter.string(from: Date())) - \(level): \(message)\n"
        queue.async {
            if !FileManager.default.fileExists(atPath: self.logURL.path) {
                FileManager.default.createFile(atPath: self.logURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: self.logURL) else { return }
            do {
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } catch {
                try? handle.close()
            }
        }
    }
}
