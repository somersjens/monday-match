import Foundation

/// Every line the app says in a notification, in English and Dutch. The
/// Dutch is written, not translated: the voice is part of the product, so
/// each language gets its own jokes. Sassy for nudges, plain for anything
/// that asks the user to act on their privacy or account.
///
/// Rules the copy keeps:
/// * Names appear only in message notifications with previews on.
/// * Nothing claims someone liked, chose or wants the user: a match means
///   both meet each other's requirements and minimum scores, nothing more.
/// * No scores, reasons, coworkers or who-ended-what on the lock screen.
enum NotificationCopy {
    struct Template: Equatable, Codable {
        /// Stable across releases: analytics and A/B results refer to it.
        let id: String
        let title: String
        let body: String

        /// The placeholders this template needs, such as `match_name`.
        var placeholders: Set<String> {
            var found = Set<String>()
            for text in [title, body] {
                var rest = Substring(text)
                while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
                    found.insert(String(rest[rest.index(after: open)..<close]))
                    rest = rest[rest.index(after: close)...]
                }
            }
            return found
        }

        /// Fills the placeholders; nil when one of them has no value, so a
        /// half-filled `{match_name}` never reaches a lock screen.
        func rendered(_ values: [String: String]) -> (title: String, body: String)? {
            guard placeholders.isSubset(of: values.filter { !$0.value.isEmpty }.keys) else { return nil }
            func fill(_ text: String) -> String {
                values.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
            }
            return (fill(title), fill(body))
        }
    }

    /// A kind, optionally narrowed to one situation (previews on or off,
    /// which consent is outdated).
    struct Slot: Hashable {
        let kind: NotificationKind
        let flavor: String?
        init(_ kind: NotificationKind, _ flavor: String? = nil) { self.kind = kind; self.flavor = flavor }
        var key: String { flavor.map { "\(kind.rawValue).\($0)" } ?? kind.rawValue }
    }

    static func catalog(for language: AppLanguage) -> [String: [Template]] {
        switch language {
        case .english: english
        case .dutch: dutch
        }
    }

    /// The English catalog, the reference for the others.
    static var catalog: [String: [Template]] { english }

    static func templates(for slot: Slot, language: AppLanguage = .english) -> [Template] {
        catalog(for: language)[slot.key] ?? english[slot.key] ?? []
    }

    /// The A/B bucket picks the first variant an install sees; each later
    /// send moves one along, so nobody gets the same line twice in a row.
    static func variant(for slot: Slot, installID: String, sendIndex: Int, values: [String: String] = [:],
                        language: AppLanguage = .english) -> (template: Template, title: String, body: String)? {
        let usable = templates(for: slot, language: language).compactMap { template in
            template.rendered(values).map { (template, $0.title, $0.body) }
        }
        guard !usable.isEmpty else { return nil }
        let bucket = Int(fnv1a("\(installID)|\(slot.key)") % UInt64(usable.count))
        return usable[(bucket + max(sendIndex, 0)) % usable.count]
    }

    /// A stable hash: Swift's own `hashValue` changes on every launch.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    private static func t(_ id: String, _ title: String, _ body: String) -> Template {
        Template(id: id, title: title, body: body)
    }

    /// Keyed by `Slot.key`; the same keys in every language. The server-sent
    /// slots (match_new, first_match, message_new.*, match_ended) are mirrored
    /// in `supabase/functions/push-dispatch/copy.json`; a test keeps them equal.
    static let english: [String: [Template]] = [
        // 1. New auto-match. A match means both people meet each other's requirements and
        // minimum scores. Nobody has seen, liked or picked anyone, so the copy never says so.
        "match_new": [
            t("match_new.a", "Well, well, well…", "Someone's a match. Go say hi before you overthink it."),
            t("match_new.b", "It's a match", "The algorithm did the hard part. The hello is on you."),
            t("match_new.c", "Plot twist: a match", "Your compatibility checks out with someone. Go see who."),
            t("match_new.d", "Zero swipes, one match", "All those questions paid off. Go see who it is."),
            t("match_new.e", "Compatible. Both ways.",
              "You tick their boxes, they tick yours. The rest is up to you two."),
            t("match_new.f", "The numbers are in", "Someone matches you on paper. Time to find out off paper."),
            t("match_new.g", "Match found. No swiping involved.", "Your answers did the talking. Now it's your turn."),
            t("match_new.h", "New match, who dis?", "Open the app to see where your answers led you."),
        ],
        "first_match": [
            t("first_match.a", "Your first match. Finally.", "Worth the wait. Go see who it is."),
            t("first_match.b", "First match unlocked", "Mark the date. Now go make it a story."),
            t("first_match.c", "Your first match is in", "All those questions finally paid off. Go take a look."),
            t("first_match.d", "Day one of something?", "Your very first match. No pressure. Okay, a little pressure."),
        ],
        // 2. New message. The server never sees message text, so even with
        // previews on a push names the sender only.
        "message_new.preview": [
            t("message_new.preview.a", "{match_name}", "{match_name} sent you a message."),
            t("message_new.preview.b", "{match_name}", "{match_name} has something to say."),
            t("message_new.preview.c", "{match_name}", "New message from {match_name}. Your move."),
            t("message_new.preview.d", "{match_name}", "{match_name} just wrote. Don't play it too cool."),
        ],
        "message_new.preview_batch": [
            t("message_new.preview_batch.a", "{match_name}", "{match_name} sent {count} messages. Somebody's chatty."),
            t("message_new.preview_batch.b", "{match_name}", "{count} new messages from {match_name}."),
            t("message_new.preview_batch.c", "{match_name}",
              "{count} messages from {match_name}. The conversation is on."),
            t("message_new.preview_batch.d", "{match_name}", "{match_name} is on a roll: {count} new messages."),
        ],
        "message_new.private": [
            t("message_new.private.a", "New message", "Open the app to read it."),
            t("message_new.private.b", "New message", "Your match wrote. Open the app to read it."),
            t("message_new.private.c", "You've got a message", "It's waiting in the app, for your eyes only."),
        ],
        "message_new.private_batch": [
            t("message_new.private_batch.a", "New messages", "{count} new messages are waiting."),
            t("message_new.private_batch.b", "New messages",
              "{count} messages from your match. Open the app to read them."),
            t("message_new.private_batch.c", "Your chat is busy", "{count} new messages, for your eyes only."),
        ],
        // 3. Match ended: never who or why.
        "match_ended": [
            t("match_ended.a", "Well, that chapter was short.",
              "This match has ended. The conversation stays readable in My matches."),
            t("match_ended.b", "And… scene.", "This match is over. No drama, just a fresh start."),
            t("match_ended.c", "Onward.", "Your match has ended. Plenty of plot left."),
            t("match_ended.d", "That's a wrap",
              "This match has ended. Your chat is still there to reread in My matches."),
            t("match_ended.e", "Not every match is the one",
              "This one has ended. With auto-matching on, the search starts again."),
        ],
        // 4. Conversation going quiet
        "conversation_quiet": [
            t("conversation_quiet.a", "This conversation needs CPR", "One message could bring it back."),
            t("conversation_quiet.b", "Awkward silence detected", "Someone has to break it. Might as well be you."),
            t("conversation_quiet.c", "Don't let it fizzle", "Good conversations don't text themselves."),
            t("conversation_quiet.d", "Your chat is gathering dust", "A question is the easiest way back in."),
            t("conversation_quiet.e", "Radio silence",
              "It's been quiet for days. A good question beats a perfect opener."),
        ],
        // 5. Unanswered message
        "message_unanswered": [
            t("message_unanswered.a", "Playing hard to get?", "Or just forgetful? You have a message waiting."),
            t("message_unanswered.b", "Left on unread", "Rude, but fixable. Your match wrote to you."),
            t("message_unanswered.c", "Fashionably late", "Any later and it's just late. Your reply is waiting."),
            t("message_unanswered.d", "Your match wrote to you", "About a day ago. Just saying."),
            t("message_unanswered.e", "Ghosting is so last season", "There's an unread message with your name on it."),
        ],
        // 5b. Matched, nobody has said a word yet
        "match_no_conversation": [
            t("match_no_conversation.a", "Cupid has done his part", "Your move. A simple hi has worked for centuries."),
            t("match_no_conversation.b", "Someone has to go first", "Be the brave one. Say hi to your match."),
            t("match_no_conversation.c", "Silence isn't mysterious", "It's just silence. Say hi to your match."),
            t("match_no_conversation.d", "Still no hello?", "Neither of you has said a word yet. Fix that."),
            t("match_no_conversation.e", "Openers are overrated", "Hi works. Your match is one message away."),
        ],
        "message_not_sent": [
            t("message_not_sent.a", "Your message didn't make it",
              "Open the app to send it. It's waiting, encrypted and ready."),
            t("message_not_sent.b", "Stuck in the outbox", "A message hasn't been sent yet. Open the app to retry."),
        ],
        // 6. Privacy approval required: playful title, exact body.
        "privacy_required": [
            t("privacy_required.a", "Even Cupid needs your consent",
              "Accept the privacy terms to share your profile and use matching. Nothing is shared until you do."),
            t("privacy_required.b", "One signature away",
              "Profile sharing and matching need your privacy consent first. Read it, then decide."),
        ],
        // 7. Updated privacy terms: clarity over humour.
        "privacy_updated.profile": [
            t("privacy_updated.profile.a", "We've updated our privacy terms",
              "Please review them. Profile sharing and matching are paused until you accept."),
            t("privacy_updated.profile.b", "Plot twist: new privacy terms",
              "Review what changed. Sharing and matching resume once you accept."),
        ],
        "privacy_updated.matching": [
            t("privacy_updated.matching.a", "We've updated our privacy terms",
              "Please review them. Auto-matching is paused until you accept."),
            t("privacy_updated.matching.b", "Plot twist: new privacy terms",
              "Review what changed. Auto-matching resumes once you accept."),
        ],
        // 8. First compatibility check (phones together or the QR code)
        "first_matchmaking": [
            t("first_matchmaking.a", "That coworker isn't going to check themselves",
              "Hold your phones together and see if you're compatible. It takes seconds."),
            t("first_matchmaking.b", "Curious about someone?",
              "Phones together, results in seconds. No awkward questions required."),
            t("first_matchmaking.c", "All dressed up",
              "Your profile is ready and going nowhere. Check your compatibility with someone."),
            t("first_matchmaking.d", "Two phones, one answer",
              "Hold them together with someone, or let them scan your code. Then you'll know."),
        ],
        // 9. Consider lowering your standards
        "lower_standards": [
            t("lower_standards.a", "Your standards are giving \"unattainable\"",
              "A month without a match. Your matching preferences might be why."),
            t("lower_standards.b", "High standards. Low results.",
              "Coincidence? Take a look at your matching preferences."),
            t("lower_standards.c", "Picky is a strategy", "So far, a lonely one. Review your minimum match score."),
            t("lower_standards.d", "Nobody's that perfect",
              "Not even you. A slightly lower minimum match could change a lot."),
        ],
        // 10. No compatibility check for a month
        "compatibility_monthly": [
            t("compatibility_monthly.a", "Your love life called",
              "It's bored. Check your compatibility with someone new."),
            t("compatibility_monthly.b", "Another month, another missed opportunity",
              "Hold your phones together with someone. It takes seconds."),
            t("compatibility_monthly.c", "It's been a month",
              "Your profile misses being compared. Find someone and check."),
            t("compatibility_monthly.d", "Curiosity is free",
              "So is checking your compatibility. Phones together, answer in seconds."),
            t("compatibility_monthly.e", "Wondering about someone?",
              "Stop wondering. Let them scan your code and find out."),
        ],
        // 11. Auto-matching on, user away
        "auto_matching_idle": [
            t("auto_matching_idle.a", "Cupid is working overtime. You?",
              "Auto-matching is still on the job. Drop by sometime."),
            t("auto_matching_idle.b", "Still looking",
              "Auto-matching keeps searching while you're away. You'll hear from us when there's a match."),
            t("auto_matching_idle.c", "We're still on it",
              "Auto-matching never takes a day off. You're allowed to, but not forever."),
            t("auto_matching_idle.d", "Long time no see",
              "Auto-matching is still searching for you. Come say hi sometime."),
        ],
        // 12. Incomplete onboarding
        "onboarding_incomplete": [
            t("onboarding_incomplete.a", "You left us on read. Already?",
              "Your profile is {percent}% done. Pick up where you left off."),
            t("onboarding_incomplete.b", "Halfway there is nowhere", "A few more questions and you're in."),
            t("onboarding_incomplete.c", "Your profile is ghosting us", "Finish it and let the matching begin."),
            t("onboarding_incomplete.d", "So close", "Just a few more answers between you and matching."),
        ],
        "matching_setup_incomplete": [
            t("matching_setup_incomplete.a", "Auto-matching is on a break",
              "A couple of preferences are missing. Fill them in to resume."),
            t("matching_setup_incomplete.b", "Your preferences need a refresh",
              "Auto-matching is paused until you finish them. Two quick taps."),
        ],
        "welcome_back": [
            t("welcome_back.a", "Look who's back.", "Your profile is right where you left it."),
            t("welcome_back.b", "Oh, hi.", "It's been a while. Everything's where you left it."),
            t("welcome_back.c", "You're back.", "We'd say we missed you, but we're an app. Your profile's all set."),
        ],
    ]

    /// Written in Dutch, not translated: its own jokes, the app's own terms
    /// ("Automatisch matchen", "Mijn matches") and informal "je".
    static let dutch: [String: [Template]] = [
        "match_new": [
            t("match_new.nl.a", "Kijk eens aan…", "Je hebt een match. Zeg hoi voordat je het kapotdenkt."),
            t("match_new.nl.b", "Het is raak", "Het algoritme deed het zware werk. Die eerste 'hoi' is voor jou."),
            t("match_new.nl.c", "Breaking news: een match", "Jullie antwoorden passen bij elkaar. Kijk snel met wie."),
            t("match_new.nl.d", "Nul keer geswipet, één match",
              "Al die vragen hebben zich terugbetaald. Kijk wie het is."),
            t("match_new.nl.e", "Het klikt. Van twee kanten.",
              "Jij voldoet aan hun eisen, zij aan die van jou. De rest is aan jullie."),
            t("match_new.nl.f", "De cijfers zijn binnen",
              "Op papier zit het goed. Tijd om te kijken of dat in het echt ook zo is."),
            t("match_new.nl.g", "Match gevonden, zonder swipen", "Jouw antwoorden hebben het woord gedaan. Nu jij."),
            t("match_new.nl.h", "Raad eens", "Je hebt een nieuwe match. Open de app om te zien met wie."),
        ],
        "first_match": [
            t("first_match.nl.a", "Je eerste match. Eindelijk.", "Het wachten was het waard. Kijk wie het is."),
            t("first_match.nl.b", "Eerste match: check",
              "Zet de datum maar in je agenda. Nu nog een mooi verhaal ervan maken."),
            t("first_match.nl.c", "Daar is 'ie dan", "Je allereerste match. Al die vragen waren niet voor niets."),
            t("first_match.nl.d", "Dag één van iets moois?", "Je eerste match. Geen druk hoor. Oké, een béétje druk."),
        ],
        "message_new.preview": [
            t("message_new.preview.nl.a", "{match_name}", "{match_name} heeft je een bericht gestuurd."),
            t("message_new.preview.nl.b", "{match_name}", "{match_name} heeft je iets te vertellen."),
            t("message_new.preview.nl.c", "{match_name}", "Nieuw bericht van {match_name}. Jouw beurt."),
            t("message_new.preview.nl.d", "{match_name}", "{match_name} stuurde je net iets. Doe niet té cool."),
        ],
        "message_new.preview_batch": [
            t("message_new.preview_batch.nl.a", "{match_name}",
              "{match_name} stuurde {count} berichten. Lekker spraakzaam."),
            t("message_new.preview_batch.nl.b", "{match_name}", "{count} nieuwe berichten van {match_name}."),
            t("message_new.preview_batch.nl.c", "{match_name}",
              "{count} berichten van {match_name}. Het gesprek is los."),
            t("message_new.preview_batch.nl.d", "{match_name}",
              "{match_name} is goed op dreef: {count} nieuwe berichten."),
        ],
        "message_new.private": [
            t("message_new.private.nl.a", "Nieuw bericht", "Open de app om het te lezen."),
            t("message_new.private.nl.b", "Nieuw bericht", "Je match heeft geschreven. Lees het in de app."),
            t("message_new.private.nl.c", "Er is post", "Het ligt in de app voor je klaar. Alleen voor jouw ogen."),
        ],
        "message_new.private_batch": [
            t("message_new.private_batch.nl.a", "Nieuwe berichten",
              "Er liggen {count} nieuwe berichten voor je klaar."),
            t("message_new.private_batch.nl.b", "Nieuwe berichten",
              "{count} berichten van je match. Open de app om ze te lezen."),
            t("message_new.private_batch.nl.c", "Het is druk in je chat",
              "{count} nieuwe berichten, alleen voor jouw ogen."),
        ],
        "match_ended": [
            t("match_ended.nl.a", "Nou, dat was een kort hoofdstuk.",
              "Deze match is voorbij. Jullie gesprek blijft leesbaar in Mijn matches."),
            t("match_ended.nl.b", "Doek.", "Deze match is voorbij. Geen drama, gewoon een frisse start."),
            t("match_ended.nl.c", "Door naar het volgende.",
              "Je match is beëindigd. Er komen nog genoeg hoofdstukken."),
            t("match_ended.nl.d", "Dat was 'm",
              "Deze match is voorbij. Jullie chat kun je nog teruglezen in Mijn matches."),
            t("match_ended.nl.e", "Niet elke match is de ware",
              "Deze is voorbij. Staat automatisch matchen aan, dan zoeken we gewoon verder."),
        ],
        "conversation_quiet": [
            t("conversation_quiet.nl.a", "Dit gesprek moet gereanimeerd worden", "Eén berichtje en het leeft weer."),
            t("conversation_quiet.nl.b", "Ongemakkelijke stilte gedetecteerd",
              "Iemand moet 'm doorbreken. Waarom jij niet?"),
            t("conversation_quiet.nl.c", "Laat het niet doodbloeden", "Goede gesprekken typen zichzelf niet."),
            t("conversation_quiet.nl.d", "Je chat staat stof te vangen",
              "Een vraag stellen is de makkelijkste weg terug."),
            t("conversation_quiet.nl.e", "Radiostilte",
              "Het is al dagen stil. Een goede vraag wint het van de perfecte openingszin."),
        ],
        "message_unanswered": [
            t("message_unanswered.nl.a", "Moeilijk aan het doen?",
              "Of gewoon vergeten? Er staat een bericht voor je klaar."),
            t("message_unanswered.nl.b", "Nog ongelezen",
              "Onbeleefd, maar nog te redden. Je match heeft je geschreven."),
            t("message_unanswered.nl.c", "Lekker laat",
              "Nog even en het is gewoon onbeleefd. Je hebt een ongelezen bericht."),
            t("message_unanswered.nl.d", "Je match heeft je geschreven",
              "Alweer bijna een dag geleden. We zeggen het maar even."),
            t("message_unanswered.nl.e", "Ghosten is zó vorig seizoen",
              "Er ligt een ongelezen bericht met jouw naam erop."),
        ],
        "match_no_conversation": [
            t("match_no_conversation.nl.a", "Cupido heeft zijn werk gedaan",
              "Nu jij. Een simpel 'hoi' werkt al eeuwen."),
            t("match_no_conversation.nl.b", "Iemand moet de eerste zijn", "Wees dapper en zeg hoi tegen je match."),
            t("match_no_conversation.nl.c", "Stilte is niet mysterieus",
              "Het is gewoon stilte. Zeg hoi tegen je match."),
            t("match_no_conversation.nl.d", "Nog steeds geen hoi?",
              "Jullie hebben nog geen woord gewisseld. Tijd om daar iets aan te doen."),
            t("match_no_conversation.nl.e", "Openingszinnen zijn overrated",
              "'Hoi' werkt prima. Eén berichtje en jullie zitten in een gesprek."),
        ],
        "message_not_sent": [
            t("message_not_sent.nl.a", "Je bericht is niet aangekomen",
              "Open de app om het te versturen. Het staat versleuteld klaar."),
            t("message_not_sent.nl.b", "Nog niet verstuurd",
              "Een bericht hangt nog in de wachtrij. Open de app om het opnieuw te proberen."),
        ],
        "privacy_required": [
            t("privacy_required.nl.a", "Zelfs Cupido vraagt om toestemming",
              "Accepteer de privacyvoorwaarden om je profiel te delen en te matchen. Tot dan wordt er niets gedeeld."),
            t("privacy_required.nl.b", "Nog één handtekening",
              "Voor profiel delen en matchen is eerst je privacytoestemming nodig. Lees het rustig en beslis dan."),
        ],
        "privacy_updated.profile": [
            t("privacy_updated.profile.nl.a", "We hebben onze privacyvoorwaarden aangepast",
              "Bekijk ze even. Profiel delen en matchen staan op pauze tot je akkoord gaat."),
            t("privacy_updated.profile.nl.b", "Plotwending: nieuwe privacyvoorwaarden",
              "Bekijk wat er veranderd is. Delen en matchen gaan verder zodra je akkoord gaat."),
        ],
        "privacy_updated.matching": [
            t("privacy_updated.matching.nl.a", "We hebben onze privacyvoorwaarden aangepast",
              "Bekijk ze even. Automatisch matchen staat op pauze tot je akkoord gaat."),
            t("privacy_updated.matching.nl.b", "Plotwending: nieuwe privacyvoorwaarden",
              "Bekijk wat er veranderd is. Automatisch matchen gaat verder zodra je akkoord gaat."),
        ],
        "first_matchmaking": [
            t("first_matchmaking.nl.a", "Die collega checkt zichzelf echt niet",
              "Houd jullie telefoons tegen elkaar en zie of jullie bij elkaar passen. Duurt maar even."),
            t("first_matchmaking.nl.b", "Benieuwd naar iemand?",
              "Telefoons tegen elkaar en binnen een paar seconden weet je het. Zonder ongemakkelijke vragen."),
            t("first_matchmaking.nl.c", "Helemaal opgedoft",
              "Je profiel staat klaar, maar gaat nergens heen. Check je compatibiliteit met iemand."),
            t("first_matchmaking.nl.d", "Twee telefoons, één antwoord",
              "Houd ze tegen elkaar of laat iemand je code scannen. Dan weet je het."),
        ],
        "lower_standards": [
            t("lower_standards.nl.a", "Je eisen zijn nogal… onbereikbaar",
              "Een maand zonder match. Misschien ligt de lat net iets te hoog."),
            t("lower_standards.nl.b", "Hoge eisen, weinig resultaat", "Toeval? Kijk eens naar je matchvoorkeuren."),
            t("lower_standards.nl.c", "Kieskeurig is ook een strategie",
              "Tot nu toe wel een eenzame. Bekijk je minimale matchscore."),
            t("lower_standards.nl.d", "Niemand is zó perfect",
              "Jij ook niet. Een iets lagere minimale match kan veel uitmaken."),
        ],
        "compatibility_monthly": [
            t("compatibility_monthly.nl.a", "Je liefdesleven belde",
              "Het verveelt zich. Check je compatibiliteit met iemand nieuws."),
            t("compatibility_monthly.nl.b", "Weer een maand, weer een kans gemist",
              "Houd je telefoon tegen die van iemand anders. Duurt een paar seconden."),
            t("compatibility_monthly.nl.c", "Het is alweer een maand",
              "Je profiel mist het om vergeleken te worden. Zoek iemand en check het."),
            t("compatibility_monthly.nl.d", "Nieuwsgierig zijn kost niks",
              "Je compatibiliteit checken ook niet. Telefoons tegen elkaar en je weet het."),
            t("compatibility_monthly.nl.e", "Twijfel je over iemand?",
              "Stop met twijfelen. Laat diegene je code scannen en je weet het."),
        ],
        "auto_matching_idle": [
            t("auto_matching_idle.nl.a", "Cupido draait overuren. En jij?",
              "Automatisch matchen is nog steeds aan het werk. Kom eens langs."),
            t("auto_matching_idle.nl.b", "We zoeken nog",
              "Automatisch matchen zoekt door terwijl jij weg bent. Je hoort het als er een match is."),
            t("auto_matching_idle.nl.c", "Wij blijven zoeken",
              "Automatisch matchen neemt nooit vrij. Jij mag dat wel, maar niet voor altijd."),
            t("auto_matching_idle.nl.d", "Lang niet gezien",
              "Automatisch matchen zoekt nog steeds voor je. Kom eens hoi zeggen."),
        ],
        "onboarding_incomplete": [
            t("onboarding_incomplete.nl.a", "Je laat ons op gelezen staan. Nu al?",
              "Je profiel is voor {percent}% af. Ga verder waar je gebleven was."),
            t("onboarding_incomplete.nl.b", "Halverwege is nergens", "Nog een paar vragen en je bent binnen."),
            t("onboarding_incomplete.nl.c", "Je profiel ghost ons", "Maak het af en laat het matchen beginnen."),
            t("onboarding_incomplete.nl.d", "Zo dichtbij", "Nog maar een paar antwoorden tussen jou en matchen."),
        ],
        "matching_setup_incomplete": [
            t("matching_setup_incomplete.nl.a", "Automatisch matchen heeft pauze",
              "Er ontbreken een paar voorkeuren. Vul ze in om verder te gaan."),
            t("matching_setup_incomplete.nl.b", "Je voorkeuren zijn niet compleet",
              "Automatisch matchen staat op pauze tot ze compleet zijn. Twee tikken en klaar."),
        ],
        "welcome_back": [
            t("welcome_back.nl.a", "Kijk eens wie we daar hebben.", "Je profiel staat nog precies waar je het liet."),
            t("welcome_back.nl.b", "Hé, hoi.", "Dat is een tijdje geleden. Alles staat nog voor je klaar."),
            t("welcome_back.nl.c", "Je bent terug.",
              "We zouden zeggen dat we je gemist hebben, maar we zijn een app. Je profiel staat klaar."),
        ],
    ]
}
