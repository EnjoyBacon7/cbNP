import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppViewModel {
    var connectionStatus = "Disconnected"
    var trackTitle = "No track playing"
    var trackArtist = ""
    var artwork: NSImage?
    var sourceWarning = ""
    var lastError = ""

    var endpointInput = ""
    var tokenInput = ""
    var intervalInput = "15"
    var selectedSource: MediaSource = .music

    private(set) var preferences: AppPreferences

    private let preferencesStore = PreferencesStore()
    private let nowPlayingService = NowPlayingService()
    private let webSocketClient = WebSocketClient()
    private let logger: AppLogger

    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var currentTrackID: String?
    private var started = false
    private var connectingTask: Task<Void, Never>?

    init() {
        let store = PreferencesStore()
        let prefs: AppPreferences
        do {
            prefs = try store.loadPreferences()
        } catch {
            prefs = .default
        }

        preferences = prefs
        logger = AppLogger(logURL: store.logURL)

        endpointInput = prefs.endpoint
        tokenInput = prefs.token
        intervalInput = String(prefs.interval)
        selectedSource = MediaSource.supportedInSwiftApp.contains(prefs.mediaPlayer) ? prefs.mediaPlayer : .music
        sourceWarning = Self.musicTahoeWarningIfNeeded(source: prefs.mediaPlayer)

        logger.info("Starting cbNP")
    }

    func startIfNeeded() {
        guard !started else {
            return
        }
        started = true
        refreshSourceWarning()
        startReconnectTimer()
    }

    func stop() {
        pollTimer?.invalidate()
        heartbeatTimer?.invalidate()
        reconnectTimer?.invalidate()
        pollTimer = nil
        heartbeatTimer = nil
        reconnectTimer = nil

        Task {
            await webSocketClient.disconnect()
        }
    }

    func savePreferencesFromInputs() {
        guard let interval = Int(intervalInput), interval >= 1 else {
            setError("Interval must be an integer >= 1")
            return
        }

        let draft = AppPreferences(
            endpoint: endpointInput,
            token: tokenInput,
            interval: interval,
            mediaPlayer: selectedSource
        ).validated()

        guard AppPreferences.isValidEndpoint(draft.endpoint) else {
            setError("Endpoint must be wss:// (ws:// is allowed only for localhost)")
            return
        }

        do {
            try preferencesStore.savePreferences(draft)
        } catch {
            setError("Failed to save preferences: \(error.localizedDescription)")
            return
        }

        preferences = draft
        endpointInput = draft.endpoint
        tokenInput = draft.token
        intervalInput = String(draft.interval)
        selectedSource = draft.mediaPlayer
        refreshSourceWarning()

        pollTimer?.invalidate()
        heartbeatTimer?.invalidate()
        pollTimer = nil
        heartbeatTimer = nil

        Task {
            await webSocketClient.disconnect()
            await connectIfNeeded()
        }
    }

    func updateNow() {
        Task {
            await sendUpdateIfPossible(force: true)
        }
    }

    func reconnectNow() {
        Task {
            await webSocketClient.disconnect()
            connectionStatus = "Disconnected"
            connectingTask?.cancel()
            connectingTask = nil
            await connectIfNeeded()
        }
    }

    private func refreshSourceWarning() {
        sourceWarning = Self.musicTahoeWarningIfNeeded(source: preferences.mediaPlayer)
    }

    private static func musicTahoeWarningIfNeeded(source: MediaSource) -> String {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if source == .music && major >= 26 {
            return "Warning: Music artwork is unreliable on Tahoe. Use MediaRemote when available."
        }
        return ""
    }

    private func setError(_ message: String) {
        lastError = message
        logger.error(logger.redactToken(in: message, token: preferences.token))
    }

    private func startReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.connectIfNeeded()
            }
        }
        reconnectTimer?.tolerance = 0.5
    }

    private func startOperationalTimers() {
        pollTimer?.invalidate()
        heartbeatTimer?.invalidate()

        pollTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(preferences.interval), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.sendUpdateIfPossible(force: false)
            }
        }
        pollTimer?.tolerance = min(1, TimeInterval(preferences.interval) * 0.25)

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.sendHeartbeat()
            }
        }
        heartbeatTimer?.tolerance = 2
    }

    private func connectIfNeeded() async {
        // If a connection attempt is already in flight, don't start another.
        guard connectingTask == nil else { return }

        connectingTask = Task {
            await _connect()
            connectingTask = nil
        }
    }

    private func _connect() async {
        if await webSocketClient.isConnected {
            return
        }

        guard let endpointURL = URL(string: preferences.endpoint), AppPreferences.isValidEndpoint(preferences.endpoint) else {
            setError("Invalid endpoint: \(preferences.endpoint)")
            connectionStatus = "Invalid endpoint"
            return
        }

        connectionStatus = "Connecting..."
        await webSocketClient.connect(endpoint: endpointURL)

        do {
            try await webSocketClient.send(jsonObject: ["type": "heartbeat"])
            connectionStatus = "Connected"
            lastError = ""
            logger.info("WebSocket connected on \(preferences.endpoint)")
            startOperationalTimers()
            await sendUpdateIfPossible(force: true)
        } catch {
            connectionStatus = "Disconnected"
            await webSocketClient.disconnect()
            logger.warning("Connection failed: \(error.localizedDescription)")
        }
    }

    private func sendHeartbeat() async {
        do {
            try await webSocketClient.send(jsonObject: ["type": "heartbeat"])
        } catch {
            connectionStatus = "Disconnected"
            logger.warning("Heartbeat failed: \(error.localizedDescription)")
            await webSocketClient.disconnect()
        }
    }

    private func sendUpdateIfPossible(force: Bool) async {
        if !(await webSocketClient.isConnected) {
            connectionStatus = "Disconnected"
            return
        }

        let track: Track
        do {
            track = try await nowPlayingService.fetchTrack(source: preferences.mediaPlayer)
        } catch NowPlayingError.noTrackPlaying {
            logger.info("fetchTrack: noTrackPlaying (source: \(preferences.mediaPlayer.rawValue))")
            clearTrackDisplay()
            return
        } catch NowPlayingError.invalidFormat(let raw) {
            clearTrackDisplay()
            setError("fetchTrack: invalidFormat — raw output: \(raw.prefix(200))")
            return
        } catch {
            clearTrackDisplay()
            setError("fetchTrack failed: \(error.localizedDescription)")
            return
        }

        do {
            if !force, currentTrackID == track.id {
                return
            }

            currentTrackID = track.id
            applyTrackDisplay(track)

            let payload = try track.asDictionary()
            try await webSocketClient.send(jsonObject: [
                "type": "update",
                "payload": payload,
                "auth": preferences.token,
            ])
            lastError = ""
        } catch {
            connectionStatus = "Disconnected"
            await webSocketClient.disconnect()
            setError("WebSocket send failed: \(error.localizedDescription)")
        }
    }

    private func applyTrackDisplay(_ track: Track) {
        trackTitle = track.name.isEmpty ? "Unknown track" : track.name
        trackArtist = track.artist
        artwork = Self.decodeArtwork(track.artwork)
    }

    private func clearTrackDisplay() {
        currentTrackID = nil
        trackTitle = "No track playing"
        trackArtist = ""
        artwork = nil
    }

    private static func decodeArtwork(_ base64: String) -> NSImage? {
        guard !base64.isEmpty,
              let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data)
        else {
            return nil
        }
        return image
    }
}
