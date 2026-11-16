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

    func testQuestionnaireStepsClimbTheScaleAndStartOver() {
        XCTAssertEqual((1...7).map(AppSound.step), [.step1, .step2, .step3, .step4, .step5, .step1, .step2])
        XCTAssertEqual(AppSound.step(0), .step5)
    }

    func testSoundsAreOnByDefaultAndTheChoiceIsRemembered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        XCTAssertTrue(SoundPlayer(defaults: defaults).isEnabled)
        SoundPlayer(defaults: defaults).isEnabled = false
        XCTAssertFalse(SoundPlayer(defaults: defaults).isEnabled)
        defaults.removePersistentDomain(forName: #function)
    }
}
