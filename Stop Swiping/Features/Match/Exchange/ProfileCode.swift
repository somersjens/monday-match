import CoreLocation
import Foundation

/// A whole shared profile, sealed (`ProfileSeal`) and packed small enough
/// for one QR code. Whoever scans it gets the same profile an exchange
/// between two phones delivers, without a connection of any kind. The app
/// compares it with its own profile once and keeps only the outcome; the
/// answers themselves are never shown and never stored.
///
/// The code holds a web link that belongs to the app, so the system camera
/// opens the app with it, and sends people who don't have the app to a page
/// that leads to the App Store. The sealed bytes sit behind the `#`, the part
/// of a link a browser never sends to the website. Inside the seal: when it
/// was sealed, who sealed it (`ProfileHolder`), and the answers as bits in a
/// fixed order; every table below is part of the format and is only ever
/// appended to.
///
/// The same sealed bytes travel over the radio and as the server's match
/// card. Only a code read from a camera or a link expires (`codeLifetime`):
/// a screenshot passed around stops working, while a match made from it
/// keeps its outcome for good.
enum ProfileCode {
    static let formatVersion = Int(ProfileSeal.version)
    /// The version of the bit layout inside the seal.
    static let packingVersion = 3
    /// Matches the associated domain in the entitlements, and the site's
    /// `apple-app-site-association`.
    static let webHost = "www.hakketjak.com"
    static let webPath = "/stop-swiping/code"
    /// The app's own scheme, which the web page falls back on.
    static let scheme = "stopswiping"
    static let host = "code"
    /// How long a code read from a camera or link is accepted after it was
    /// made. A code on screen is made afresh every time it is shown, so it
    /// lasts a whole event; a screenshot of it doesn't last longer.
    static let codeLifetime: TimeInterval = 24 * 60 * 60
    /// Phones whose clocks run a little ahead are still believed.
    static let clockTolerance: TimeInterval = 60 * 60
    /// When a code was sealed, in whole minutes since 1 January 2026 UTC:
    /// three bytes last until 2057.
    static let timestampEpoch = Date(timeIntervalSince1970: 1_767_225_600)
    static let timestampBytes = 3

    /// A profile that came from another phone, and who sent it.
    struct Received: Equatable {
        let profile: ProfileCreationState
        let holder: ProfileHolder
        let sealedAt: Date
    }

    // MARK: - Sealing

    /// The sealed bytes for a QR code, the radio or the server.
    static func sealed(_ profile: ProfileCreationState, holder: ProfileHolder = .current,
                       today: CalendarDate = .today(), now: Date = Date(), nonce: Data? = nil) -> Data? {
        guard let packed = encoded(profile, today: today) else { return nil }
        var plaintext = Data()
        let minutes = min(max(Int(now.timeIntervalSince(timestampEpoch) / 60), 0), (1 << (8 * timestampBytes)) - 1)
        plaintext += (0..<timestampBytes).reversed().map { UInt8(truncatingIfNeeded: minutes >> (8 * $0)) }
        plaintext += holder.bytes
        plaintext += packed
        return ProfileSeal.seal(plaintext, nonce: nonce)
    }

    /// What `sealed` made, or nil. With `expires`, a code older than
    /// `codeLifetime` is refused too.
    static func opened(_ data: Data, today: CalendarDate = .today(), now: Date = Date(),
                       expires: Bool) -> Received? {
        guard let plaintext = ProfileSeal.open(data), plaintext.count > timestampBytes + ProfileHolder.byteCount
        else { return nil }
        let bytes = Array(plaintext)
        let minutes = bytes[0..<timestampBytes].reduce(0) { $0 << 8 | Int($1) }
        let sealedAt = timestampEpoch.addingTimeInterval(TimeInterval(minutes * 60))
        if expires {
            let age = now.timeIntervalSince(sealedAt)
            guard age <= codeLifetime, age >= -clockTolerance else { return nil }
        }
        let holder = ProfileHolder(bytes: Data(bytes[timestampBytes..<(timestampBytes + ProfileHolder.byteCount)]))
        guard let profile = decoded(Data(bytes[(timestampBytes + ProfileHolder.byteCount)...]), today: today,
                                    completedAt: sealedAt) else { return nil }
        return Received(profile: profile, holder: holder, sealedAt: sealedAt)
    }

    /// The match card the server keeps for the partner, as text.
    static func card(for profile: ProfileCreationState, today: CalendarDate = .today()) -> String? {
        sealed(profile, today: today)?.base64EncodedString()
    }

    /// A partner's card from the server. It never expires: the match was
    /// made when it was shared.
    static func profile(fromCard card: String, today: CalendarDate = .today()) -> ProfileCreationState? {
        Data(base64Encoded: card).flatMap { opened($0, today: today, expires: false)?.profile }
    }

    // MARK: - Links

    static func url(for profile: ProfileCreationState, holder: ProfileHolder = .current,
                    today: CalendarDate = .today(), now: Date = Date()) -> URL? {
        guard let data = sealed(profile, holder: holder, today: today, now: now) else { return nil }
        let text = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "https://\(webHost)\(webPath)#\(text)")
    }

    /// The sealed profile in a link, in either of its two forms, or nil when
    /// the link isn't meant to be a profile code at all.
    private static func payload(in url: URL) -> String? {
        switch url.scheme?.lowercased() {
        case "https" where url.host()?.lowercased() == webHost:
            let path = url.path()
            guard path == webPath || path == webPath + "/" else { return nil }
            return url.fragment() ?? ""
        case scheme where url.host()?.lowercased() == host:
            return url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        default:
            return nil
        }
    }

    /// Whether a link is meant to be a profile code, readable or not.
    static func isCode(_ url: URL) -> Bool { payload(in: url) != nil }

    /// The profile in a scanned link, or nil when it isn't a code this build
    /// can read, it has expired, or the profile in it can't be trusted.
    static func received(from url: URL, today: CalendarDate = .today(), now: Date = Date()) -> Received? {
        guard var text = payload(in: url)?
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/"),
              !text.isEmpty, text.count <= 4096 else { return nil }
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text) else { return nil }
        return opened(data, today: today, now: now, expires: true)
    }

    /// Text read from a QR code by the in-app scanner.
    static func received(fromScanned text: String, today: CalendarDate = .today(), now: Date = Date()) -> Received? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { received(from: $0, today: today, now: now) }
    }

    // MARK: - Tables

    private static let genders: [GenderIdentity] = [.woman, .man, .nonBinary, .selfDescribed]
    private static let religions: [Religion] = [
        .none, .spiritual, .christian, .muslim, .jewish, .hindu, .buddhist, .other, .preferNotToShare
    ]
    private static let arrangements = ["partnerOnly", "togetherWithOthers", "separatelyFromPartner", "noSex"]
    private static let futureChildren: [FutureChildrenWish] = [.yes, .no, .notSure]
    private static let substances: [Substance] = [.alcohol, .smoking, .drugs]
    private static let maximumNameBytes = 127
    private static let maximumPlaceBytes = 63
    private static let maximumLanguages = 20

    // MARK: - Packing

    /// The bits inside the seal. Never leaves the phone unsealed.
    static func encoded(_ profile: ProfileCreationState, today: CalendarDate = .today()) -> Data? {
        let profile = profile.sharedCopy(today: today)
        guard let age = profile.age(on: today), (0..<128).contains(age) else { return nil }
        var bits = BitWriter()
        bits.write(packingVersion, bits: 8)
        bits.write(age, bits: 7)
        bits.write(text: profile.displayName, lengthBits: 7, maximumBytes: maximumNameBytes)

        bits.write(profile.partnerAgeRange != nil)
        if let range = profile.partnerAgeRange {
            bits.write(range.minimum, bits: 7)
            bits.write(range.maximum, bits: 7)
            bits.write(range.isCustomized)
        }
        bits.write(profile.heightCentimeters, bits: 8)
        bits.write(profile.hasAdjustedHeight)
        bits.write(profile.partnerHeightRange.minimum, bits: 8)
        bits.write(profile.partnerHeightRange.maximum, bits: 8)

        bits.write(profile.gender.flatMap { genders.firstIndex(of: $0) }.map { $0 + 1 } ?? 0, bits: 3)
        bits.write(mask(genders) { profile.partnerGenders.contains($0) }, bits: 4)
        let arrangement = profile.relationshipPreferences.selectedOptionIDs(for: .sexualArrangement)
        bits.write(mask(arrangements) { arrangement.contains($0) }, bits: 4)
        bits.write(profile.religion.own.flatMap { religions.firstIndex(of: $0) }.map { $0 + 1 } ?? 0, bits: 4)
        bits.write(mask(religions) { profile.religion.acceptedPartnerReligions.contains($0) }, bits: 9)

        bits.write(optional: profile.lifestyle.hasChildren)
        bits.write(optional: profile.lifestyle.openToPartnerWithChildren)
        bits.write(profile.lifestyle.futureChildren.flatMap { futureChildren.firstIndex(of: $0) }.map { $0 + 1 } ?? 0, bits: 2)
        for substance in substances {
            let answer = profile.lifestyle[substance]
            bits.write(answer.ownLevel.map { $0 + 1 } ?? 0, bits: 3)
            bits.write(answer.partnerMaximumLevel.map { $0 + 1 } ?? 0, bits: 3)
        }

        bits.write(profile.searchRadiusKilometers, bits: 8)
        let location = profile.location.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
        bits.write(location != nil)
        if let location {
            // Hundredths of a degree: the same kilometre the shared copy keeps.
            bits.write(Int(((location.latitude + 90) * 100).rounded()), bits: 15)
            bits.write(Int(((location.longitude + 180) * 100).rounded()), bits: 16)
            bits.write(text: location.placeName ?? "", lengthBits: 6, maximumBytes: maximumPlaceBytes)
        }

        let languages = profile.languages.compactMap { LanguageCode($0) }.prefix(maximumLanguages)
        bits.write(languages.count, bits: 5)
        for language in languages { language.write(to: &bits) }

        // Seven bits per answered question, found by its step's storage ID.
        let answers = Dictionary(uniqueKeysWithValues: CompatibilityScaleQuestion.all.compactMap { question in
            (0..<255).contains(question.step.rawValue)
                ? ScaleAnswer(profile.lifestyle[question]).map { (question.step.rawValue, $0) } : nil
        })
        let count = (answers.keys.max() ?? -1) + 1
        bits.write(count, bits: 8)
        for id in 0..<count { bits.write(answers[id] != nil) }
        for id in 0..<count { if let answer = answers[id] { answer.write(to: &bits) } }
        return bits.data
    }

    /// `completedAt` isn't packed: a code is only made from a finished
    /// profile, so the time it was sealed stands in for it.
    static func decoded(_ data: Data, today: CalendarDate = .today(),
                        completedAt: Date = Date(timeIntervalSince1970: 0)) -> ProfileCreationState? {
        var bits = BitReader(data)
        guard bits.read(8) == packingVersion, let age = bits.read(7),
              let name = bits.readText(lengthBits: 7) else { return nil }
        var profile = ProfileCreationState(today: today, applicationLanguage: "")
        let birthday = CalendarDate(year: today.year - age, month: 1, day: 1)
        profile.dateOfBirth = birthday
        profile.birthDateBaseline = birthday
        profile.birthDateSelection = birthday
        profile.completedAt = completedAt
        profile.displayName = name

        guard let hasAgeRange = bits.readFlag() else { return nil }
        if hasAgeRange {
            guard let minimum = bits.read(7), let maximum = bits.read(7), let customized = bits.readFlag() else { return nil }
            let range = PartnerAgeRules.clamped(minimum: minimum, maximum: maximum)
            profile.partnerAgeRange = PartnerAgeRange(minimum: range.minimum, maximum: range.maximum, isCustomized: customized)
        }
        guard let height = bits.read(8), let adjusted = bits.readFlag(),
              let shortest = bits.read(8), let tallest = bits.read(8) else { return nil }
        profile.heightCentimeters = HeightRules.clamped(height)
        profile.hasAdjustedHeight = adjusted
        let lower = HeightRules.clamped(shortest)
        profile.partnerHeightRange = PartnerHeightRange(minimum: lower, maximum: max(lower, HeightRules.clamped(tallest)))

        guard let gender = bits.read(3), let partnerGenders = bits.read(4), let arrangement = bits.read(4),
              let religion = bits.read(4), let partnerReligions = bits.read(9) else { return nil }
        profile.gender = gender > 0 && gender <= genders.count ? genders[gender - 1] : nil
        profile.partnerGenders = Set(selected(genders, in: partnerGenders))
        for option in selected(arrangements, in: arrangement) {
            profile.relationshipPreferences.select(option, in: .sexualArrangement)
        }
        profile.religion = ReligionAnswers(
            own: religion > 0 && religion <= religions.count ? religions[religion - 1] : nil,
            acceptedPartnerReligions: Set(selected(religions, in: partnerReligions))
        )

        guard let hasChildren = bits.readOptionalFlag(), let openToChildren = bits.readOptionalFlag(),
              let wish = bits.read(2) else { return nil }
        var lifestyle = LifestyleAnswers()
        lifestyle.hasChildren = hasChildren
        lifestyle.openToPartnerWithChildren = openToChildren
        lifestyle.futureChildren = wish > 0 && wish <= futureChildren.count ? futureChildren[wish - 1] : nil
        for substance in substances {
            guard let own = bits.read(3), let partner = bits.read(3) else { return nil }
            lifestyle[substance] = SubstanceAnswer(ownLevel: own > 0 ? own - 1 : nil,
                                                   partnerMaximumLevel: partner > 0 ? partner - 1 : nil)
        }

        guard let radius = bits.read(8), let hasLocation = bits.readFlag() else { return nil }
        profile.searchRadiusKilometers = SearchRadiusRules.clamped(radius)
        if hasLocation {
            guard let latitude = bits.read(15), let longitude = bits.read(16),
                  let place = bits.readText(lengthBits: 6) else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: Double(latitude) / 100 - 90,
                                                    longitude: Double(longitude) / 100 - 180)
            if CLLocationCoordinate2DIsValid(coordinate) {
                profile.location = SelectedLocation(coordinate: coordinate, source: .map,
                                                    placeName: place.isEmpty ? nil : place)
            }
        }

        guard let languageCount = bits.read(5) else { return nil }
        var languages: [String] = []
        for _ in 0..<languageCount {
            guard let language = LanguageCode(from: &bits) else { return nil }
            languages.append(language.text)
        }
        profile.languages = languages

        guard let count = bits.read(8) else { return nil }
        var answered: [Int] = []
        for id in 0..<count {
            guard let isAnswered = bits.readFlag() else { return nil }
            if isAnswered { answered.append(id) }
        }
        for id in answered {
            guard let read = ScaleAnswer.read(from: &bits) else { return nil }
            // A question this build doesn't know is skipped, not refused.
            guard let answer = read, let step = ProfileCreationStep(rawValue: id),
                  let question = CompatibilityScaleQuestion.question(for: step) else { continue }
            lifestyle[question] = answer.answer
        }
        profile.lifestyle = lifestyle
        return profile.receivedCopy(today: today)
    }

    private static func mask<Value>(_ table: [Value], contains: (Value) -> Bool) -> Int {
        table.enumerated().reduce(0) { contains($1.element) ? $0 | (1 << $1.offset) : $0 }
    }

    private static func selected<Value>(_ table: [Value], in mask: Int) -> [Value] {
        table.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
    }

    /// A 1–5 answer in seven bits when all three parts are given: own,
    /// partner and importance as one number 0–124. Otherwise the escape value
    /// 127 and a byte with each part as 0–5, where 0 is unanswered. Whether
    /// the partner value was set by hand follows from the two values differing.
    private struct ScaleAnswer {
        static let escape = 127

        func write(to bits: inout BitWriter) {
            if let own = answer.own, let partner = answer.partner, let importance = answer.importance,
               [own, partner, importance].allSatisfy(CompatibilityScaleAnswer.range.contains) {
                bits.write((own - 1) * 25 + (partner - 1) * 5 + (importance - 1), bits: 7)
            } else {
                bits.write(Self.escape, bits: 7)
                bits.write(packed, bits: 8)
            }
        }

        /// Nil past the end; otherwise the answer, or nil for one that can't be read.
        static func read(from bits: inout BitReader) -> ScaleAnswer?? {
            guard let value = bits.read(7) else { return nil }
            if value < 125 {
                return .some(ScaleAnswer(answer: CompatibilityScaleAnswer(
                    own: value / 25 + 1, partner: value / 5 % 5 + 1, isPartnerCustomized: value / 25 != value / 5 % 5,
                    importance: value % 5 + 1)))
            }
            guard value == escape, let packed = bits.read(8) else { return value == escape ? nil : .some(nil) }
            return .some(ScaleAnswer(packed: packed))
        }

        private init(answer: CompatibilityScaleAnswer) { self.answer = answer }

        let answer: CompatibilityScaleAnswer

        init?(_ answer: CompatibilityScaleAnswer) {
            guard answer.own != nil || answer.partner != nil else { return nil }
            self.answer = answer
        }

        init?(packed: Int) {
            let own = packed / 36, partner = packed / 6 % 6, importance = packed % 6
            guard own <= 5 else { return nil }
            answer = CompatibilityScaleAnswer(own: own == 0 ? nil : own, partner: partner == 0 ? nil : partner,
                                              isPartnerCustomized: own != partner,
                                              importance: importance == 0 ? nil : importance)
        }

        var packed: Int {
            func digit(_ value: Int?) -> Int { value.map { min(max($0, 1), 5) } ?? 0 }
            return digit(answer.own) * 36 + digit(answer.partner) * 6 + digit(answer.importance)
        }
    }

    /// A two- or three-letter language code, five bits per letter.
    private struct LanguageCode {
        let text: String

        init?(_ text: String) {
            let text = text.lowercased()
            guard (2...3).contains(text.utf8.count), text.utf8.allSatisfy({ (97...122).contains($0) }) else { return nil }
            self.text = text
        }

        init?(from bits: inout BitReader) {
            guard let isLong = bits.readFlag() else { return nil }
            var letters: [UInt8] = []
            for _ in 0..<(isLong ? 3 : 2) {
                guard let letter = bits.read(5), letter < 26 else { return nil }
                letters.append(UInt8(97 + letter))
            }
            text = String(decoding: letters, as: UTF8.self)
        }

        func write(to bits: inout BitWriter) {
            bits.write(text.utf8.count == 3)
            for letter in text.utf8 { bits.write(Int(letter) - 97, bits: 5) }
        }
    }
}

/// Writes whole numbers of any width, most significant bit first.
struct BitWriter {
    private var bytes: [UInt8] = []
    private var used = 0

    var data: Data { Data(bytes) }

    /// Values outside the width are clamped, never wrapped.
    mutating func write(_ value: Int, bits: Int) {
        write(raw: UInt32(clamping: min(max(value, 0), (1 << bits) - 1)), bits: bits)
    }

    mutating func write(raw value: UInt32, bits: Int) {
        for bit in (0..<bits).reversed() {
            if used % 8 == 0 { bytes.append(0) }
            if value >> UInt32(bit) & 1 == 1 { bytes[bytes.count - 1] |= 0x80 >> UInt8(used % 8) }
            used += 1
        }
    }

    mutating func write(_ flag: Bool) { write(flag ? 1 : 0, bits: 1) }

    /// Unanswered, no or yes.
    mutating func write(optional flag: Bool?) { write(flag.map { $0 ? 2 : 1 } ?? 0, bits: 2) }

    /// As many whole characters as fit in `maximumBytes`.
    mutating func write(text: String, lengthBits: Int, maximumBytes: Int) {
        var utf8: [UInt8] = []
        for character in text {
            let next = Array(String(character).utf8)
            guard utf8.count + next.count <= maximumBytes else { break }
            utf8 += next
        }
        write(utf8.count, bits: lengthBits)
        for byte in utf8 { write(Int(byte), bits: 8) }
    }
}

/// Reads what `BitWriter` wrote. Every read is nil past the end.
struct BitReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ data: Data) { bytes = Array(data) }

    mutating func read(_ bits: Int) -> Int? {
        guard position + bits <= bytes.count * 8 else { return nil }
        var value = 0
        for _ in 0..<bits {
            value = value << 1 | Int(bytes[position / 8] >> UInt8(7 - position % 8) & 1)
            position += 1
        }
        return value
    }

    mutating func readFlag() -> Bool? { read(1).map { $0 == 1 } }

    /// Nil past the end; otherwise the answer, which may itself be missing.
    mutating func readOptionalFlag() -> Bool?? {
        guard let value = read(2) else { return nil }
        return .some(value == 0 ? nil : value == 2)
    }

    mutating func readText(lengthBits: Int) -> String? {
        guard let count = read(lengthBits) else { return nil }
        var utf8: [UInt8] = []
        for _ in 0..<count {
            guard let byte = read(8) else { return nil }
            utf8.append(UInt8(byte))
        }
        if #available(iOS 18, *) {
            return String(validating: utf8, as: UTF8.self)
        }
        return String(bytes: utf8, encoding: .utf8)
    }
}
