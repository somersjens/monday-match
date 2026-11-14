import CoreLocation
import Metal
import CoreImage
import XCTest
@testable import Stop_Swiping

@MainActor
final class ProfileCodeTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 13)
    private var now: Date {
        BirthDateRules.calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 15))!
    }

    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .english
    }

    // MARK: - Packing

    func testCodeCarriesTheWholeSharedProfile() throws {
        let emma = detailed(profile(name: "Emma", gender: .woman, partnerGenders: [.man, .nonBinary]))
        let link = try XCTUnwrap(ProfileCode.url(for: emma, today: today))
        XCTAssertEqual(link.scheme, "https")
        XCTAssertEqual(link.host(), "www.hakketjak.com")
        XCTAssertEqual(link.path(), "/stop-swiping/code", "The page that leads to the App Store.")
        XCTAssertFalse(link.absoluteString.contains("Emma"), "The code isn't readable as text.")
        let packed = try XCTUnwrap(link.fragment(), "Answers stay behind the #, which no website receives.")
        XCTAssertNil(link.query())

        let scanned = try XCTUnwrap(ProfileCode.profile(from: link, today: today))
        let shared = try XCTUnwrap(emma.sharedCopy(today: today).receivedCopy(today: today))
        XCTAssertEqual(scanned.displayName, "Emma")
        XCTAssertEqual(scanned.age(on: today), 30)
        XCTAssertEqual(scanned.dateOfBirth, shared.dateOfBirth, "Only the age travels.")
        XCTAssertEqual(scanned.partnerAgeRange, shared.partnerAgeRange)
        XCTAssertEqual(scanned.heightCentimeters, 182)
        XCTAssertEqual(scanned.partnerHeightRange, PartnerHeightRange(minimum: 170, maximum: 205))
        XCTAssertEqual(scanned.gender, .woman)
        XCTAssertEqual(scanned.partnerGenders, [.man, .nonBinary])
        XCTAssertEqual(scanned.relationshipPreferences, shared.relationshipPreferences)
        XCTAssertEqual(scanned.religion, shared.religion)
        XCTAssertEqual(scanned.languages, ["nl", "en", "fil"])
        XCTAssertEqual(scanned.searchRadiusKilometers, 40)
        XCTAssertEqual(try XCTUnwrap(scanned.location?.latitude), 51.05, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(scanned.location?.longitude), 3.72, accuracy: 1e-9)
        XCTAssertEqual(scanned.location?.placeName, "Gent")
        XCTAssertEqual(scanned.completedAt, shared.completedAt)
        XCTAssertEqual(scanned.autoMatching, AutoMatchingSettings(), "Auto matching never leaves the phone.")
        XCTAssertEqual(scanned.lifestyle.hasChildren, false)
        XCTAssertEqual(scanned.lifestyle.openToPartnerWithChildren, true)
        XCTAssertEqual(scanned.lifestyle.futureChildren, .yes)
        for substance in Substance.allCases {
            XCTAssertEqual(scanned.lifestyle[substance], shared.lifestyle[substance])
        }
        for question in CompatibilityScaleQuestion.all {
            let answer = scanned.lifestyle[question], original = shared.lifestyle[question]
            XCTAssertEqual(answer.own, original.own, question.id)
            XCTAssertEqual(answer.partner, original.partner, question.id)
            XCTAssertEqual(answer.importance, original.importance, question.id)
        }

        // Scanning gives exactly the match an exchange between two phones gives.
        let jens = profile(name: "Jens").sharedCopy(today: today)
        XCTAssertEqual(MatchReport(you: jens, them: scanned, on: today), MatchReport(you: jens, them: shared, on: today))
        XCTAssertEqual(ProfileCode.profile(fromScanned: " \(link.absoluteString)\n", today: today), scanned)
        // The page hands the same answers on through the app's own scheme.
        XCTAssertEqual(ProfileCode.profile(fromScanned: "stopswiping://code/\(packed)", today: today), scanned)
        XCTAssertEqual(ProfileCode.profile(fromScanned: "https://www.hakketjak.com/stop-swiping/code/#\(packed)", today: today), scanned)
    }

    func testUnansweredAndUnusualAnswersSurvive() throws {
        var state = profile(name: "Zoë 🌙")
        state.gender = nil
        state.partnerAgeRange = nil
        state.location = nil
        state.languages = ["nl", "zh-Hant", "EN"]
        state.lifestyle.hasChildren = nil
        state.lifestyle.futureChildren = nil
        state.lifestyle[.drugs] = SubstanceAnswer()
        let pets = try XCTUnwrap(CompatibilityScaleQuestion.question(for: .pets))
        state.lifestyle[.aloneTime] = CompatibilityScaleAnswer()
        state.lifestyle[pets] = CompatibilityScaleAnswer(own: 5, partner: nil, isPartnerCustomized: false, importance: nil)

        let scanned = try XCTUnwrap(ProfileCode.decoded(try XCTUnwrap(ProfileCode.encoded(state, today: today)), today: today))
        XCTAssertEqual(scanned.displayName, "Zoë 🌙")
        XCTAssertNil(scanned.gender)
        XCTAssertNil(scanned.partnerAgeRange)
        XCTAssertNil(scanned.location)
        XCTAssertEqual(scanned.languages, ["nl", "en"], "Only plain language codes are packed.")
        XCTAssertNil(scanned.lifestyle.hasChildren)
        XCTAssertNil(scanned.lifestyle.futureChildren)
        XCTAssertEqual(scanned.lifestyle[.drugs], SubstanceAnswer())
        XCTAssertEqual(scanned.lifestyle[.aloneTime], CompatibilityScaleAnswer())
        XCTAssertEqual(scanned.lifestyle[pets].own, 5)
        XCTAssertNil(scanned.lifestyle[pets].partner)
        XCTAssertNil(scanned.lifestyle[pets].importance)
    }

    func testCodeStaysSmallEnoughToScanFromAScreen() throws {
        var state = detailed(profile(name: String(repeating: "W", count: ProfileNameRules.maximumLength)))
        state.languages = ["nl", "en", "fr", "de", "es", "fil"]
        state.location?.placeName = "Sint-Lambrechts-Woluwe"
        let data = try XCTUnwrap(ProfileCode.encoded(state, today: today))
        XCTAssertLessThan(data.count, 190)
        let link = try XCTUnwrap(ProfileCode.url(for: state, today: today))
        let matrix = try XCTUnwrap(WelcomeLightCode.Matrix(message: link.absoluteString))
        // At least three lines of light per module.
        XCTAssertLessThanOrEqual(matrix.size, WelcomeLightCode.lineCount / 3)
    }

    func testOnlyTrustworthyCodesAreRead() throws {
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        let link = try XCTUnwrap(ProfileCode.url(for: emma, today: today))
        XCTAssertTrue(ProfileCode.isCode(link))
        XCTAssertNotNil(ProfileCode.profile(from: link, today: today))

        let callback = try XCTUnwrap(URL(string: "stopswiping://auth/callback?code=abc"))
        XCTAssertFalse(ProfileCode.isCode(callback), "Sign-in links are left alone.")
        XCTAssertNil(ProfileCode.profile(from: callback, today: today))
        XCTAssertNil(ProfileCode.profile(fromScanned: "https://example.com/code/abc", today: today))
        XCTAssertNil(ProfileCode.profile(fromScanned: "Stop Swiping", today: today))
        XCTAssertNil(ProfileCode.profile(fromScanned: "stopswiping://code/", today: today))
        XCTAssertNil(ProfileCode.profile(fromScanned: "stopswiping://code/!!!", today: today))
        let packed = try XCTUnwrap(link.fragment())
        for other in ["https://www.hakketjak.com/stop-swiping#\(packed)", "https://www.hakketjak.com/dino-time/code#\(packed)",
                      "https://hakketjak.example.com/stop-swiping/code#\(packed)", "http://www.hakketjak.com/stop-swiping/code#\(packed)"] {
            let url = try XCTUnwrap(URL(string: other))
            XCTAssertFalse(ProfileCode.isCode(url), other)
            XCTAssertNil(ProfileCode.profile(from: url, today: today), other)
        }
        let empty = try XCTUnwrap(URL(string: "https://www.hakketjak.com/stop-swiping/code"))
        XCTAssertTrue(ProfileCode.isCode(empty), "A code link without answers is still recognised, and refused.")
        XCTAssertNil(ProfileCode.profile(from: empty, today: today))

        let data = try XCTUnwrap(ProfileCode.encoded(emma, today: today))
        XCTAssertNil(ProfileCode.decoded(data.prefix(data.count / 2), today: today), "A cut-off code is refused.")
        XCTAssertNil(ProfileCode.decoded(Data(), today: today))
        var newer = data
        newer[0] = UInt8(ProfileCode.formatVersion + 1)
        XCTAssertNil(ProfileCode.decoded(newer, today: today), "A newer format is never guessed at.")

        var minor = emma
        minor.dateOfBirth = CalendarDate(year: 2012, month: 1, day: 1)
        XCTAssertNil(ProfileCode.decoded(try XCTUnwrap(ProfileCode.encoded(minor, today: today)), today: today))
        var unfinished = emma
        unfinished.dateOfBirth = nil
        XCTAssertNil(ProfileCode.encoded(unfinished, today: today))
        var nameless = emma
        nameless.displayName = ""
        XCTAssertNil(ProfileCode.decoded(try XCTUnwrap(ProfileCode.encoded(nameless, today: today)), today: today))

        // Random bytes never crash and never become a profile by accident.
        var generator = SystemRandomNumberGenerator()
        for length in [1, 7, 40, 160, 400] {
            var bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
            bytes[0] = UInt8(ProfileCode.formatVersion)
            _ = ProfileCode.decoded(Data(bytes), today: today)
        }
    }

    func testBitsRoundTripAtEveryWidth() {
        var writer = BitWriter()
        writer.write(5, bits: 3)
        writer.write(true)
        writer.write(999, bits: 7)
        writer.write(optional: nil)
        writer.write(optional: false)
        writer.write(optional: true)
        writer.write(raw: 0xDEADBEEF, bits: 32)
        writer.write(text: "héé 👋🏽 en nog veel meer", lengthBits: 4, maximumBytes: 9)
        var reader = BitReader(writer.data)
        XCTAssertEqual(reader.read(3), 5)
        XCTAssertEqual(reader.readFlag(), true)
        XCTAssertEqual(reader.read(7), 127, "Values are clamped to their width.")
        XCTAssertEqual(reader.readOptionalFlag(), .some(nil))
        XCTAssertEqual(reader.readOptionalFlag(), .some(false))
        XCTAssertEqual(reader.readOptionalFlag(), .some(true))
        XCTAssertEqual(reader.read(32), 0xDEADBEEF)
        XCTAssertEqual(reader.readText(lengthBits: 4), "héé ", "Text is cut between characters.")
        XCTAssertNil(reader.read(8))
    }

    // MARK: - Showing and scanning

    func testRenderedCodeOfLightScansBackToTheProfile() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let emma = detailed(profile(name: "Emma", gender: .woman, partnerGenders: [.man]))
        let link = try XCTUnwrap(ProfileCode.url(for: emma, today: today))
        let matrix = try XCTUnwrap(WelcomeLightCode.Matrix(message: link.absoluteString))

        // An iPhone screen at 3x, at several moments of the code's slow sway.
        let scale = 3, width = 393 * scale, height = 825 * scale
        let size = CGSize(width: width, height: height)
        for elapsed in [40.0, 43.5, 47.0] {
            var uniforms = WelcomeLightUniforms(presentationElapsed: elapsed, size: size, pixelScale: Float(scale))
            uniforms.apply(WelcomeLightLock.Pose(amount: 1, lift: 0, shake: 0, isHelix: true, code: 1))
            uniforms.code.y = Float(matrix.size)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget, .shaderRead]
            let texture = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
            let emission = try XCTUnwrap(resources.emissionTexture(size: size))
            let target = MTLRenderPassDescriptor()
            target.colorAttachments[0].texture = texture
            target.colorAttachments[0].loadAction = .clear
            target.colorAttachments[0].storeAction = .store
            let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
            resources.render(command: command, target: target, emission: emission, uniforms: &uniforms,
                             code: resources.codeBuffer(for: matrix))
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let image = try XCTUnwrap(CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "Profile code at \(elapsed) s"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Core Image's reader runs in the simulator too; Vision's doesn't.
            let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let payloads = detector.features(in: CIImage(cgImage: image))
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(payloads, [link.absoluteString], "The code must scan at \(elapsed) s.")
            XCTAssertEqual(payloads.first.flatMap { ProfileCode.profile(fromScanned: $0, today: today) }?.displayName, "Emma")
        }
    }

    func testScannerEndsOnTheFirstProfileAndFlagsOtherCodes() throws {
        let link = try XCTUnwrap(ProfileCode.url(for: profile(name: "Emma", gender: .woman, partnerGenders: [.man]), today: today))
        let model = ProfileCodeScannerModel()
        model.read("https://example.com", today: today)
        XCTAssertTrue(model.showsUnknownCode)
        XCTAssertNil(model.profile)
        model.read(link.absoluteString, today: today)
        XCTAssertEqual(model.profile?.displayName, "Emma")
        XCTAssertFalse(model.showsUnknownCode)

        let other = try XCTUnwrap(ProfileCode.url(for: profile(name: "Noor", gender: .woman, partnerGenders: [.man]), today: today))
        model.read(other.absoluteString, today: today)
        XCTAssertEqual(model.profile?.displayName, "Emma", "One scan gives one match.")
    }

    // MARK: - Opened from outside

    func testInboxKeepsACodeUntilTheProfileIsReady() throws {
        let link = try XCTUnwrap(ProfileCode.url(for: profile(name: "Emma", gender: .woman, partnerGenders: [.man]), today: today))
        let inbox = ProfileCodeInbox()
        XCTAssertFalse(inbox.open(try XCTUnwrap(URL(string: "stopswiping://auth/callback?code=abc")),
                                  isProfileReady: true, today: today))
        XCTAssertNil(inbox.pending)
        XCTAssertNil(inbox.notice)

        XCTAssertTrue(inbox.open(link, isProfileReady: false, today: today))
        XCTAssertEqual(inbox.notice, .needsProfile(name: "Emma"))
        XCTAssertEqual(inbox.pending?.displayName, "Emma", "The match follows once the profile is finished.")
        inbox.dismissNotice()
        XCTAssertNil(inbox.notice)
        XCTAssertEqual(inbox.take()?.displayName, "Emma")
        XCTAssertNil(inbox.pending)
        XCTAssertNil(inbox.take())

        XCTAssertTrue(inbox.open(link, isProfileReady: true, today: today))
        XCTAssertNil(inbox.notice, "A finished profile goes straight to the match.")
        XCTAssertNotNil(inbox.take())

        XCTAssertTrue(inbox.open(try XCTUnwrap(URL(string: "stopswiping://code/AAAA")), isProfileReady: true, today: today))
        XCTAssertEqual(inbox.notice, .unreadable)
        XCTAssertNil(inbox.pending)
    }

    // MARK: - Fixtures

    private func profile(name: String, gender: GenderIdentity = .man,
                         partnerGenders: Set<GenderIdentity> = [.woman]) -> ProfileCreationState {
        var state = ProfileCreationState(today: today, applicationLanguage: "nl")
        state.displayName = name
        state.dateOfBirth = CalendarDate(year: 1996, month: 4, day: 21)
        state.partnerAgeRange = PartnerAgeRange(minimum: 24, maximum: 40, isCustomized: true)
        state.heightCentimeters = 182
        state.gender = gender
        state.partnerGenders = partnerGenders
        state.languages = ["nl", "en"]
        state.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        state.searchRadiusKilometers = 40
        var lifestyle = state.lifestyle
        lifestyle.hasChildren = false
        lifestyle.openToPartnerWithChildren = true
        lifestyle.futureChildren = .notSure
        for substance in Substance.allCases {
            lifestyle[substance] = SubstanceAnswer(ownLevel: 1, partnerMaximumLevel: 5)
        }
        for question in CompatibilityScaleQuestion.all {
            lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 3, isPartnerCustomized: true, importance: 3)
        }
        state.lifestyle = lifestyle
        state.completedAt = now
        return state
    }

    /// Every answer set to something other than its default.
    private func detailed(_ profile: ProfileCreationState) -> ProfileCreationState {
        var state = profile
        state.hasAdjustedHeight = true
        state.partnerHeightRange = PartnerHeightRange(minimum: 170, maximum: 205)
        state.languages = ["nl", "en", "fil"]
        state.location?.placeName = "Gent"
        state.relationshipPreferences.select("togetherWithOthers", in: .sexualArrangement)
        state.lifestyle.futureChildren = .yes
        state.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 3, partnerMaximumLevel: 0)
        state.lifestyle[.smoking] = SubstanceAnswer(ownLevel: 0, partnerMaximumLevel: 2)
        var religion = ReligionAnswers()
        religion.own = .christian
        religion.acceptedPartnerReligions = [.christian, .agnostic, .other]
        state.religion = religion
        for (index, question) in CompatibilityScaleQuestion.all.enumerated() {
            state.lifestyle[question] = CompatibilityScaleAnswer(own: index % 5 + 1, partner: (index * 3) % 5 + 1,
                                                                 isPartnerCustomized: true, importance: index % 5 + 1)
        }
        return state
    }
}
