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
    /// The completed profile: the helix flies in for the first time and
    /// settles into a chord.
    case complete
    /// The helix flying in on the home screen: two strands drawn in from the
    /// sides, then the base pairs clicking into place.
    case helixArrival = "helix-arrival"
    /// A first name is saved: a sweep of stardust.
    case name
    /// A new match: the helix's strands are pulled apart, then the heart blooms.
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
        case .step1, .step2, .step3, .step4, .step5, .lock, .messageSent, .name: 0.55
        case .rejection, .messageReceived, .seal, .success, .exchange, .chatOpen: 0.6
        case .helixArrival: 0.65
        case .entrance, .complete, .match, .noMatch, .unfold: 0.7
        case .notification: 0.6
        }
    }

    /// The looping bed under the turning heart, carried from the landing page
    /// into the questionnaire.
    static var ambienceURL: URL? { Bundle.main.url(forResource: "ambience", withExtension: "caf") }
    /// The bed at full level, on the landing page. Far behind everything
    /// else: felt more than heard. Later screens play a share of this.
    static let ambienceVolume: Float = 0.14

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

    private let cues = CuePlayers()
    private let ambience = AmbientBed()
    /// The bed's requested level, as a share of its full volume.
    private var ambienceLevel: Float = 0
    private var isSessionConfigured = false
    private var sessionObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        // Sounds are always on now; drop the old profile overview switch.
        defaults.removeObject(forKey: "sounds.enabled")
    }

    /// Loads every cue up front so the first of each plays without delay.
    func prepare() {
        guard !Self.isRunningTests else { return }
        startSession()
        cues.load(AppSound.allCases.compactMap { sound in sound.url.map { (sound.rawValue, $0) } })
    }

    func play(_ sound: AppSound) {
        guard !Self.isRunningTests, let url = sound.url else { return }
        startSession()
        cues.play(sound.rawValue, url: url, volume: sound.volume)
    }

    /// Fades a cue that no longer matches the screen, for instance when a
    /// match closes before its sound has finished.
    func fadeOut(_ sounds: AppSound..., duration: TimeInterval = 0.35) {
        cues.fadeOut(sounds.map(\.rawValue), duration: duration)
    }

    /// Sets the bed's level as a share of its full volume; zero fades it out.
    /// From silence it waits a moment and then fades in slowly. Between two
    /// levels it glides, slower than the screen's own transition, so moving
    /// on feels like the room growing quieter rather than a step. It stays
    /// silent while another app plays audio, so it never sits under
    /// someone's music.
    func setAmbience(_ level: Float) {
        guard level != ambienceLevel else { return }
        let previous = ambienceLevel
        ambienceLevel = level
        guard !Self.isRunningTests else { return }
        guard level > 0 else {
            ambience.stop(fadeOut: 1.5)
            return
        }
        guard let url = AppSound.ambienceURL else { return }
        startSession()
        let volume = AppSound.ambienceVolume * level
        if previous == 0 {
            ambience.start(url: url, volume: volume, fadeIn: 4, delay: 1.5)
        } else {
            ambience.start(url: url, volume: volume, fadeIn: level < previous ? 2.5 : 2, delay: 0)
        }
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

/// The ambient bed: one decoded buffer looped sample-accurately by
/// an audio engine (an AVAudioPlayer leaves a gap at the loop point), with
/// volume ramps for the fades. Everything runs on one serial queue.
nonisolated private final class AmbientBed: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SoundPlayer.ambience", qos: .utility)
    /// Only touched on `queue`.
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?
    private var targetVolume: Float = 0
    /// Bumped by every start and stop, so an older fade gives way.
    private var generation = 0
    private var wantsPlaying = false
    private var configurationObserver: NSObjectProtocol?

    func start(url: URL, volume: Float, fadeIn: TimeInterval, delay: TimeInterval) {
        queue.async {
            self.generation += 1
            self.wantsPlaying = true
            self.targetVolume = volume
            guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint,
                  self.prepare(url), self.resume() else { return }
            self.ramp(to: volume, over: fadeIn, after: delay, generation: self.generation)
        }
    }

    func stop(fadeOut: TimeInterval) {
        queue.async {
            self.generation += 1
            self.wantsPlaying = false
            guard let node = self.node, node.isPlaying else { return }
            self.ramp(to: 0, over: fadeOut, after: 0, generation: self.generation) {
                node.stop()
                self.engine?.stop()
            }
        }
    }

    private func prepare(_ url: URL) -> Bool {
        if engine != nil { return true }
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return false }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
        node.volume = 0
        self.engine = engine
        self.node = node
        self.buffer = buffer
        // A new route (headphones, Bluetooth) stops the engine; pick the bed
        // up again where it should still be playing.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                guard self.wantsPlaying else { return }
                self.node?.stop()
                _ = self.resume()
                self.node?.volume = self.targetVolume
            }
        }
        return true
    }

    /// Starts the engine and the loop if they aren't running.
    private func resume() -> Bool {
        guard let engine, let node, let buffer else { return false }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        if !node.isPlaying {
            node.volume = 0
            node.scheduleBuffer(buffer, at: nil, options: .loops)
            node.play()
        }
        return true
    }

    private func ramp(to volume: Float, over duration: TimeInterval, after delay: TimeInterval,
                      generation: Int, then completion: (() -> Void)? = nil) {
        let step = 0.05
        let steps = max(1, Int(duration / step))
        let start = node?.volume ?? 0
        for index in 1...steps {
            queue.asyncAfter(deadline: .now() + delay + step * Double(index)) {
                guard self.generation == generation, let node = self.node else { return }
                let progress = Float(index) / Float(steps)
                // Equal-power curve, so the fade sounds even.
                let eased = sin(progress * .pi / 2)
                node.volume = start + (volume - start) * (volume > start ? eased : 1 - cos(progress * .pi / 2))
                if index == steps { completion?() }
            }
        }
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
