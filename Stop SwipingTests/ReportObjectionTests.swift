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

    func testEveryGivenNameCountsForTheInitial() throws {
        // ANNA MARIA may go by Maria.
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
            "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
        ], today: today))
        XCTAssertEqual(zone.initials, ["A", "M"])
        XCTAssertTrue(IDDocumentComparison(zone: zone, displayName: "Maria", birthDate: zone.birthDate, today: today).initialMatches)
        XCTAssertFalse(IDDocumentComparison(zone: zone, displayName: "Eriksson", birthDate: zone.birthDate, today: today).initialMatches)
        let json = String(decoding: try JSONEncoder().encode(zone.idCheck), as: UTF8.self)
        XCTAssertTrue(json.contains("\"initials\":[\"A\",\"M\"]"))
    }

    // MARK: Live scan

    func testFillersReadAsKAreRepaired() throws {
        XCTAssertEqual(MachineReadableZone.repairedFillers("ERIKSSON<<ANNA<MARIA<<<K<<KK<<<"),
                       "ERIKSSON<<ANNA<MARIA<<<<<<<<<<<")
        // A name ending in K keeps it; fillers start at a <.
        XCTAssertEqual(MachineReadableZone.repairedFillers("DE<VRIES<<DIRK<<<<<<"), "DE<VRIES<<DIRK<<<<<<")
        let zone = try XCTUnwrap(MachineReadableZone.parse(lines: [
            "I<UTOD231458907<<<<<<<<<<<<<<<",
            "7408122F1204159UTO<<<<<<<<<<<6",
            "ERIKSSON<<ANNA<MARIA<<<K<<KK<<",
        ], today: today))
        XCTAssertEqual(zone.initials, ["A", "M"])
    }

    func testPiecesOfOneLineAreJoinedLeftToRight() throws {
        // Vision splits the names line at its fillers and lists the pieces
        // out of order; the numbers line sits lower (smaller y).
        let pieces = [
            RecognisedTextRows.Piece(text: "<<<<<<<<<<<<<<<<<<<", box: CGRect(x: 0.6, y: 0.402, width: 0.35, height: 0.05)),
            RecognisedTextRows.Piece(text: "L898902C36UTO7408122F1204159ZE184226B<<<<<10",
                                     box: CGRect(x: 0.05, y: 0.3, width: 0.9, height: 0.05)),
            RecognisedTextRows.Piece(text: "P<UTOERIKSSON<<ANNA<MARIA", box: CGRect(x: 0.05, y: 0.4, width: 0.5, height: 0.05)),
        ]
        let lines = RecognisedTextRows.join(pieces)
        XCTAssertEqual(lines, ["P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
                               "L898902C36UTO7408122F1204159ZE184226B<<<<<10"])
        XCTAssertNotNil(MachineReadableZone.parse(lines: lines, today: today))
    }

    func testLiveScanNeedsTwoMatchingReads() {
        let lines = ["P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", "L898902C36UTO7408122F1204159ZE184226B<<<<<10"]
        let misread = ["P<UTOERIKSSON<<HANNA<MARIA<<<<<<<<<<<<<<<<<<", lines[1]]
        var reader = MachineReadableZoneReader()
        XCTAssertNil(reader.observe(lines: lines, today: today))
        XCTAssertNil(reader.observe(lines: misread, today: today), "A different initial starts over")
        XCTAssertNil(reader.observe(lines: ["blurry"], today: today))
        XCTAssertNil(reader.observe(lines: lines, today: today))
        XCTAssertEqual(reader.observe(lines: lines, today: today)?.initials, ["A", "M"])

        // A wrong document-number check digit never counts, however often.
        var strict = MachineReadableZoneReader()
        let badNumber = [lines[0], "L898902C37UTO7408122F1204159ZE184226B<<<<<10"]
        XCTAssertNil(strict.observe(lines: badNumber, today: today))
        XCTAssertNil(strict.observe(lines: badNumber, today: today))
    }

    func testZoneLinesAreRecognisedBeforeTheyRead() {
        XCTAssertTrue(MachineReadableZone.looksLikeZoneLine("L898902C36UTO74O8I22F12O4159ZE184226B<<<<<10"))
        XCTAssertFalse(MachineReadableZone.looksLikeZoneLine("KONINKRIJK DER NEDERLANDEN"))
    }

    func testCameraZoomsInOnlyWhenTooCloseToFocus() {
        // About 70° across; 200 mm closest focus, like recent Pro iPhones.
        let zoom = IDDocumentCamera.zoomFactor(minimumFocusDistance: 200, fieldOfView: 70, maximum: 10)
        XCTAssertGreaterThan(zoom, 1.3)
        XCTAssertLessThan(zoom, 2.2)
        XCTAssertEqual(IDDocumentCamera.zoomFactor(minimumFocusDistance: 80, fieldOfView: 70, maximum: 10), 1)
        XCTAssertEqual(IDDocumentCamera.zoomFactor(minimumFocusDistance: -1, fieldOfView: 70, maximum: 10), 1)
        XCTAssertEqual(IDDocumentCamera.zoomFactor(minimumFocusDistance: 2000, fieldOfView: 70, maximum: 10), 3)
    }

    func testOnlyWhatTheFrameShowsIsRead() {
        // Upright 1080 × 1920 video in a 1.5 : 1 frame: full width, a band of the height.
        let region = IDDocumentCamera.visibleRegion(bufferAspect: 1080 / 1920, frameAspect: 1.5)
        XCTAssertEqual(region.width, 1)
        XCTAssertEqual(region.height, 0.375, accuracy: 0.001)
        XCTAssertEqual(region.midY, 0.5, accuracy: 0.001)
        let landscape = IDDocumentCamera.visibleRegion(bufferAspect: 1920 / 1080, frameAspect: 1.5)
        XCTAssertEqual(landscape.height, 1)
        XCTAssertEqual(landscape.midX, 0.5, accuracy: 0.001)
    }

    func testScanScreenMovesFromSearchingToRead() {
        let model = IDDocumentScanViewModel()
        let lines = ["P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", "L898902C36UTO7408122F1204159ZE184226B<<<<<10"]
        model.observe(["Some unrelated text"])
        XCTAssertEqual(model.phase, .searching)
        model.observe([lines[0], "L898902C36UTO7408132F1204159ZE184226B<<<<<10"])
        XCTAssertEqual(model.phase, .holdStill, "Lines of <<< in view but not read yet")
        model.observe(lines)
        XCTAssertNil(model.outcome)
        model.observe(lines)
        XCTAssertEqual(model.outcome?.isRead, true)
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
        XCTAssertEqual(ModerationHome.resolve(pending, isUnread: false, result: nil)?.status?.title,
                       ModerationCopy.status(pending).title, "A pending objection stays in view")
        XCTAssertNil(ModerationHome.resolve(pending, isUnread: false, result: nil)?.notice,
                     "Once read, it leaves the profile buttons alone")
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
        let notice = ModerationCopy.strike(warning)
        XCTAssertEqual(notice.reason, ReportReason.harassment.title)
        XCTAssertTrue(notice.message.contains("7"))
        XCTAssertTrue(notice.canObject)
        let blocked = ModerationStatus(strikes: 2, strikesSeen: 1, suspendedUntil: Date().addingTimeInterval(86_400),
                                       banned: false, latestReport: report)
        XCTAssertEqual(ModerationCopy.strike(blocked).reason, ReportReason.harassment.title)
        XCTAssertTrue(ModerationCopy.isLocked(blocked))
    }

    func testManualReviewSendsNoIDDetails() throws {
        let json = String(decoding: try JSONEncoder().encode(AgeProof.manualReview), as: UTF8.self)
        XCTAssertTrue(json.contains("\"manual_review\":true") && json.contains("\"photo_attached\":true"))
        XCTAssertFalse(json.contains("birth") || json.contains("initial"))
        let check = ReportIDCheck(initial: "A", birthDate: "1974-08-12", expires: nil, document: "P", checkDigits: true)
        let sorted = JSONEncoder()
        sorted.outputFormatting = .sortedKeys
        XCTAssertEqual(try sorted.encode(AgeProof.document(check)), try sorted.encode(check),
                       "A document is sent exactly as before")
    }

    func testUnderEighteenLocksWithoutUnderstood() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = UUID()
        let locked = try decoder.decode(ModerationStatus.self, from: Data("""
        {"strikes":0,"strikes_seen":0,"banned":false,"latest_report":null,"age_locked":true,
         "age_check":{"id":"\(report)","is_demo":false,"objection":null}}
        """.utf8))
        XCTAssertTrue(locked.needsAgeProof)
        XCTAssertTrue(locked.isLocked())
        XCTAssertFalse(locked.canObject, "It is not a strike to object to")
        let notice = try XCTUnwrap(ModerationHome.resolve(locked, isUnread: false, result: nil)?.notice)
        XCTAssertEqual(notice.kind, .ageCheck, "Even when read, the age check stays in front")
        XCTAssertEqual(notice.title, L10n("You were reported"), "The button already says to confirm the age")
        XCTAssertEqual(locked.ageCheck?.report.reportReason, .underage)

        let pending = ModerationStatus(strikes: 0, strikesSeen: 0, suspendedUntil: nil, banned: false,
                                       ageCheck: .init(id: report, objection: .pending), ageLocked: true)
        XCTAssertFalse(pending.needsAgeProof)
        XCTAssertTrue(pending.awaitsDecision)
        XCTAssertEqual(ModerationHome.resolve(pending, isUnread: false, result: nil)?.status?.title,
                       L10n("Age check under review"))

        let confirmed = ModerationStatus.ObjectionResult(id: UUID(), decision: .approved, reason: "underage")
        XCTAssertEqual(ModerationCopy.result(confirmed).title, L10n("Your age is confirmed"))
    }

    func testARejectionThatBansSaysSo() {
        let rejected = ModerationStatus.ObjectionResult(id: UUID(), decision: .rejected, reason: "harassment")
        let banned = ModerationStatus(strikes: 1, strikesSeen: 1, suspendedUntil: nil, banned: true, banReason: .direct)
        XCTAssertEqual(ModerationCopy.result(rejected, status: banned).message, L10n("Your account is now permanently blocked."))
        XCTAssertNotEqual(ModerationCopy.result(rejected).message, L10n("Your account is now permanently blocked."))
    }

    func testBansSayWhy() throws {
        let device = try JSONDecoder().decode(ModerationStatus.self, from: Data("""
        {"strikes":0,"strikes_seen":0,"banned":true,"ban_reason":"device"}
        """.utf8))
        XCTAssertEqual(device.banReason, .device)
        XCTAssertTrue(ModerationCopy.isLocked(device))
        let status = try XCTUnwrap(ModerationHome.resolve(device, isUnread: false, result: nil)?.status)
        XCTAssertEqual(status.message, ModerationCopy.banMessage(.device))
        XCTAssertFalse(status.canObject)
        XCTAssertNotEqual(ModerationCopy.banMessage(.direct), ModerationCopy.banMessage(.strikes))
    }

    func testTheStrikeNoticeLeavesObjectingToTheButton() {
        let report = ModerationStatus.LatestReport(id: UUID(), reason: "spam", objection: nil)
        let warning = ModerationStatus(strikes: 1, strikesSeen: 0, suspendedUntil: nil, banned: false, latestReport: report)
        let notice = ModerationCopy.strike(warning)
        XCTAssertNil(notice.nextStep)
        XCTAssertFalse(notice.message.localizedCaseInsensitiveContains(L10n("Object")))
        XCTAssertTrue(notice.canObject)
    }

    func testAdminReviewDecodesTheReportAtTheTopLevel() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let id = UUID()
        let review = try decoder.decode(AdminReview.self, from: Data("""
        {"id":"\(id)","reason":"offlineBehavior","details":"","created_at":"2026-11-20T09:00:00Z",
         "ended_match":false,"is_demo":false,"display_name":"Bram","strike":2,"chat_copy":null}
        """.utf8))
        XCTAssertEqual(review.id, id)
        XCTAssertEqual(review.report.strike, 2)
        XCTAssertEqual(review.displayName, "Bram")
    }

    func testANoticeOverrulesTheHomeScreenUntilItIsRead() {
        let report = ModerationStatus.LatestReport(id: UUID(), reason: "spam", objection: nil)
        let warning = ModerationStatus(strikes: 1, strikesSeen: 0, suspendedUntil: nil, banned: false, latestReport: report)
        XCTAssertNotNil(ModerationHome.resolve(warning, isUnread: true, result: nil)?.notice)
        XCTAssertNil(ModerationHome.resolve(warning, isUnread: false, result: nil), "A read warning leaves the home screen as it was")

        let blocked = ModerationStatus(strikes: 2, strikesSeen: 2, suspendedUntil: Date().addingTimeInterval(86_400),
                                       banned: false, latestReport: report)
        let status = ModerationHome.resolve(blocked, isUnread: false, result: nil)?.status
        XCTAssertNotNil(status, "A block stays where automatic matching was")
        XCTAssertEqual(status?.canObject, true)

        let result = ModerationStatus.ObjectionResult(id: UUID(), decision: .rejected, reason: "spam")
        XCTAssertEqual(ModerationHome.resolve(warning, isUnread: true, result: result)?.notice?.kind, .objectionResult,
                       "The outcome of the older objection comes before the newer report")
    }
}
