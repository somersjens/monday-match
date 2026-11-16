import AVFoundation
import SwiftUI
import UserNotifications

/// The app's sound palette. Every cue shares one key and one glass voice
/// (see tools/sounds/generate_sounds.py), so the app sounds like one
/// instrument. Cues are deliberately quiet: they accompany the light, they
/// never announce themselves.
enum AppSound: String, CaseIterable {
    /// The welcome light threading in at launch.
    case entrance
    /// One questionnaire step; five notes climbing the scale.
    case step1 = "step-1", step2 = "step-2", step3 = "step-3", step4 = "step-4", step5 = "step-5"
    /// Choosing an answer.
    case select
    /// An answer that can't continue, or an age that isn't allowed.
    case rejection
    /// The finished questionnaire seals with its checkmark.
    case seal
    /// The completed profile: the helix arrives.
    case complete
    /// A new match: the heart blooms.
    case match
    /// A new result without a match: the heart lets go, gently.
    case noMatch = "no-match"
    /// A saved match unfolding in place from the helix.
    case unfold
    /// Two phones meet, or a code is scanned.
    case exchange
    /// The heart's tip lifts into the conversation's rings.
    case chatOpen = "chat-open"
    case messageSent = "message-sent"
    case messageReceived = "message-received"
    /// A tap on the lock.
    case lock
    /// Something opens or comes forward, and its counterpart.
    case open, close
    /// Signed in, or another moment of success.
    case success
    /// The app's signature, also used for its notifications.
    case notification = "notification-chime"

    /// The questionnaire's note for a step, climbing and then starting over.
    static func step(_ number: Int) -> AppSound {
        let steps: [AppSound] = [.step1, .step2, .step3, .step4, .step5]
        return steps[((number - 1) % steps.count + steps.count) % steps.count]
    }

    var fileExtension: String { self == .notification ? "caf" : "m4a" }

    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: fileExtension) }

    /// Playback level. The files are mastered close together; this sets how
    /// far each one sits behind the interface.
    var volume: Float {
        switch self {
        case .select, .open, .close: 0.5
        case .step1, .step2, .step3, .step4, .step5, .lock, .messageSent: 0.55
        case .rejection, .messageReceived, .seal, .success, .exchange, .chatOpen: 0.6
        case .entrance, .complete, .match, .noMatch, .unfold: 0.7
        case .notification: 0.6
        }
    }

    /// The chime for local notifications, from the app bundle.
    static var notificationSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName("\(AppSound.notification.rawValue).caf"))
    }
}

/// Plays the palette. Uses the ambient audio category, so sounds follow the
/// silent switch and mix with whatever else is playing.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    static let enabledKey = "sounds.enabled"

    private let defaults: UserDefaults
    private let cues = CuePlayers()
    private var isSessionConfigured = false
    private var sessionObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On unless turned off in the profile overview.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { cues.stopAll() }
        }
    }

    /// Loads every cue up front so the first of each plays without delay.
    func prepare() {
        guard !Self.isRunningTests else { return }
        startSession()
        cues.load(AppSound.allCases.compactMap { sound in sound.url.map { (sound.rawValue, $0) } })
    }

    func play(_ sound: AppSound) {
        guard isEnabled, !Self.isRunningTests, let url = sound.url else { return }
        startSession()
        cues.play(sound.rawValue, url: url, volume: sound.volume)
    }

    /// Fades a cue that no longer matches the screen, for instance when a
    /// match closes before its sound has finished.
    func fadeOut(_ sounds: AppSound..., duration: TimeInterval = 0.35) {
        cues.fadeOut(sounds.map(\.rawValue), duration: duration)
    }

    /// Sets the ambient category and activates the session ahead of the first
    /// cue. Safe to call more than once; only the first call does anything.
    func startSession() {
        guard !isSessionConfigured, !Self.isRunningTests else { return }
        isSessionConfigured = true
        // The category stays synchronous: a cue that played before it was set
        // would use the default category and silence other apps' audio.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        cues.activateSession()
        // The system deactivates the session in the background and during
        // interruptions; reactivate it before a cue has to do so itself.
        let center = NotificationCenter.default
        let cues = cues
        sessionObservers = [
            center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                               object: nil, queue: nil) { _ in cues.activateSession() },
            center.addObserver(forName: AVAudioSession.interruptionNotification,
                               object: nil, queue: nil) { note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                if type == .ended { cues.activateSession() }
            },
        ]
    }

    nonisolated private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

/// The cue players, kept off the main thread. Starting playback activates the
/// audio session, which talks to the audio server and can block the calling
/// thread, so every player is created, started and stopped on one serial
/// queue. Session activation runs on the same queue, ahead of any cue.
nonisolated private final class CuePlayers: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SoundPlayer.cues", qos: .userInitiated)
    /// Only touched on `queue`.
    private var players: [String: AVAudioPlayer] = [:]

    func activateSession() {
        queue.async { try? AVAudioSession.sharedInstance().setActive(true) }
    }

    func load(_ cues: [(name: String, url: URL)]) {
        queue.async {
            for cue in cues { _ = self.player(cue.name, url: cue.url) }
        }
    }

    func play(_ name: String, url: URL, volume: Float) {
        queue.async {
            guard let player = self.player(name, url: url) else { return }
            player.volume = volume
            player.currentTime = 0
            player.play()
        }
    }

    func fadeOut(_ names: [String], duration: TimeInterval) {
        queue.async {
            for name in names {
                guard let player = self.players[name], player.isPlaying else { continue }
                player.setVolume(0, fadeDuration: duration)
            }
        }
    }

    func stopAll() {
        queue.async { self.players.values.forEach { $0.stop() } }
    }

    private func player(_ name: String, url: URL) -> AVAudioPlayer? {
        if let player = players[name] { return player }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[name] = player
        return player
    }
}

extension View {
    /// Plays a sound when `trigger` changes, like `sensoryFeedback`.
    func soundFeedback<T: Equatable>(_ sound: AppSound, trigger: T) -> some View {
        onChange(of: trigger) { _, _ in SoundPlayer.shared.play(sound) }
    }

    /// Plays a sound when `trigger` changes and `condition` holds.
    func soundFeedback<T: Equatable>(_ sound: AppSound, trigger: T,
                                     condition: @escaping (T, T) -> Bool) -> some View {
        onChange(of: trigger) { old, new in
            if condition(old, new) { SoundPlayer.shared.play(sound) }
        }
    }

    /// Plays the sound `choose` picks for a change, if any.
    func soundFeedback<T: Equatable>(trigger: T, _ choose: @escaping (T, T) -> AppSound?) -> some View {
        onChange(of: trigger) { old, new in
            if let sound = choose(old, new) { SoundPlayer.shared.play(sound) }
        }
    }
}
