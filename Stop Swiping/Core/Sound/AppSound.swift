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
    private var players: [AppSound: AVAudioPlayer] = [:]
    private var isSessionConfigured = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// On unless turned off in the profile overview.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            if !newValue { players.values.forEach { $0.stop() } }
        }
    }

    /// Loads every cue up front so the first of each plays without delay.
    func prepare() {
        configureSession()
        for sound in AppSound.allCases where players[sound] == nil {
            _ = player(for: sound)
        }
    }

    func play(_ sound: AppSound) {
        guard isEnabled, !Self.isRunningTests else { return }
        configureSession()
        guard let player = player(for: sound) else { return }
        player.volume = sound.volume
        player.currentTime = 0
        player.play()
    }

    /// Fades a cue that no longer matches the screen, for instance when a
    /// match closes before its sound has finished.
    func fadeOut(_ sounds: AppSound..., duration: TimeInterval = 0.35) {
        for sound in sounds {
            guard let player = players[sound], player.isPlaying else { continue }
            player.setVolume(0, fadeDuration: duration)
        }
    }

    private func player(for sound: AppSound) -> AVAudioPlayer? {
        if let player = players[sound] { return player }
        guard let url = sound.url, let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[sound] = player
        return player
    }

    private func configureSession() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }

    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
