import UIKit

/// The other person's profile and the whole conversation as an A4 PDF, to
/// take to the police. Made on the phone from what is stored there.
struct MatchReportExport {
    let match: MatchSnapshot
    let messages: [ChatMessage]
    var isDemo = false
    /// The other person's photo, when the phone has one. A match only
    /// carries answers today, so their initial stands in.
    var photo: UIImage? = nil
    var createdAt = Date()

    /// Their own name, not a label given to a saved match.
    var partnerName: String { match.them.displayName }

    var fileName: String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let name = partnerName.components(separatedBy: unsafe).joined()
        let day = createdAt.formatted(.iso8601.year().month().day())
        return "Stop Swiping – \(name) – \(day).pdf"
    }

    func pdfData() -> Data {
        // The first pass only counts pages, so every footer can say "of N".
        let pageCount = render(totalPages: nil).pages
        return render(totalPages: pageCount).data
    }

    /// Writes the PDF where the share sheet can pick it up.
    func writeTemporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReportExports", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try pdfData().write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private func render(totalPages: Int?) -> (data: Data, pages: Int) {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: L10n("Profile and conversation") + " – " + partnerName,
            kCGPDFContextCreator as String: "Stop Swiping",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: PDFPage.bounds, format: format)
        var pages = 0
        let data = renderer.pdfData { context in
            let page = PDFPage(context: context, totalPages: totalPages,
                               footer: L10n("Profile and conversation") + " · " + partnerName)
            draw(on: page)
            pages = page.number
        }
        return (data, pages)
    }

    // MARK: - Content

    private func draw(on page: PDFPage) {
        page.begin()
        drawTitle(on: page)
        drawProfileCard(on: page)
        drawFacts(on: page)
        drawScaleAnswers(on: page)
        drawConversation(on: page)
        page.space(18)
        page.paragraph(L10n("This document was made on your own phone, from the conversation as it is stored there."),
                       font: PDFStyle.font(9), color: PDFStyle.tertiary)
    }

    private func drawTitle(on page: PDFPage) {
        page.paragraph("STOP SWIPING", font: PDFStyle.font(9, .bold), color: PDFStyle.accent, kern: 2)
        page.space(6)
        page.paragraph(L10n("Profile and conversation"), font: PDFStyle.rounded(26, .semibold), color: PDFStyle.ink)
        page.space(4)
        let created = createdAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(AppLocale.current))
        page.paragraph(L10n("Created on \(created)"), font: PDFStyle.font(10), color: PDFStyle.secondary)
        if isDemo {
            page.space(4)
            page.paragraph(L10n("Demo conversation, not a real match"), font: PDFStyle.font(10, .semibold), color: PDFStyle.alert)
        }
        page.space(20)
    }

    private func drawProfileCard(on page: PDFPage) {
        let avatar: CGFloat = 76
        let padding: CGFloat = 18
        let textX = padding + avatar + 18
        let textWidth = page.width - textX - padding

        var lines: [(String, UIFont, UIColor)] = [(partnerName, PDFStyle.rounded(20, .semibold), PDFStyle.ink)]
        let day = CalendarDate.today(calendar: BirthDateRules.calendar, now: match.matchedAt)
        let summary = [match.them.age(on: day).map { L10n("\($0) years") }, match.them.location?.placeName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !summary.isEmpty { lines.append((summary, PDFStyle.font(11), PDFStyle.secondary)) }
        if match.name != partnerName {
            lines.append((L10n("Saved by you as \(match.name)"), PDFStyle.font(10), PDFStyle.secondary))
        }
        let matched = match.matchedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(AppLocale.current))
        lines.append((L10n("Matched on \(matched)"), PDFStyle.font(10), PDFStyle.secondary))
        lines.append((L10n("Average match: \(L10nPercent(match.report.average))"), PDFStyle.font(10, .semibold), PDFStyle.accent))
        if let ended = match.ended {
            let date = ended.at.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current))
            lines.append((L10n("Match ended on \(date)"), PDFStyle.font(10, .semibold), PDFStyle.alert))
        }

        let texts = lines.map { PDFText($0.0, font: $0.1, color: $0.2) }
        let textHeight = texts.reduce(0) { $0 + $1.height(width: textWidth) } + CGFloat(texts.count - 1) * 3
        let height = max(avatar, textHeight) + padding * 2
        page.ensure(height)

        let card = CGRect(x: page.left, y: page.y, width: page.width, height: height)
        PDFStyle.surface.setFill()
        UIBezierPath(roundedRect: card, cornerRadius: 16).fill()

        let circle = CGRect(x: card.minX + padding, y: card.minY + (height - avatar) / 2, width: avatar, height: avatar)
        drawAvatar(in: circle)

        var y = card.minY + (height - textHeight) / 2
        for text in texts {
            y += text.draw(at: CGPoint(x: card.minX + textX, y: y), width: textWidth) + 3
        }
        page.y = card.maxY
        page.space(26)
    }

    private func drawAvatar(in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(ovalIn: rect).addClip()
        if let photo {
            // Fill the circle, cropping the longer side.
            let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
            let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                  width: size.width, height: size.height))
        } else {
            let colors = [PDFStyle.cyan.cgColor, PDFStyle.accent.cgColor, PDFStyle.violet.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                           end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            }
            let initial = PDFText(String(partnerName.prefix(1)).uppercased(), font: PDFStyle.rounded(32, .semibold),
                                  color: .white, alignment: .center)
            let height = initial.height(width: rect.width)
            initial.draw(at: CGPoint(x: rect.minX, y: rect.midY - height / 2), width: rect.width)
        }
        context.restoreGState()
    }

    private func drawFacts(on page: PDFPage) {
        page.sectionTitle(L10n("About \(partnerName)"))
        let titleWidth = page.width * 0.36
        let facts = match.sharedFacts
        for (index, fact) in facts.enumerated() {
            let title = PDFText(fact.title, font: PDFStyle.font(10.5), color: PDFStyle.secondary)
            let value = PDFText(fact.value, font: PDFStyle.font(10.5, .medium), color: PDFStyle.ink)
            let valueWidth = page.width - titleWidth - 12
            let height = max(title.height(width: titleWidth), value.height(width: valueWidth)) + 14
            page.ensure(height)
            title.draw(at: CGPoint(x: page.left, y: page.y + 7), width: titleWidth)
            value.draw(at: CGPoint(x: page.left + titleWidth + 12, y: page.y + 7), width: valueWidth)
            page.y += height
            if index < facts.count - 1 { page.hairline() }
        }
        page.space(22)
    }

    private func drawScaleAnswers(on page: PDFPage) {
        let them = match.them
        for group in CompatibilityScaleQuestion.sections {
            let answered = group.questions.filter { them.lifestyle[$0].own != nil }
            guard !answered.isEmpty else { continue }
            page.sectionTitle(group.title)
            for (index, question) in answered.enumerated() {
                drawScaleRow(question, value: them.lifestyle[question].own ?? 0, on: page)
                if index < answered.count - 1 { page.hairline() }
            }
            page.space(22)
        }
    }

    private func drawScaleRow(_ question: CompatibilityScaleQuestion, value: Int, on page: PDFPage) {
        let scaleWidth: CGFloat = 250
        let dotsWidth: CGFloat = 56
        let gap: CGFloat = 10
        let textWidth = page.width - scaleWidth - 16
        let title = PDFText(question.title, font: PDFStyle.font(10.5, .medium), color: PDFStyle.ink)
        let low = PDFText(question.lowLabel, font: PDFStyle.font(8), color: PDFStyle.secondary)
        let high = PDFText(question.highLabel, font: PDFStyle.font(8), color: PDFStyle.secondary, alignment: .right)
        let labelWidth = (scaleWidth - dotsWidth - gap * 2) / 2
        let labelHeight = max(low.height(width: labelWidth), high.height(width: labelWidth))
        let height = max(title.height(width: textWidth), labelHeight, 12) + 16
        page.ensure(height)

        title.draw(at: CGPoint(x: page.left, y: page.y + 8), width: textWidth)

        let scaleX = page.left + page.width - scaleWidth
        let midY = page.y + height / 2
        low.draw(at: CGPoint(x: scaleX, y: midY - labelHeight / 2), width: labelWidth)
        high.draw(at: CGPoint(x: scaleX + scaleWidth - labelWidth, y: midY - labelHeight / 2), width: labelWidth)
        let range = Array(CompatibilityScaleAnswer.range)
        let dotsX = scaleX + labelWidth + gap
        let step = dotsWidth / CGFloat(max(range.count - 1, 1))
        for (index, position) in range.enumerated() {
            let selected = position == value
            let size: CGFloat = selected ? 9 : 5
            let center = CGPoint(x: dotsX + CGFloat(index) * step, y: midY)
            (selected ? PDFStyle.accent : PDFStyle.dot).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)).fill()
        }
        page.y += height
    }

    private func drawConversation(on page: PDFPage) {
        page.newPage()
        page.sectionTitle(L10n("Conversation"))
        let sorted = messages.sorted { $0.sentAt < $1.sentAt }
        guard let first = sorted.first, let last = sorted.last else {
            page.paragraph(L10n("No messages yet."), font: PDFStyle.font(11), color: PDFStyle.secondary)
            return
        }
        let count = sorted.count == 1 ? L10n("1 message") : L10n("\(sorted.count) messages")
        let from = first.sentAt.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current))
        let to = last.sentAt.formatted(.dateTime.day().month(.wide).year().locale(AppLocale.current))
        page.paragraph(from == to ? "\(count) · \(from)" : "\(count) · \(from) – \(to)",
                       font: PDFStyle.font(10), color: PDFStyle.secondary)
        page.space(8)

        let calendar = Calendar.current
        var previousDay: Date?
        var previousSender: ChatMessage.Sender?
        for message in sorted {
            let day = calendar.startOfDay(for: message.sentAt)
            if day != previousDay {
                drawDaySeparator(message.sentAt, on: page)
                previousDay = day
                previousSender = nil
            }
            drawMessage(message, showsSender: message.sender != previousSender, on: page)
            previousSender = message.sender
        }
    }

    private func drawDaySeparator(_ date: Date, on page: PDFPage) {
        let text = PDFText(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(AppLocale.current)),
                           font: PDFStyle.font(9, .semibold), color: PDFStyle.secondary, alignment: .center)
        let height = text.height(width: page.width) + 22
        // Never leave a date alone at the bottom of a page.
        page.ensure(height + 40)
        text.draw(at: CGPoint(x: page.left, y: page.y + 14), width: page.width)
        page.y += height
    }

    private func drawMessage(_ message: ChatMessage, showsSender: Bool, on page: PDFPage) {
        let time = message.sentAt.formatted(.dateTime.hour().minute().locale(AppLocale.current))
        if message.sender == .system {
            let text = PDFText("\(message.text) · \(time)", font: PDFStyle.italic(9.5), color: PDFStyle.secondary,
                               alignment: .center)
            let height = text.height(width: page.width) + 10
            page.ensure(height)
            text.draw(at: CGPoint(x: page.left, y: page.y + 5), width: page.width)
            page.y += height
            return
        }

        let isMine = message.sender == .currentUser
        let maxBubble = page.width * 0.72
        let padding = CGSize(width: 12, height: 8)
        let sender = isMine ? L10n("You") : partnerName
        let label = PDFText(showsSender ? "\(sender) · \(time)" : time, font: PDFStyle.font(8, .medium),
                            color: PDFStyle.tertiary, alignment: isMine ? .right : .left)
        let labelHeight = label.height(width: maxBubble)
        let font = PDFStyle.font(10.5)
        let color: UIColor = isMine ? .white : PDFStyle.ink

        // A long message continues on the next page instead of running off this one.
        var remaining = message.text
        var isFirstPart = true
        while !remaining.isEmpty {
            let full = PDFText(remaining, font: font, color: color)
            let textWidth = min(full.width(limit: maxBubble - padding.width * 2), maxBubble - padding.width * 2)
            let header = isFirstPart ? labelHeight + 3 : 0
            let needed = header + full.height(width: textWidth) + padding.height * 2
            var part = remaining
            if page.y + needed > page.bottom {
                if page.y + header + padding.height * 2 + 60 > page.bottom || needed <= page.contentHeight {
                    page.newPage()
                }
                if page.y + needed > page.bottom {
                    let room = page.bottom - page.y - header - padding.height * 2
                    part = full.prefix(fitting: room, width: textWidth)
                }
            }
            remaining = String(remaining.dropFirst(part.count)).trimmingLeadingWhitespace

            if isFirstPart {
                let labelX = isMine ? page.left + page.width - maxBubble : page.left
                label.draw(at: CGPoint(x: labelX, y: page.y), width: maxBubble)
                page.y += labelHeight + 3
            }
            let text = PDFText(part, font: font, color: color)
            let width = min(text.width(limit: maxBubble - padding.width * 2), maxBubble - padding.width * 2)
            let bubble = CGSize(width: width + padding.width * 2, height: text.height(width: width) + padding.height * 2)
            let origin = CGPoint(x: isMine ? page.left + page.width - bubble.width : page.left, y: page.y)
            (isMine ? PDFStyle.accent : PDFStyle.surface).setFill()
            UIBezierPath(roundedRect: CGRect(origin: origin, size: bubble), cornerRadius: 12).fill()
            text.draw(at: CGPoint(x: origin.x + padding.width, y: origin.y + padding.height), width: width)
            page.y += bubble.height + 6
            isFirstPart = false
        }
    }
}

// MARK: - Drawing

private enum PDFStyle {
    static let ink = UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1)
    static let secondary = UIColor(red: 0.39, green: 0.41, blue: 0.48, alpha: 1)
    static let tertiary = UIColor(red: 0.56, green: 0.58, blue: 0.64, alpha: 1)
    static let surface = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)
    static let line = UIColor(red: 0.89, green: 0.90, blue: 0.93, alpha: 1)
    static let dot = UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1)
    static let accent = UIColor(red: 0.16, green: 0.32, blue: 1, alpha: 1)
    static let cyan = UIColor(red: 0.20, green: 0.81, blue: 1, alpha: 1)
    static let violet = UIColor(red: 0.61, green: 0.30, blue: 1, alpha: 1)
    static let alert = UIColor(red: 0.85, green: 0.18, blue: 0.36, alpha: 1)

    static func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func italic(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// One block of wrapped text.
private struct PDFText {
    let string: NSAttributedString

    init(_ text: String, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left, kern: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1.5
        string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern,
        ])
    }

    func height(width: CGFloat) -> CGFloat {
        ceil(string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    /// The width the text takes up, at most `limit`.
    func width(limit: CGFloat) -> CGFloat {
        ceil(string.boundingRect(with: CGSize(width: limit, height: .greatestFiniteMagnitude),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).width)
    }

    @discardableResult
    func draw(at point: CGPoint, width: CGFloat) -> CGFloat {
        let height = height(width: width)
        string.draw(with: CGRect(x: point.x, y: point.y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return height
    }

    /// The longest start of the text, ending at a word, that fits `height`.
    func prefix(fitting height: CGFloat, width: CGFloat) -> String {
        let text = string.string
        var low = 1, high = text.count, best = 1
        while low <= high {
            let middle = (low + high) / 2
            let candidate = string.attributedSubstring(from: NSRange(text.startIndex..<text.index(text.startIndex, offsetBy: middle), in: text))
            let fits = ceil(candidate.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height) <= height
            if fits { best = middle; low = middle + 1 } else { high = middle - 1 }
        }
        let cut = text.prefix(best)
        if best < text.count, let space = cut.lastIndex(where: \.isWhitespace), space > cut.startIndex {
            return String(cut[..<space])
        }
        return String(cut)
    }
}

/// Keeps track of where the next thing goes, and starts a new page when it
/// would not fit.
private final class PDFPage {
    static let bounds = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let margin: CGFloat = 48
    private static let footerHeight: CGFloat = 30

    let context: UIGraphicsPDFRendererContext
    let totalPages: Int?
    let footer: String
    private(set) var number = 0
    var y: CGFloat = 0

    var left: CGFloat { Self.margin }
    var width: CGFloat { Self.bounds.width - Self.margin * 2 }
    var bottom: CGFloat { Self.bounds.height - Self.margin - Self.footerHeight }
    var contentHeight: CGFloat { bottom - Self.margin }

    init(context: UIGraphicsPDFRendererContext, totalPages: Int?, footer: String) {
        self.context = context
        self.totalPages = totalPages
        self.footer = footer
    }

    func begin() { newPage() }

    func newPage() {
        context.beginPage()
        number += 1
        y = Self.margin
        drawChrome()
    }

    func ensure(_ height: CGFloat) {
        if y + height > bottom { newPage() }
    }

    func space(_ height: CGFloat) {
        y = min(y + height, bottom)
    }

    func paragraph(_ text: String, font: UIFont, color: UIColor, kern: CGFloat = 0) {
        let block = PDFText(text, font: font, color: color, kern: kern)
        let height = block.height(width: width)
        ensure(height)
        block.draw(at: CGPoint(x: left, y: y), width: width)
        y += height
    }

    func sectionTitle(_ title: String) {
        let text = PDFText(title.uppercased(), font: PDFStyle.font(9, .bold), color: PDFStyle.accent, kern: 1.4)
        let height = text.height(width: width)
        // Keep a title together with at least its first row.
        ensure(height + 50)
        text.draw(at: CGPoint(x: left, y: y), width: width)
        y += height + 6
        PDFStyle.accent.withAlphaComponent(0.35).setFill()
        UIRectFill(CGRect(x: left, y: y, width: width, height: 1))
        y += 4
    }

    func hairline() {
        PDFStyle.line.setFill()
        UIRectFill(CGRect(x: left, y: y, width: width, height: 0.5))
    }

    private func drawChrome() {
        // A thin band of the app's light along the top edge.
        if let cg = UIGraphicsGetCurrentContext(),
           let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [PDFStyle.cyan.cgColor, PDFStyle.accent.cgColor, PDFStyle.violet.cgColor] as CFArray,
                                     locations: [0, 0.5, 1]) {
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: Self.bounds.width, height: 5))
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: Self.bounds.width, y: 0), options: [])
            cg.restoreGState()
        }

        let footerY = Self.bounds.height - Self.margin + 8
        PDFStyle.line.setFill()
        UIRectFill(CGRect(x: left, y: footerY - 10, width: width, height: 0.5))
        let pageLabel = totalPages.map { L10n("Page \(number) of \($0)") } ?? L10n("Page \(number) of \(number)")
        PDFText(footer, font: PDFStyle.font(8), color: PDFStyle.tertiary)
            .draw(at: CGPoint(x: left, y: footerY), width: width * 0.7)
        PDFText(pageLabel, font: PDFStyle.font(8), color: PDFStyle.tertiary, alignment: .right)
            .draw(at: CGPoint(x: left + width * 0.7, y: footerY), width: width * 0.3)
    }
}

private extension String {
    var trimmingLeadingWhitespace: String {
        String(drop(while: \.isWhitespace))
    }
}
