import Foundation
import UIKit
import Vision

/// The machine-readable zone (the lines with `<<<`) of a passport or ID
/// card, read on this phone to dispute a "may be under 18" report. Only the
/// first initial, the birth date and the expiry date are kept; the photo
/// never leaves the phone.
struct MachineReadableZone: Equatable {
    /// "P" for a passport, "I", "A" or "C" (often with a second letter) for an ID card.
    let documentCode: String
    /// First letter of the first given name, A–Z.
    let initial: String
    let birthDate: CalendarDate
    let expiryDate: CalendarDate?
    /// The document number, birth date and expiry date all pass their check digits.
    let checkDigitsValid: Bool

    var idCheck: ReportIDCheck {
        ReportIDCheck(initial: initial, birthDate: Self.iso(birthDate), expires: expiryDate.map { Self.iso($0) },
                      document: documentCode, checkDigits: checkDigitsValid)
    }

    static func iso(_ date: CalendarDate) -> String {
        String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    // MARK: Parsing

    /// Finds a passport (2 × 44), ID card (3 × 30) or older card (2 × 36)
    /// among recognised text lines, top to bottom. Nil when none reads
    /// cleanly: the birth date must pass its check digit, so a misread
    /// date is never sent.
    static func parse(lines raw: [String], today: CalendarDate = .today()) -> MachineReadableZone? {
        let lines = raw.map { clean($0) }.filter { $0.count >= 15 && $0.contains("<") }
        guard !lines.isEmpty else { return nil }
        for index in lines.indices {
            let rest = Array(lines[index...])
            if rest.count >= 3, let zone = td1(rest[0], rest[1], rest[2], today: today) { return zone }
            if rest.count >= 2, let zone = twoLine(rest[0], rest[1], length: 44, today: today) { return zone }
            if rest.count >= 2, let zone = twoLine(rest[0], rest[1], length: 36, today: today) { return zone }
        }
        return nil
    }

    /// Upper case, `«` as `<`, nothing but A–Z, 0–9 and `<`.
    static func clean(_ line: String) -> String {
        let upper = line.uppercased().replacingOccurrences(of: "«", with: "<")
        return String(upper.unicodeScalars.filter { scalar in
            ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "<"
        }.map(Character.init))
    }

    /// Text recognition drops trailing fillers and sometimes adds a stray
    /// character; anything further off is not this format.
    /// A names line may lose a long run of fillers, so it is padded from
    /// any length; the numbers line decides the format.
    private static func fitted(_ line: String, to length: Int, isNames: Bool = false) -> String? {
        if line.count == length { return line }
        if line.count < length, line.count >= (isNames ? 8 : length - 6) {
            return line + String(repeating: "<", count: length - line.count)
        }
        if line.count > length, line.count <= length + 2 { return String(line.prefix(length)) }
        return nil
    }

    /// TD3 (passport, 44) and TD2 (36): names on the first line, numbers on the second.
    private static func twoLine(_ first: String, _ second: String, length: Int, today: CalendarDate) -> MachineReadableZone? {
        guard let l1 = fitted(first, to: length, isNames: true), let l2 = fitted(second, to: length),
              let code = l1.first, "PIAC".contains(code) else { return nil }
        let chars = Array(l2)
        let number = String(chars[0..<9]), numberCheck = chars[9]
        let birth = digits(String(chars[13..<19])), birthCheck = digit(chars[19])
        let expiry = digits(String(chars[21..<27])), expiryCheck = digit(chars[27])
        guard checkDigit(birth) == birthCheck, let birthDate = date(birth, isBirth: true, today: today),
              let initial = initial(names: String(l1.dropFirst(5))) else { return nil }
        let expiryDate = date(expiry, isBirth: false, today: today)
        let valid = checkDigit(number) == digit(numberCheck) && checkDigit(expiry) == expiryCheck
        return MachineReadableZone(documentCode: documentCode(l1), initial: initial, birthDate: birthDate,
                                   expiryDate: expiryDate, checkDigitsValid: valid)
    }

    /// TD1 (ID card, 3 × 30): numbers on the first two lines, names on the third.
    private static func td1(_ first: String, _ second: String, _ third: String, today: CalendarDate) -> MachineReadableZone? {
        guard let l1 = fitted(first, to: 30), let l2 = fitted(second, to: 30), let l3 = fitted(third, to: 30, isNames: true),
              let code = l1.first, "IAC".contains(code) else { return nil }
        let top = Array(l1), middle = Array(l2)
        let number = String(top[5..<14]), numberCheck = top[14]
        let birth = digits(String(middle[0..<6])), birthCheck = digit(middle[6])
        let expiry = digits(String(middle[8..<14])), expiryCheck = digit(middle[14])
        guard checkDigit(birth) == birthCheck, let birthDate = date(birth, isBirth: true, today: today),
              let initial = initial(names: l3) else { return nil }
        let expiryDate = date(expiry, isBirth: false, today: today)
        let valid = checkDigit(number) == digit(numberCheck) && checkDigit(expiry) == expiryCheck
        return MachineReadableZone(documentCode: documentCode(l1), initial: initial, birthDate: birthDate,
                                   expiryDate: expiryDate, checkDigitsValid: valid)
    }

    private static func documentCode(_ line: String) -> String {
        String(line.prefix(2)).replacingOccurrences(of: "<", with: "")
    }

    /// `SURNAME<<GIVEN<NAMES`: the first letter of the first given name.
    private static func initial(names: String) -> String? {
        guard let separator = names.range(of: "<<") else { return nil }
        let given = names[separator.upperBound...].drop { $0 == "<" }
        guard let letter = given.first, ("A"..."Z").contains(String(letter)) else { return nil }
        return String(letter)
    }

    /// Letters text recognition mistakes for digits in a numeric field.
    private static func digits(_ field: String) -> String {
        let fixes: [Character: Character] = ["O": "0", "Q": "0", "D": "0", "I": "1", "L": "1", "Z": "2",
                                              "S": "5", "B": "8", "G": "6", "T": "7"]
        return String(field.map { fixes[$0] ?? $0 })
    }

    private static func digit(_ character: Character) -> Int? {
        Int(String(digits(String(character))))
    }

    /// ICAO 9303: weights 7, 3, 1; A = 10 … Z = 35; `<` = 0.
    static func checkDigit(_ field: String) -> Int? {
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in field.enumerated() {
            let value: Int
            if let number = character.wholeNumberValue { value = number }
            else if character == "<" { value = 0 }
            else if let ascii = character.asciiValue, (65...90).contains(ascii) { value = Int(ascii) - 55 }
            else { return nil }
            sum += value * weights[index % 3]
        }
        return sum % 10
    }

    /// YYMMDD. A birth year in the future belongs to the previous century.
    private static func date(_ field: String, isBirth: Bool, today: CalendarDate) -> CalendarDate? {
        guard field.count == 6, let yy = Int(field.prefix(2)), let mm = Int(field.dropFirst(2).prefix(2)),
              let dd = Int(field.suffix(2)), (1...12).contains(mm), (1...31).contains(dd) else { return nil }
        var year = 2000 + yy
        if isBirth { if year > today.year { year -= 100 } } else if yy >= 70 { year -= 100 }
        let date = CalendarDate(year: year, month: mm, day: dd)
        return BirthDateRules.exists(date) ? date : nil
    }
}

/// Compares a read document with this phone's own profile, for the
/// objection screen. The server makes the same comparison itself.
struct IDDocumentComparison: Equatable {
    let initialMatches: Bool
    let birthDateMatches: Bool
    let isAdult: Bool
    let isExpired: Bool

    init(zone: MachineReadableZone, displayName: String, birthDate: CalendarDate, today: CalendarDate = .today()) {
        initialMatches = Self.initial(of: displayName) == zone.initial
        birthDateMatches = zone.birthDate == birthDate
        isAdult = Self.age(of: zone.birthDate, on: today) >= 18
        isExpired = zone.expiryDate.map { ($0.year, $0.month, $0.day) < (today.year, today.month, today.day) } ?? false
    }

    /// "Émile" → "E", like the server's `initial_of`.
    static func initial(of name: String) -> String? {
        let folded = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
        return folded.first.map(String.init)
    }

    static func age(of birth: CalendarDate, on day: CalendarDate) -> Int {
        let hadBirthday = (day.month, day.day) >= (birth.month, birth.day)
        return day.year - birth.year - (hadBirthday ? 0 : 1)
    }
}

/// Reads the machine-readable zone from a photo, on this phone.
enum IDDocumentScanner {
    static func read(_ image: UIImage) async -> MachineReadableZone? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines = await recognisedLines(cgImage, orientation: orientation)
        return MachineReadableZone.parse(lines: lines)
    }

    private static func recognisedLines(_ cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // The zone is not language: correction would "fix" it.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            // Top to bottom: Vision's origin is the bottom left.
            return (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
