import XCTest
import Metal
@testable import Stop_Swiping

final class PersonalityEstimatorTests: XCTestCase {
    private func answers(_ values: [ProfileCreationStep: Double], default fallback: Double = 0) -> PersonalityAnswers {
        var all: [ProfileCreationStep: Double] = [:]
        for step in CompatibilityScaleQuestion.orderedSteps { all[step] = values[step] ?? fallback }
        return PersonalityAnswers(values: all)
    }

    private var outgoingPlanner: PersonalityAnswers {
        answers([
            .talkativeness: 1, .socialPlans: 1, .aloneTime: -1, .nightlife: 1, .competitiveness: 1, .hostingGuests: 1,
            .rules: -1, .newExperiences: -1, .spirituality: -1, .headOrHeart: -1, .perfectionism: 1,
            .communicationStyle: 1, .debating: 1, .listeningAndSolutions: -1, .setbacks: -1,
            .weeklyPlanning: 1, .punctuality: 1, .homeTidiness: 1, .spendingMoney: 1, .boundaries: 1,
            .takingInitiative: 1, .workAmbition: 1,
        ])
    }

    private var quietDreamer: PersonalityAnswers {
        answers([
            .talkativeness: -1, .socialPlans: -1, .aloneTime: 1, .nightlife: -1, .competitiveness: -1, .hostingGuests: -1,
            .rules: 1, .newExperiences: 1, .spirituality: 1, .headOrHeart: 1, .perfectionism: -1,
            .communicationStyle: -1, .debating: -1, .listeningAndSolutions: 1, .setbacks: 1,
            .weeklyPlanning: -1, .punctuality: -1, .homeTidiness: -1, .spendingMoney: -1, .boundaries: -1,
        ])
    }

    func testEveryTestHasAResultThatFitsTheShader() throws {
        for test in PersonalityTest.allCases {
            for profile in [outgoingPlanner, quietDreamer, answers([:])] {
                let result = try XCTUnwrap(PersonalityEstimator.result(for: test, answers: profile), test.title)
                XCTAssertFalse(result.headline.isEmpty, test.title)
                XCTAssertFalse(result.summary.isEmpty, test.title)
                XCTAssertLessThanOrEqual(result.visual.values.count, WelcomeLightPersonality.maximumValues, test.title)
                XCTAssertTrue(result.visual.values.allSatisfy(\.isFinite), test.title)
            }
        }
    }

    func testMBTIReadsOppositeProfilesAsOppositeTypes() {
        XCTAssertEqual(PersonalityEstimator.mbti(outgoingPlanner).headline, "ESTJ")
        XCTAssertEqual(PersonalityEstimator.mbti(quietDreamer).headline, "INFP")
        guard case .spectrum(let dimensions) = PersonalityEstimator.mbti(outgoingPlanner).chart else {
            return XCTFail("MBTI draws as a spectrum")
        }
        XCTAssertEqual(dimensions.count, 4)
        XCTAssertTrue(dimensions.allSatisfy { $0.percent >= 50 && $0.percent <= 100 })
        XCTAssertTrue(dimensions.allSatisfy { abs($0.value) <= 1 })
    }

    func testModelsAgreeWithEachOther() {
        let outgoing = outgoingPlanner, quiet = quietDreamer
        XCTAssertTrue(PersonalityEstimator.sixteenPersonalities(outgoing).headline.hasPrefix("ESTJ-"))
        XCTAssertEqual(PersonalityEstimator.disc(outgoing).headline.first, "D")
        XCTAssertEqual(PersonalityEstimator.insights(outgoing).headline, L10n("Fiery Red"))
        XCTAssertEqual(PersonalityEstimator.insights(quiet).headline, L10n("Earth Green"))
        XCTAssertEqual(PersonalityEstimator.bigFive(outgoing).headline.prefix(3), "oCE")
        XCTAssertEqual(PersonalityEstimator.belbin(outgoing).headline, L10n("Implementer"))
        XCTAssertEqual(PersonalityEstimator.belbin(quiet).headline, L10n("Plant"))
    }

    /// Deterministic random profiles: every question answered 1…5, or only
    /// at the extremes, as people with strong opinions answer.
    private func randomProfiles(count: Int, extremes: Bool) -> [PersonalityAnswers] {
        var seed: UInt64 = extremes ? 0x9E3779B97F4A7C15 : 0x2545F4914F6CDD1D
        func next() -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return seed >> 33
        }
        return (0..<count).map { _ in
            var values: [ProfileCreationStep: Double] = [:]
            for step in CompatibilityScaleQuestion.orderedSteps {
                values[step] = extremes ? (next() % 2 == 0 ? -1 : 1) : Double(Int(next() % 5) - 2) / 2
            }
            return PersonalityAnswers(values: values)
        }
    }

    private func distribution(_ headlines: [String]) -> [String: Double] {
        var counts: [String: Double] = [:]
        for headline in headlines { counts[headline, default: 0] += 1 }
        return counts.mapValues { $0 / Double(headlines.count) }
    }

    /// Answers without any pattern must not favour one outcome: every type
    /// and role has to be reachable, and none may dominate.
    func testRandomProfilesSpreadOverEveryOutcome() throws {
        let profiles = randomProfiles(count: 4000, extremes: false)
        var report: [String] = []
        func check(_ name: String, _ headlines: [String], expected: Int, minimum: Double, maximum: Double) {
            let shares = distribution(headlines)
            report.append("\(name): " + shares.sorted { $0.value > $1.value }
                .map { "\($0.key) \(Int(($0.value * 100).rounded()))%" }.joined(separator: ", "))
            XCTAssertEqual(shares.count, expected, "\(name) reaches every outcome")
            XCTAssertGreaterThanOrEqual(shares.values.min() ?? 0, minimum, name)
            XCTAssertLessThanOrEqual(shares.values.max() ?? 1, maximum, name)
        }
        let mbti = profiles.map { PersonalityEstimator.mbti($0).headline }
        for index in 0..<4 {
            let letters = mbti.map { String(Array($0)[index]) }
            check("MBTI letter \(index + 1)", letters, expected: 2, minimum: 0.35, maximum: 0.65)
        }
        check("MBTI", mbti, expected: 16, minimum: 0.02, maximum: 0.12)
        check("DISC", profiles.map { String(PersonalityEstimator.disc($0).headline.prefix(1)) },
              expected: 4, minimum: 0.15, maximum: 0.35)
        check("Insights", profiles.map { PersonalityEstimator.insights($0).headline },
              expected: 4, minimum: 0.15, maximum: 0.35)
        check("Enneagram", profiles.map { String(PersonalityEstimator.enneagram($0).headline.prefix(1)) },
              expected: 9, minimum: 0.04, maximum: 0.20)
        check("Belbin", profiles.map { PersonalityEstimator.belbin($0).headline },
              expected: 9, minimum: 0.04, maximum: 0.20)
        check("TMA", profiles.map { PersonalityEstimator.tma($0).headline },
              expected: 8, minimum: 0.05, maximum: 0.22)
        check("16P identity", profiles.map { String(PersonalityEstimator.sixteenPersonalities($0).headline.suffix(1)) },
              expected: 2, minimum: 0.35, maximum: 0.65)
        let pi = distribution(profiles.map { PersonalityEstimator.predictiveIndex($0).headline })
        report.append("PI: " + pi.sorted { $0.value > $1.value }
            .map { "\($0.key) \(Int(($0.value * 100).rounded()))%" }.joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(pi.count, 15, "PI reaches nearly every reference profile")
        XCTAssertLessThanOrEqual(pi.values.max() ?? 1, 0.2)
        print("PERSONALITY DISTRIBUTION\n" + report.joined(separator: "\n"))
    }

    /// Strong opinions on every question must still give a profile with a
    /// shape: no chart may show most of its corners at the top.
    func testOutspokenAnswersNeverSaturateACharts() throws {
        for profile in randomProfiles(count: 500, extremes: true) {
            for test in PersonalityTest.allCases {
                let chart = try XCTUnwrap(PersonalityEstimator.result(for: test, answers: profile)).chart
                switch chart {
                case .spectrum(let dimensions):
                    XCTAssertTrue(dimensions.allSatisfy { $0.percent < 100 }, test.title)
                case .radar(let traits), .enneagram(let traits, _, _):
                    XCTAssertTrue(traits.allSatisfy { $0.percent < 100 }, test.title)
                    XCTAssertLessThanOrEqual(traits.filter { $0.percent >= 90 }.count, 2, test.title)
                case .wheel(let quarters, _, _):
                    let total = quarters.map(\.value).reduce(0, +)
                    XCTAssertTrue(quarters.allSatisfy { $0.value / total < 0.6 }, test.title)
                }
            }
        }
    }

    /// Codes such as OCEAN or HEXACO are spelled out in the info view;
    /// labels that are already words are not repeated.
    func testInfoSpellsOutEveryCodeAndLinksSecurely() throws {
        let expected: [PersonalityTest: Int] = [
            .mbti: 4, .sixteenPersonalities: 5, .predictiveIndex: 4, .bigFive: 5, .hexaco: 6,
            .disc: 4, .insights: 0, .belbin: 9, .enneagram: 9, .tma: 0,
        ]
        for test in PersonalityTest.allCases {
            let result = try XCTUnwrap(PersonalityEstimator.result(for: test, answers: outgoingPlanner))
            XCTAssertEqual(result.legend.count, expected[test], test.title)
            XCTAssertEqual(Set(result.legend.map(\.key)).count, result.legend.count, "\(test.title) keys are unique")
            XCTAssertEqual(test.infoURL.scheme, "https", test.title)
            XCTAssertFalse(test.about.isEmpty, test.title)
        }
        let hexaco = try XCTUnwrap(PersonalityEstimator.result(for: .hexaco, answers: outgoingPlanner))
        XCTAssertEqual(hexaco.legend.map(\.key), ["H", "E", "X", "A", "C", "O"])
    }

    func testEnneagramWingNeighboursItsType() throws {
        for profile in [outgoingPlanner, quietDreamer, answers([:], default: 0.5)] {
            guard case .enneagram(let traits, let type, let wing) = PersonalityEstimator.enneagram(profile).chart else {
                return XCTFail("The enneagram draws as its figure")
            }
            XCTAssertEqual(traits.count, 9)
            XCTAssertTrue((1...9).contains(type))
            let neighbours = [type == 1 ? 9 : type - 1, type == 9 ? 1 : type + 1]
            XCTAssertTrue(neighbours.contains(wing))
        }
    }

    func testUnansweredQuestionsAreLeftOut() {
        let partial = PersonalityAnswers(values: [.talkativeness: 1])
        // One answer is thin evidence: clearly extravert, but not at the end of the scale.
        XCTAssertEqual(PersonalityEstimator.extraversion(partial), 1 / 1.6, accuracy: 1e-9)
        XCTAssertEqual(PersonalityEstimator.intuition(partial), 0)
        XCTAssertEqual(PersonalityEstimator.mbti(partial).headline.first, "E")
    }

    private func lifestyle(_ answers: [ProfileCreationStep: CompatibilityScaleAnswer]) throws -> PersonalityAnswers {
        var lifestyle = LifestyleAnswers()
        for (step, answer) in answers {
            lifestyle[try XCTUnwrap(CompatibilityScaleQuestion.question(for: step))] = answer
        }
        return PersonalityAnswers(lifestyle: lifestyle)
    }

    private func answer(_ own: Int, importance: Int = 3, partner: Int? = nil) -> CompatibilityScaleAnswer {
        CompatibilityScaleAnswer(own: own, partner: partner ?? own, isPartnerCustomized: partner != nil,
                                 importance: importance)
    }

    /// With untouched importance and partner values, only the own answers count.
    func testOwnAnswersAreTheMeasurement() throws {
        let stored = try lifestyle([.talkativeness: answer(5), .aloneTime: answer(2), .punctuality: answer(1)])
        let plain = PersonalityAnswers(values: [.talkativeness: 1, .aloneTime: -0.5, .punctuality: -1])
        XCTAssertEqual(PersonalityEstimator.extraversion(stored), PersonalityEstimator.extraversion(plain), accuracy: 1e-12)
        XCTAssertEqual(PersonalityEstimator.conscientiousness(stored), PersonalityEstimator.conscientiousness(plain),
                       accuracy: 1e-12)
    }

    /// Importance makes an answer count more within its dimension, but a
    /// middle answer stays in the middle however important it is.
    func testImportanceWeighsAnswersWithoutMovingThem() throws {
        let talkerCares = try lifestyle([.talkativeness: answer(5, importance: 5), .nightlife: answer(1, importance: 1)])
        let homebodyCares = try lifestyle([.talkativeness: answer(5, importance: 1), .nightlife: answer(1, importance: 5)])
        XCTAssertGreaterThan(PersonalityEstimator.extraversion(talkerCares), 0)
        XCTAssertLessThan(PersonalityEstimator.extraversion(homebodyCares), 0)

        let neutral = try lifestyle([.talkativeness: answer(3, importance: 5)])
        XCTAssertEqual(PersonalityEstimator.extraversion(neutral), 0)
        let important = try lifestyle([.talkativeness: answer(5, importance: 5)])
        XCTAssertEqual(PersonalityEstimator.extraversion(important), 1.3 / 1.9, accuracy: 1e-9)
        let unimportant = try lifestyle([.talkativeness: answer(5, importance: 1)])
        XCTAssertGreaterThan(PersonalityEstimator.extraversion(unimportant), 0.5)
    }

    /// A hand-set partner wish adds to the user's own need only where the need
    /// is lived together; elsewhere it describes the partner, not the user.
    func testPartnerWishRefinesOnlySharedNeeds() throws {
        let wantsContact = try lifestyle([.texting: answer(3, partner: 5)])
        XCTAssertGreaterThan(PersonalityEstimator.neuroticism(wantsContact), 0)

        let prefilled = try lifestyle([.texting: CompatibilityScaleAnswer(own: 3, partner: 5)])
        XCTAssertEqual(PersonalityEstimator.neuroticism(prefilled), 0)

        let wantsTalker = try lifestyle([.talkativeness: answer(3, partner: 5), .socialPlans: answer(1, partner: 5)])
        XCTAssertEqual(PersonalityEstimator.extraversion(wantsTalker),
                       PersonalityEstimator.extraversion(PersonalityAnswers(values: [.talkativeness: 0, .socialPlans: -1])),
                       accuracy: 1e-12)

        // The own answer stays the larger part.
        let evidence = try XCTUnwrap(PersonalityAnswers.evidence(for: .texting, answer: answer(1, partner: 5)))
        XCTAssertLessThan(evidence.value, 0)
    }

    func testMotionWeavesInCrossesAndUnweaves() throws {
        let first = WelcomeLightPersonality.Visual(kind: .spectrum, values: [0.5, -0.5, 0.2, 0.1])
        let second = WelcomeLightPersonality.Visual(kind: .radar, values: [0.2, 0.9, 0.5, 0.4, 0.7])
        var motion = WelcomeLightPersonality.Motion()
        XCTAssertNil(motion.pose(at: 0))

        motion.update(first, now: 10, animated: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(at: 10.8)).amount, 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(motion.pose(at: 20)).amount, 1)
        XCTAssertEqual(motion.pose(at: 20)?.to, first)

        motion.update(second, now: 20, animated: true)
        let crossing = try XCTUnwrap(motion.pose(at: 20.65))
        XCTAssertEqual(crossing.from, first)
        XCTAssertEqual(crossing.to, second)
        XCTAssertEqual(crossing.cross, 0.5, accuracy: 1e-9)
        XCTAssertEqual(crossing.amount, 1)

        motion.update(nil, now: 30, animated: true)
        XCTAssertEqual(try XCTUnwrap(motion.pose(at: 30.8)).amount, 0.5, accuracy: 1e-9)
        XCTAssertNil(motion.pose(at: 40))

        motion.update(first, now: 50, animated: false)
        let reopened = try XCTUnwrap(motion.pose(at: 50))
        XCTAssertEqual(reopened.amount, 1)
        XCTAssertEqual(reopened.from, first)
    }

    func testSpectrumLayoutStaysInsideTheHelixFrame() {
        for count in 1...6 {
            let rows = (0..<count).map { WelcomeLightPersonality.Spectrum.rowY($0, count: count) }
            XCTAssertTrue(rows.allSatisfy { abs($0) < 0.85 })
            XCTAssertEqual(rows, rows.sorted())
        }
    }

    @MainActor
    func testEveryChartKindRendersAsLightAwayFromTheHelix() throws {
        let resources = try XCTUnwrap(WelcomeLightMetalRenderer.resources)
        let size = CGSize(width: 393, height: 825)
        func brightness(_ pose: WelcomeLightPersonality.Pose?) throws -> [UInt8] {
            var uniforms = WelcomeLightUniforms(presentationElapsed: 40, size: size, pixelScale: 1)
            uniforms.lock = SIMD4(1, 0, 0, 1)
            if let pose { uniforms.apply(pose) }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: 393, height: 825, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.renderTarget, .shaderRead]
            let texture = try XCTUnwrap(resources.device.makeTexture(descriptor: descriptor))
            let emission = try XCTUnwrap(resources.emissionTexture(size: size))
            let target = MTLRenderPassDescriptor()
            target.colorAttachments[0].texture = texture
            target.colorAttachments[0].loadAction = .clear
            target.colorAttachments[0].storeAction = .store
            let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
            resources.render(command: command, target: target, emission: emission, uniforms: &uniforms)
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            var pixels = [UInt8](repeating: 0, count: 393 * 825 * 4)
            texture.getBytes(&pixels, bytesPerRow: 393 * 4, from: MTLRegionMake2D(0, 0, 393, 825), mipmapLevel: 0)
            return pixels
        }
        let helix = try brightness(nil)
        for test in PersonalityTest.allCases {
            let visual = try XCTUnwrap(PersonalityEstimator.result(for: test, answers: outgoingPlanner)).visual
            let chart = try brightness(WelcomeLightPersonality.Pose(amount: 1, cross: 1, from: visual, to: visual))
            var lit = 0, changed = 0
            for offset in stride(from: 0, to: chart.count, by: 4) {
                let value = max(chart[offset], chart[offset + 1], chart[offset + 2])
                if value > 80 { lit += 1 }
                if abs(Int(value) - Int(max(helix[offset], helix[offset + 1], helix[offset + 2]))) > 40 { changed += 1 }
            }
            XCTAssertGreaterThan(lit, 1500, test.title)
            XCTAssertGreaterThan(changed, 1500, test.title)
        }
    }
}
