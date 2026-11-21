import Foundation
import CoreGraphics

/// The machine-readable zone (the lines with `<<<`) of a passport or ID
/// card, read on this phone to dispute a "may be under 18" report. Only the
/// given names' initials, the birth date and the expiry date are kept; the
/// photo never leaves the phone.
struct MachineReadableZone: Equatable {
    /// "P" for a passport, "I", "A" or "C" (often with a second letter) for an ID card.
    let documentCode: String
    /// First letter of every given name, A–Z, in order: someone called Jan
    /// Pieter may go by Pieter.
    let initials: [String]
    let birthDate: CalendarDate
    let expiryDate: CalendarDate?
    /// The document number, birth date and expiry date all pass their check digits.
    let checkDigitsValid: Bool

    /// First letter of the first given name.
    var initial: String { initials[0] }

    var idCheck: ReportIDCheck {
        ReportIDCheck(initial: initial, initials: initials, birthDate: Self.iso(birthDate),
                      expires: expiryDate.map { Self.iso($0) }, document: documentCode, checkDigits: checkDigitsValid)
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
        let lines = raw.map { repairedFillers(clean($0)) }.filter { $0.count >= 15 && $0.contains("<") }
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

    /// A long run of fillers is sometimes read with a K among the `<`: a
    /// tail of nothing but `<` and K, holding at least three `<`, is all
    /// fillers. It starts at a `<`, so a name ending in K keeps its K.
    static func repairedFillers(_ line: String) -> String {
        let characters = Array(line)
        for start in characters.indices where characters[start] == "<" {
            let tail = characters[start...]
            guard tail.allSatisfy({ $0 == "<" || $0 == "K" }) else { continue }
            guard tail.filter({ $0 == "<" }).count >= 3 else { break }
            return String(characters[..<start]) + String(repeating: "<", count: tail.count)
        }
        return line
    }

    /// Looks like a line of the zone: long, with fillers in it. Enough of
    /// these in view means the document is there and only needs a sharp frame.
    static func looksLikeZoneLine(_ line: String) -> Bool {
        let cleaned = repairedFillers(clean(line))
        return cleaned.count >= 25 && cleaned.filter { $0 == "<" }.count >= 2
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
              let initials = initials(names: String(l1.dropFirst(5))) else { return nil }
        let expiryDate = date(expiry, isBirth: false, today: today)
        let valid = checkDigit(number) == digit(numberCheck) && checkDigit(expiry) == expiryCheck
        return MachineReadableZone(documentCode: documentCode(l1), initials: initials, birthDate: birthDate,
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
              let initials = initials(names: l3) else { return nil }
        let expiryDate = date(expiry, isBirth: false, today: today)
        let valid = checkDigit(number) == digit(numberCheck) && checkDigit(expiry) == expiryCheck
        return MachineReadableZone(documentCode: documentCode(l1), initials: initials, birthDate: birthDate,
                                   expiryDate: expiryDate, checkDigitsValid: valid)
    }

    private static func documentCode(_ line: String) -> String {
        String(line.prefix(2)).replacingOccurrences(of: "<", with: "")
    }

    /// `SURNAME<<GIVEN<NAMES`: the first letter of each given name, in
    /// order. Nil without a readable first given name.
    private static func initials(names: String) -> [String]? {
        guard let separator = names.range(of: "<<") else { return nil }
        let given = names[separator.upperBound...].split(separator: "<", omittingEmptySubsequences: true)
        var letters: [String] = []
        for name in given {
            guard let letter = name.first, ("A"..."Z").contains(String(letter)) else { break }
            if !letters.contains(String(letter)) { letters.append(String(letter)) }
        }
        return letters.isEmpty ? nil : letters
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

/// Compares a read document with this phone's own profile. The server makes
/// the same comparison itself; the verification screen never shows it, so
/// nobody can try documents until one passes.
struct IDDocumentComparison: Equatable {
    let initialMatches: Bool
    let birthDateMatches: Bool
    let isAdult: Bool
    let isExpired: Bool

    init(zone: MachineReadableZone, displayName: String, birthDate: CalendarDate, today: CalendarDate = .today()) {
        // Any given name counts: "Jan Pieter" may go by Pieter.
        initialMatches = Self.initial(of: displayName).map(zone.initials.contains) ?? false
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

/// Reads from the live camera: a document counts once two frames read it
/// the same way and every check digit passes. The names have no check
/// digit, so the second, identical read keeps a misread initial from being
/// sent.
struct MachineReadableZoneReader {
    private var previous: MachineReadableZone?
    private(set) var result: MachineReadableZone?

    /// The recognised lines of one camera frame, top to bottom.
    mutating func observe(lines: [String], today: CalendarDate = .today()) -> MachineReadableZone? {
        guard result == nil else { return result }
        guard let zone = MachineReadableZone.parse(lines: lines, today: today), zone.checkDigitsValid else { return nil }
        if zone == previous { result = zone } else { previous = zone }
        return result
    }
}

/// Text recognition splits a long line of `<<<` into pieces and returns
/// them in no particular order. Pieces whose centres share a row are joined
/// left to right; rows come top to bottom.
nonisolated enum RecognisedTextRows {
    struct Piece: Sendable {
        let text: String
        /// Vision's normalised box: origin bottom left.
        let box: CGRect
    }

    static func join(_ pieces: [Piece]) -> [String] {
        var rows: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = rows.last?.first,
               abs(first.box.midY - piece.box.midY) < min(first.box.height, piece.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined() }
    }
}
