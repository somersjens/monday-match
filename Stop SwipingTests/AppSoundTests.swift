import AVFoundation
import XCTest
@testable import Stop_Swiping

@MainActor
final class AppSoundTests: XCTestCase {
    func testEveryCueIsBundled() throws {
        for sound in AppSound.allCases {
            let url = try XCTUnwrap(sound.url, "\(sound.rawValue).\(sound.fileExtension) is missing from the bundle")
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 0, sound.rawValue)
        }
    }

    /// iOS plays a custom notification sound only if it is linear PCM (or
    /// IMA4/aLaw/µLaw) and shorter than 30 seconds; otherwise it falls back
    /// to the default sound without a word.
    func testNotificationChimeMeetsTheNotificationRequirements() throws {
        let url = try XCTUnwrap(AppSound.notification.url)
        XCTAssertEqual(url.pathExtension, "caf")
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat.streamDescription.pointee
        XCTAssertEqual(format.mFormatID, kAudioFormatLinearPCM)
        XCTAssertLessThan(Double(file.length) / file.fileFormat.sampleRate, 30)
    }

    func testCuesStayShortEnoughToFollowTheirAnimation() throws {
        for sound in AppSound.allCases {
            let file = try AVAudioFile(forReading: try XCTUnwrap(sound.url))
            XCTAssertLessThan(Double(file.length) / file.fileFormat.sampleRate, 10, sound.rawValue)
        }
    }

    /// The bed loops without a seam only if the decoder gives back exactly
    /// the 24 seconds that were written, without AAC priming or padding.
    func testAmbienceDecodesToExactlyOneLoop() throws {
        let file = try AVAudioFile(forReading: try XCTUnwrap(AppSound.ambienceURL))
        XCTAssertEqual(file.length, 24 * 44_100)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
    }

    /// A cue that stops while still ringing ends in a click. Every file
    /// has to fade all the way out.
    func testEveryCueEndsInSilence() throws {
        for sound in AppSound.allCases {
            let file = try AVAudioFile(forReading: try XCTUnwrap(sound.url))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                        frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            let frames = Int(buffer.frameLength)
            let tail = Int(file.processingFormat.sampleRate * 0.01)
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in max(0, frames - tail)..<frames { peak = max(peak, abs(channels[channel][frame])) }
            }
            XCTAssertLessThan(peak, 0.003, "\(sound.rawValue) still sounds in its last 10 ms")
        }
    }

    /// Ticks follow a finger on a wheel or slider; they need spare voices so
    /// one never cuts the last off, and a limit so they never pile up.
    func testRapidCuesHaveSpareVoicesAndARateLimit() {
        XCTAssertGreaterThan(AppSound.tick.voices, 1)
        XCTAssertGreaterThan(AppSound.tick.minimumInterval, 0)
        XCTAssertGreaterThan(AppSound.select.minimumInterval, 0)
        XCTAssertEqual(AppSound.match.minimumInterval, 0)
        XCTAssertLessThan(AppSound.masterVolume, 1)
    }

    func testQuestionnaireStepsClimbTheScaleAndStartOver() {
        XCTAssertEqual((1...7).map(AppSound.step), [.step1, .step2, .step3, .step4, .step5, .step1, .step2])
        XCTAssertEqual(AppSound.step(0), .step5)
    }

    func testTheOldSoundsSwitchIsCleared() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.set(false, forKey: "sounds.enabled")
        _ = SoundPlayer(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "sounds.enabled"))
        defaults.removePersistentDomain(forName: #function)
    }
}
