import Foundation

/// Every line the app says in a notification. English only, by design: the
/// voice is part of the product. Sassy for nudges, plain for anything that
/// asks the user to act on their privacy or account.
///
/// Rules the copy keeps:
/// * Names appear only in message notifications with previews on.
/// * Nothing claims someone "likes" the user: a match means mutual
///   compatibility, nothing more.
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

    static func templates(for slot: Slot) -> [Template] { catalog[slot.key] ?? [] }

    /// The A/B bucket picks the first variant an install sees; each later
    /// send moves one along, so nobody gets the same line twice in a row.
    static func variant(for slot: Slot, installID: String, sendIndex: Int,
                        values: [String: String] = [:]) -> (template: Template, title: String, body: String)? {
        let usable = templates(for: slot).compactMap { template in
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

    /// Keyed by `Slot.key`. The server-sent slots (match_new, first_match,
    /// message_new.*, match_ended) are mirrored in
    /// `supabase/functions/push-dispatch/copy.json`; a test keeps them equal.
    static let catalog: [String: [Template]] = [
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
}
