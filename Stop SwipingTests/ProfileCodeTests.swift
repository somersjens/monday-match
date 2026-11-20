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
        // Sealed: decoding the base64 shows nothing of the profile either.
        let bytes = try XCTUnwrap(Data(base64Encoded: packed.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/").padding(toLength: (packed.count + 3) / 4 * 4, withPad: "=", startingAt: 0)))
        XCTAssertNil(String(data: bytes, encoding: .utf8).flatMap { $0.contains("Emma") ? $0 : nil })
        XCTAssertNil(bytes.range(of: Data("Emma".utf8)))
        XCTAssertNil(bytes.range(of: Data("Gent".utf8)))
        XCTAssertNil(ProfileCode.decoded(bytes, today: today), "The bits inside can't be read without the seal.")
        XCTAssertNil(link.query())

        let scanned = try XCTUnwrap(ProfileCode.received(from: link, today: today)?.profile)
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
        XCTAssertNotNil(scanned.completedAt, "The time it was sealed stands in for when it was finished.")
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
        XCTAssertEqual(ProfileCode.received(fromScanned: " \(link.absoluteString)\n", today: today)?.profile, scanned)
        // The page hands the same sealed bytes on through the app's own scheme.
        XCTAssertEqual(ProfileCode.received(fromScanned: "stopswiping://code/\(packed)", today: today)?.profile, scanned)
        XCTAssertEqual(ProfileCode.received(fromScanned: "https://www.hakketjak.com/stop-swiping/code/#\(packed)", today: today)?.profile, scanned)
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
        let sealed = try XCTUnwrap(ProfileCode.sealed(state, today: today))
        XCTAssertEqual(sealed.count, data.count + ProfileCode.timestampBytes + ProfileHolder.byteCount
                       + ProfileSeal.headerBytes + ProfileSeal.nonceBytes + ProfileSeal.tagBytes)
        let link = try XCTUnwrap(ProfileCode.url(for: state, today: today))
        let matrix = try XCTUnwrap(WelcomeLightCode.Matrix(profileLink: link.absoluteString))
        XCTAssertLessThanOrEqual(matrix.size, WelcomeLightCode.Matrix.largestScannableSize,
                                 "Even the longest profile stays as coarse as a usual one.")
        // At least three lines of light per module.
        XCTAssertLessThanOrEqual(matrix.size, WelcomeLightCode.lineCount / 3)
    }

    func testOnlyTrustworthyCodesAreRead() throws {
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        let link = try XCTUnwrap(ProfileCode.url(for: emma, today: today))
        XCTAssertTrue(ProfileCode.isCode(link))
        XCTAssertNotNil(ProfileCode.received(from: link, today: today))

        let callback = try XCTUnwrap(URL(string: "stopswiping://auth/callback?code=abc"))
        XCTAssertFalse(ProfileCode.isCode(callback), "Sign-in links are left alone.")
        XCTAssertNil(ProfileCode.received(from: callback, today: today))
        XCTAssertNil(ProfileCode.received(fromScanned: "https://example.com/code/abc", today: today))
        XCTAssertNil(ProfileCode.received(fromScanned: "Stop Swiping", today: today))
        XCTAssertNil(ProfileCode.received(fromScanned: "stopswiping://code/", today: today))
        XCTAssertNil(ProfileCode.received(fromScanned: "stopswiping://code/!!!", today: today))
        let packed = try XCTUnwrap(link.fragment())
        for other in ["https://www.hakketjak.com/stop-swiping#\(packed)", "https://www.hakketjak.com/dino-time/code#\(packed)",
                      "https://hakketjak.example.com/stop-swiping/code#\(packed)", "http://www.hakketjak.com/stop-swiping/code#\(packed)"] {
            let url = try XCTUnwrap(URL(string: other))
            XCTAssertFalse(ProfileCode.isCode(url), other)
            XCTAssertNil(ProfileCode.received(from: url, today: today), other)
        }
        let empty = try XCTUnwrap(URL(string: "https://www.hakketjak.com/stop-swiping/code"))
        XCTAssertTrue(ProfileCode.isCode(empty), "A code link without answers is still recognised, and refused.")
        XCTAssertNil(ProfileCode.received(from: empty, today: today))

        let data = try XCTUnwrap(ProfileCode.encoded(emma, today: today))
        XCTAssertNil(ProfileCode.decoded(data.prefix(data.count / 2), today: today), "A cut-off code is refused.")
        XCTAssertNil(ProfileCode.decoded(Data(), today: today))
        var newer = data
        newer[0] = UInt8(ProfileCode.packingVersion + 1)
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
            bytes[0] = UInt8(ProfileCode.packingVersion)
            _ = ProfileCode.decoded(Data(bytes), today: today)
            bytes[0] = UInt8(ProfileCode.formatVersion)
            XCTAssertNil(ProfileCode.opened(Data(bytes), today: today, expires: false))
        }
    }

    func testSealedCodesRefuseAnyChangeAndAnUnsealedProfile() throws {
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        let sealed = try XCTUnwrap(ProfileCode.sealed(emma, today: today, now: now))
        XCTAssertNotNil(ProfileCode.opened(sealed, today: today, now: now, expires: true))
        for index in [0, 1, 2, 20, sealed.count - 1] {
            var changed = sealed
            changed[index] ^= 0x01
            XCTAssertNil(ProfileCode.opened(changed, today: today, now: now, expires: false), "byte \(index)")
        }
        XCTAssertNil(ProfileCode.opened(sealed.prefix(sealed.count - 1), today: today, now: now, expires: false))
        var unknownKey = sealed
        unknownKey[1] = ProfileSeal.readableKeyNumbers.upperBound + 1
        XCTAssertNil(ProfileCode.opened(unknownKey, today: today, now: now, expires: false), "A key this build doesn't have")
        let unsealed = try XCTUnwrap(ProfileCode.encoded(emma, today: today))
        XCTAssertNil(ProfileCode.opened(unsealed, today: today, now: now, expires: false), "A bare profile is never read")
    }

    func testScannedCodesLastADayAndRadioAndCardsNever() throws {
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        let link = try XCTUnwrap(ProfileCode.url(for: emma, today: today, now: now))
        let sealed = try XCTUnwrap(ProfileCode.sealed(emma, today: today, now: now))
        let dayLater = now.addingTimeInterval(ProfileCode.codeLifetime - 60)
        let tooLate = now.addingTimeInterval(ProfileCode.codeLifetime + 60)
        XCTAssertNotNil(ProfileCode.received(from: link, today: today, now: dayLater), "A whole event long")
        XCTAssertNil(ProfileCode.received(from: link, today: today, now: tooLate), "A screenshot stops working")
        XCTAssertNil(ProfileCode.received(from: link, today: today,
                                          now: now.addingTimeInterval(-ProfileCode.clockTolerance - 60)),
                     "A code from far in the future is refused")
        XCTAssertNotNil(ProfileCode.opened(sealed, today: today, now: tooLate.addingTimeInterval(86_400 * 30), expires: false),
                        "A match card or radio exchange never expires")
        XCTAssertEqual(ProfileCode.profile(fromCard: sealed.base64EncodedString(), today: today)?.displayName, "Emma")
    }

    func testEveryCodeFromOnePhoneNamesTheSameHolder() throws {
        let holder = ProfileHolder(bytes: Data([9, 8, 7, 6, 5, 4, 3, 2]))
        let short = profile(name: "Al", gender: .woman, partnerGenders: [.man])
        let long = profile(name: "Alexandra", gender: .woman, partnerGenders: [.man])
        let first = try XCTUnwrap(ProfileCode.sealed(short, holder: holder, today: today, now: now))
        let second = try XCTUnwrap(ProfileCode.sealed(long, holder: holder, today: today, now: now))
        XCTAssertNotEqual(first, try XCTUnwrap(ProfileCode.sealed(short, holder: holder, today: today, now: now)),
                          "A fresh nonce every time")
        XCTAssertEqual(ProfileCode.opened(first, today: today, expires: false)?.holder, holder)
        XCTAssertEqual(ProfileCode.opened(second, today: today, expires: false)?.holder, holder)
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
        // A usual profile, and the largest code a profile can make.
        var longest = detailed(profile(name: String(repeating: "W", count: ProfileNameRules.maximumLength),
                                       gender: .woman, partnerGenders: [.man]))
        longest.languages = ["nl", "en", "fr", "de", "es", "fil"]
        longest.location?.placeName = "Sint-Lambrechts-Woluwe"
        for (name, profile) in [("Emma", detailed(profile(name: "Emma", gender: .woman, partnerGenders: [.man]))),
                                (longest.displayName, longest)] {
            try assertCodeScans(profile, named: name, resources: resources)
        }
    }

    private func assertCodeScans(_ emma: ProfileCreationState, named name: String,
                                 resources: WelcomeLightMetalResources) throws {
        let link = try XCTUnwrap(ProfileCode.url(for: emma, today: today))
        let matrix = try XCTUnwrap(WelcomeLightCode.Matrix(profileLink: link.absoluteString))

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
            attachment.name = "Profile code of \(name.prefix(8)) at \(elapsed) s"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Core Image's reader runs in the simulator too; Vision's doesn't.
            let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let payloads = detector.features(in: CIImage(cgImage: image))
                .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(payloads, [link.absoluteString], "The code must scan at \(elapsed) s (\(matrix.size) modules).")
            XCTAssertEqual(payloads.first.flatMap { ProfileCode.received(fromScanned: $0, today: today) }?.profile.displayName, name)
        }
    }

    func testScannerEndsOnTheFirstProfileAndFlagsOtherCodes() throws {
        let link = try XCTUnwrap(ProfileCode.url(for: profile(name: "Emma", gender: .woman, partnerGenders: [.man]), today: today))
        let model = ProfileCodeScannerModel()
        model.read("https://example.com", today: today)
        XCTAssertTrue(model.showsUnknownCode)
        XCTAssertFalse(model.rejectedIsProfileCode)
        XCTAssertNil(model.profile)
        // A screenshot of a code from two days ago says it expired.
        let old = try XCTUnwrap(ProfileCode.url(for: profile(name: "Emma", gender: .woman, partnerGenders: [.man]),
                                                today: today, now: Date().addingTimeInterval(-2 * 86_400)))
        model.read(old.absoluteString, today: today)
        XCTAssertTrue(model.rejectedIsProfileCode)
        XCTAssertNil(model.profile)
        model.read(link.absoluteString, today: today)
        XCTAssertEqual(model.profile?.profile.displayName, "Emma")
        XCTAssertFalse(model.showsUnknownCode)

        let other = try XCTUnwrap(ProfileCode.url(for: profile(name: "Noor", gender: .woman, partnerGenders: [.man]), today: today))
        model.read(other.absoluteString, today: today)
        XCTAssertEqual(model.profile?.profile.displayName, "Emma", "One scan gives one match.")
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
        XCTAssertEqual(inbox.pending?.profile.displayName, "Emma", "The match follows once the profile is finished.")
        inbox.dismissNotice()
        XCTAssertNil(inbox.notice)
        XCTAssertEqual(inbox.take()?.profile.displayName, "Emma")
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
        religion.acceptedPartnerReligions = [.christian, .preferNotToShare, .other]
        state.religion = religion
        for (index, question) in CompatibilityScaleQuestion.all.enumerated() {
            state.lifestyle[question] = CompatibilityScaleAnswer(own: index % 5 + 1, partner: (index * 3) % 5 + 1,
                                                                 isPartnerCustomized: true, importance: index % 5 + 1)
        }
        return state
    }
}
