import XCTest
@testable import Stop_Swiping

/// Objecting to a report: the passport or ID card read on the phone, the
/// conversation copy sent with a report, and what the home screen says.
@MainActor
final class ReportObjectionTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 20)

    // MARK: Machine-readable zone (ICAO 9303 specimens)

    func testPassportZoneGivesInitialAndBirthDate() throws {
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "PASSPORT", "Surname / Nom",
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
        ], today: today))
        XCTAssertEqual(zone.documentCode, "P")
        XCTAssertEqual(zone.initial, "A")
        XCTAssertEqual(zone.birthDate, CalendarDate(year: 1974, month: 8, day: 12))
        XCTAssertEqual(zone.expiryDate, CalendarDate(year: 2012, month: 4, day: 15))
        XCTAssertTrue(zone.checkDigitsValid)
    }

    func testIdentityCardZoneHasThreeLines() throws {
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "I<UTOD231458907<<<<<<<<<<<<<<<",
            "7408122F1204159UTO<<<<<<<<<<<6",
            "ERIKSSON<<ANNA<MARIA<<<<<<<<<<",
        ], today: today))
        XCTAssertEqual(zone.documentCode, "I")
        XCTAssertEqual(zone.initial, "A")
        XCTAssertEqual(zone.birthDate, CalendarDate(year: 1974, month: 8, day: 12))
        XCTAssertTrue(zone.checkDigitsValid)
    }

    func testOlderCardWithTwoLinesOf36() throws {
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<",
            "D231458907UTO7408122F1204159<<<<<<<6",
        ], today: today))
        XCTAssertEqual(zone.initial, "A")
        XCTAssertEqual(zone.birthDate, CalendarDate(year: 1974, month: 8, day: 12))
    }

    func testTextRecognitionNoiseIsTolerated() throws {
        // Spaces, a «, dropped trailing fillers and an O read for a 0.
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "p<UTO ERIKSSON«<ANNA<MARIA<<<<<<<<<<<",
            "L898902C36UTO74O8122F1204159ZE184226B<<<<<10",
        ], today: today))
        XCTAssertEqual(zone.birthDate, CalendarDate(year: 1974, month: 8, day: 12))
    }

    func testMisreadBirthDateIsNeverSent() {
        // 740812 read as 740813: the check digit no longer fits.
        XCTAssertNil(MachineReadableZone.parse(lines: [
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408132F1204159ZE184226B<<<<<10",
        ], today: today))
        XCTAssertNil(MachineReadableZone.parse(lines: ["Just a photo of a cat"], today: today))
    }

    func testRecentBirthYearStaysInThisCentury() throws {
        // Born 4 March 2010: 16 on the day of the test.
        let birth = "100304"
        let check = try XCTUnwrap(MachineReadableZone.checkDigit(birth))
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "P<NLDJANSEN<<EMMA<<<<<<<<<<<<<<<<<<<<<<<<<<<",
            "XN1234567<NLD\(birth)\(check)F3001011<<<<<<<<<<<<<<<0",
        ], today: today))
        XCTAssertEqual(zone.birthDate.year, 2010)
        XCTAssertFalse(IDDocumentComparison(zone: zone, displayName: "Emma", birthDate: zone.birthDate, today: today).isAdult)
    }

    func testOnlyInitialAndDatesLeaveThePhone() throws {
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
        ], today: today))
        let json = String(decoding: try JSONEncoder().encode(zone.idCheck), as: UTF8.self)
        XCTAssertTrue(json.contains("\"birth_date\":\"1974-08-12\""))
        XCTAssertTrue(json.contains("\"initial\":\"A\""))
        XCTAssertFalse(json.contains("ERIKSSON"))
        XCTAssertFalse(json.contains("L898902C3"))
    }

    func testComparisonWithProfile() throws {
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
        ], today: today))
        let same = IDDocumentComparison(zone: zone, displayName: " anna", birthDate: zone.birthDate, today: today)
        XCTAssertTrue(same.initialMatches && same.birthDateMatches && same.isAdult)
        XCTAssertTrue(same.isExpired)
        let other = IDDocumentComparison(zone: zone, displayName: "Bram",
                                         birthDate: CalendarDate(year: 1974, month: 8, day: 13), today: today)
        XCTAssertFalse(other.initialMatches)
        XCTAssertFalse(other.birthDateMatches)
        XCTAssertEqual(IDDocumentComparison.initial(of: "Émile"), "E")
        XCTAssertEqual(IDDocumentComparison.age(of: CalendarDate(year: 2008, month: 11, day: 21), on: today), 17)
        XCTAssertEqual(IDDocumentComparison.age(of: CalendarDate(year: 2008, month: 11, day: 20), on: today), 18)
    }

    // MARK: Conversation copy

    func testChatCopyKeepsBothSidesInOrderWithoutSystemLines() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let messages = [
            ChatMessage(sender: .system, text: "You matched", sentAt: start),
            ChatMessage(sender: .currentUser, text: "Hoi", sentAt: start.addingTimeInterval(60)),
            ChatMessage(sender: .match, text: "Hallo", sentAt: start.addingTimeInterval(120)),
        ]
        let copy = ReportChatLine.copy(of: messages)
        XCTAssertEqual(copy.map(\.from), [.reporter, .reported])
        XCTAssertEqual(copy.map(\.text), ["Hoi", "Hallo"])
    }

    func testLongChatKeepsTheNewestMessages() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let messages = (0..<10).map {
            ChatMessage(sender: .match, text: "message \($0) " + String(repeating: "x", count: 100),
                        sentAt: start.addingTimeInterval(Double($0)))
        }
        let copy = ReportChatLine.copy(of: messages, limit: 1_000)
        XCTAssertFalse(copy.isEmpty)
        XCTAssertLessThan(copy.count, 10)
        XCTAssertTrue(copy.last?.text.hasPrefix("message 9") == true)
    }

    // MARK: Home screen

    func testStatusCarriesTheNewestReportAndObjection() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = UUID(), objection = UUID()
        let status = try decoder.decode(ModerationStatus.self, from: Data("""
        {"strikes":1,"strikes_seen":0,"suspended_until":null,"banned":false,
         "latest_report":{"id":"\(report)","reason":"underage","created_at":"2026-11-20T10:00:00Z","objection":null},
         "objection_result":{"id":"\(objection)","decision":"rejected","reason":"spam"}}
        """.utf8))
        XCTAssertEqual(status.latestReport?.id, report)
        XCTAssertEqual(status.latestReport?.reportReason, .underage)
        XCTAssertTrue(status.canObject)
        XCTAssertEqual(status.objectionResult?.decision, .rejected)
        XCTAssertFalse(status.isAdmin)

        let pending = try decoder.decode(ModerationStatus.self, from: Data("""
        {"strikes":1,"strikes_seen":1,"latest_report":{"id":"\(report)","reason":"spam","objection":"pending"}}
        """.utf8))
        XCTAssertFalse(pending.canObject)
        XCTAssertTrue(pending.awaitsDecision)
        XCTAssertTrue(ModerationCard.isShown(pending, isUnread: false), "A pending objection stays in view")
    }

    func testOldCachedStatusStillDecodes() throws {
        let status = try JSONDecoder().decode(ModerationStatus.self, from: Data("""
        {"strikes":2,"strikesSeen":1,"banned":false}
        """.utf8))
        XCTAssertNil(status.latestReport)
        XCTAssertFalse(status.canObject)
    }

    func testNoticesNameTheReasonAndTheNextStep() {
        let report = ModerationStatus.LatestReport(id: UUID(), reason: "harassment", objection: nil)
        let warning = ModerationStatus(strikes: 1, strikesSeen: 0, suspendedUntil: nil, banned: false, latestReport: report)
        XCTAssertTrue(ModerationCard.message(warning).contains(ReportReason.harassment.title))
        XCTAssertTrue(ModerationCard.message(warning).contains("7"))
        let blocked = ModerationStatus(strikes: 2, strikesSeen: 1, suspendedUntil: Date().addingTimeInterval(86_400),
                                       banned: false, latestReport: report)
        XCTAssertTrue(ModerationCard.message(blocked).contains(ReportReason.harassment.title))
        XCTAssertTrue(ModerationCard.isLocked(blocked))
    }
}
