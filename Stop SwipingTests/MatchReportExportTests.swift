import CoreLocation
import PDFKit
import XCTest
@testable import Stop_Swiping

/// The PDF a reporter can take to the police: the other person's profile
/// and every message, the demo conversation included.
@MainActor
final class MatchReportExportTests: XCTestCase {
    override func tearDown() {
        AppLanguageSettings.shared.language = .english
        super.tearDown()
    }

    func testDemoConversationExportsEveryMessageAndTheProfile() throws {
        AppLanguageSettings.shared.language = .dutch
        let match = demoMatch()
        let chat = ChatViewModel.demo(matchID: match.id, name: match.name)
        var messages = chat.conversation.messages
        messages.append(ChatMessage(sender: .currentUser, text: "Hoi! Hoe gaat het?", sentAt: Date().addingTimeInterval(-60)))
        // Longer than a page, so it has to continue on the next one.
        let long = Array(repeating: "Dit is een heel lang bericht dat over meerdere regels loopt.", count: 90).joined(separator: " ")
        messages.append(ChatMessage(sender: .match, text: long + " EINDE", sentAt: Date().addingTimeInterval(-30)))

        let export = MatchReportExport(match: match, messages: messages, isDemo: chat.isDemo)
        let url = try export.writeTemporaryFile()
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(url.lastPathComponent.contains(match.them.displayName))

        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(document.pageCount, 3)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("Profiel en chatgesprek"))
        XCTAssertTrue(text.contains(match.them.displayName))
        XCTAssertTrue(text.contains("Demogesprek"))
        XCTAssertTrue(text.contains("Hoi! Hoe gaat het?"))
        XCTAssertTrue(text.contains("EINDE"), "A message longer than a page must be printed in full.")
        XCTAssertTrue(text.contains("Pagina \(document.pageCount) van \(document.pageCount)"))
        for question in CompatibilityScaleQuestion.all {
            XCTAssertFalse(text.contains(question.subtitle), "Single answers are never exported: \(question.title)")
        }

        if let folder = ProcessInfo.processInfo.environment["REPORT_EXPORT_DIR"] {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try export.pdfData().write(to: URL(fileURLWithPath: folder).appendingPathComponent("report-export.pdf"))
        }
    }

    func testThePhotoIsDrawnIntoThePDF() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 80)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        }
        let match = demoMatch()
        let withPhoto = MatchReportExport(match: match, messages: [], photo: photo).pdfData()
        let withoutPhoto = MatchReportExport(match: match, messages: []).pdfData()
        let imageMarker = Data("/Subtype /Image".utf8)
        XCTAssertNotNil(withPhoto.range(of: imageMarker), "The photo must be in the PDF.")
        XCTAssertNil(withoutPhoto.range(of: imageMarker), "Without a photo, the initial stands in.")
    }

    func testAnEmptyConversationStillExports() throws {
        let export = MatchReportExport(match: demoMatch(), messages: [])
        let document = try XCTUnwrap(PDFDocument(data: export.pdfData()))
        XCTAssertTrue(try XCTUnwrap(document.string).contains("No messages yet."))
    }

    private func demoMatch() -> MatchSnapshot {
        let now = Date()
        var you = ProfileCreationState(today: CalendarDate.today(calendar: BirthDateRules.calendar, now: now),
                                       applicationLanguage: "nl")
        you.displayName = "Jens"
        you.dateOfBirth = CalendarDate(year: 1996, month: 4, day: 21)
        you.partnerAgeRange = PartnerAgeRange(minimum: 24, maximum: 40, isCustomized: true)
        you.heightCentimeters = 182
        you.gender = .man
        you.partnerGenders = [.woman]
        you.languages = ["nl", "en"]
        you.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        for question in CompatibilityScaleQuestion.all {
            you.lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 3, isPartnerCustomized: true, importance: 3)
        }
        var generator = SeededGenerator(seed: 7)
        return DemoMatchGenerator.makeExample(for: you, now: now, using: &generator)
    }
}
