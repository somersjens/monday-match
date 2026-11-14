import Foundation

/// The ordered catalog drives onboarding, profile editing and answer storage.
struct CompatibilityScaleQuestion: Hashable, Identifiable {
    let step: ProfileCreationStep
    let title: String
    let subtitle: String
    let lowLabel: String
    let highLabel: String
    let symbol: String

    var id: String { String(describing: step) }

    struct Section {
        let title: String
        let questions: [CompatibilityScaleQuestion]
    }

    /// Localized once per language, never rebuilt during a selection or slider update.
    private struct Catalog {
        let sections: [Section]
        let questions: [CompatibilityScaleQuestion]
        let byStep: [ProfileCreationStep: CompatibilityScaleQuestion]

        init(language: AppLanguage) {
            sections = CompatibilityScaleQuestion.makeSections(language: language)
            questions = sections.flatMap(\.questions)
            byStep = Dictionary(uniqueKeysWithValues: questions.map { ($0.step, $0) })
        }
    }

    private static let english = Catalog(language: .english)
    private static let dutch = Catalog(language: .dutch)

    private static var catalog: Catalog {
        // Read the observable setting even on a cache hit so visible text
        // still refreshes immediately when the app language changes.
        AppLanguageSettings.shared.language == .english ? english : dutch
    }

    static var aloneTime: Self { catalog.byStep[.aloneTime]! }
    static var all: [Self] { catalog.questions }
    static var sections: [Section] { catalog.sections }
    /// Navigation order is independent of the current display language.
    static let orderedSteps: [ProfileCreationStep] = english.questions.map(\.step)

    static func question(for step: ProfileCreationStep) -> Self? {
        catalog.byStep[step]
    }

    private static func makeSections(language: AppLanguage) -> [Section] {
        func text(_ message: AppLocalizedMessage) -> String {
            AppLocalization.string(message, language: language)
        }
        return [
        Section(title: text("Closeness and space"), questions: [
            Self(
                step: .aloneTime,
                title: text("Time for yourself"),
                subtitle: text("How much time do you need for yourself, apart from your partner?"),
                lowLabel: text("Little time alone"),
                highLabel: text("Lots of time alone"),
                symbol: "heart"
            ),
            Self(
                step: .sharedHobbies,
                title: text("Shared hobbies"),
                subtitle: text("Do you enjoy having your own hobbies, or would you like to share many hobbies with a partner?"),
                lowLabel: text("Own hobbies"),
                highLabel: text("Many shared hobbies"),
                symbol: "heart"
            ),
            Self(
                step: .partnerSocializing,
                title: text("Including your partner"),
                subtitle: text("Are you happy keeping social lives separate, or do you like joining each other often?"),
                lowLabel: text("Separate"),
                highLabel: text("Often together"),
                symbol: "heart"
            ),
            Self(
                step: .romanticGestures,
                title: text("Romance"),
                subtitle: text("In love, are you more down-to-earth, or do you enjoy romantic gestures and surprises?"),
                lowLabel: text("Down-to-earth"),
                highLabel: text("Romantic"),
                symbol: "heart"
            ),
            Self(
                step: .physicalAffection,
                title: text("Physical affection"),
                subtitle: text("How much touch, cuddling and physical closeness do you need in a relationship?"),
                lowLabel: text("Occasional touch"),
                highLabel: text("Lots of closeness"),
                symbol: "heart"
            ),
            Self(
                step: .publicAffection,
                title: text("Affection in public"),
                subtitle: text("Do you prefer keeping affection for at home, or do you like showing it in public too?"),
                lowLabel: text("Only at home"),
                highLabel: text("In public too"),
                symbol: "heart"
            ),
            Self(
                step: .sexualIntimacy,
                title: text("Sex and intimacy"),
                subtitle: text("How big a role does sex play in a relationship for you?"),
                lowLabel: text("Small role"),
                highLabel: text("Big role"),
                symbol: "heart"
            ),
        ]),
        Section(title: text("Contact and conversation"), questions: [
            Self(
                step: .texting,
                title: text("Texting"),
                subtitle: text("Do you message your partner only when there is something to share, or regularly throughout the day?"),
                lowLabel: text("When there is news"),
                highLabel: text("Throughout the day"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .calling,
                title: text("Calling"),
                subtitle: text("Do you prefer messaging, or calling and video calling with a partner?"),
                lowLabel: text("Messaging"),
                highLabel: text("Calling"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .talkativeness,
                title: text("Quiet or talkative"),
                subtitle: text("Are you naturally on the quiet side, or do you love talking a lot about everything?"),
                lowLabel: text("Quiet"),
                highLabel: text("Talkative"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .conversationDepth,
                title: text("Depth of conversation"),
                subtitle: text("Do you like keeping conversations light, or do you love going deep?"),
                lowLabel: text("Keep it light"),
                highLabel: text("Go deep"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .currentAffairs,
                title: text("News and current affairs"),
                subtitle: text("Do you hardly follow the news and current affairs, or keep up with them every day?"),
                lowLabel: text("Hardly any news"),
                highLabel: text("News every day"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .communicationStyle,
                title: text("Communication style"),
                subtitle: text("Do you put things carefully and tactfully, or say directly what you think?"),
                lowLabel: text("Tactful"),
                highLabel: text("Direct"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .expressingAppreciation,
                title: text("Showing appreciation"),
                subtitle: text("Do you mainly show appreciation through actions, or often put it into words?"),
                lowLabel: text("Through actions"),
                highLabel: text("In words"),
                symbol: "bubble.left.and.bubble.right"
            ),
        ]),
        Section(title: text("Feelings and conflict"), questions: [
            Self(
                step: .discussingFeelings,
                title: text("Discussing feelings"),
                subtitle: text("Do you share feelings gradually and in small steps, or openly and in depth?"),
                lowLabel: text("Gradually"),
                highLabel: text("Openly and in depth"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .stressContact,
                title: text("Contact during stress"),
                subtitle: text("When stressed, do you first need space, or seek contact and support from your partner?"),
                lowLabel: text("Space first"),
                highLabel: text("Seek contact"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .listeningAndSolutions,
                title: text("Listening and solutions"),
                subtitle: text("When someone shares a problem, do you mostly offer solutions, or mostly a listening ear?"),
                lowLabel: text("Solutions"),
                highLabel: text("Listening ear"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .debating,
                title: text("Debate or harmony"),
                subtitle: text("When opinions differ, do you keep the peace, or do you enjoy a lively debate?"),
                lowLabel: text("Keep the peace"),
                highLabel: text("Lively debate"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .disagreements,
                title: text("Discussing disagreements"),
                subtitle: text("After a disagreement, do you need time first, or prefer to talk it through as soon as possible?"),
                lowLabel: text("Take time first"),
                highLabel: text("Talk soon"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .relationshipConversations,
                title: text("Relationship conversations"),
                subtitle: text("Do you discuss your relationship when something comes up, or regularly make time to reflect on it?"),
                lowLabel: text("When needed"),
                highLabel: text("Regularly"),
                symbol: "bolt.heart"
            ),
        ]),
        Section(title: text("Daily rhythm and free time"), questions: [
            Self(
                step: .dailyRhythm,
                title: text("Daily rhythm"),
                subtitle: text("Do you feel most at home in the evening, or are you at your best early in the morning?"),
                lowLabel: text("Night owl"),
                highLabel: text("Early bird"),
                symbol: "sun.max"
            ),
            Self(
                step: .leisureTime,
                title: text("Free time"),
                subtitle: text("Do you prefer relaxing at home or somewhere quiet, or going out and being active?"),
                lowLabel: text("At home and quiet"),
                highLabel: text("Out and active"),
                symbol: "sun.max"
            ),
            Self(
                step: .cityOrNature,
                title: text("City or nature"),
                subtitle: text("In your free time, do you head into the city, or out into nature?"),
                lowLabel: text("Into the city"),
                highLabel: text("Into nature"),
                symbol: "sun.max"
            ),
            Self(
                step: .nightlife,
                title: text("Parties and nightlife"),
                subtitle: text("Would you rather skip parties and festivals, or do you love going out often?"),
                lowLabel: text("Rarely out"),
                highLabel: text("Often out"),
                symbol: "sun.max"
            ),
            Self(
                step: .screenTime,
                title: text("Screen time"),
                subtitle: text("Do you spend little of your free time on series, games and your phone, or a lot?"),
                lowLabel: text("Little screen time"),
                highLabel: text("Lots of screen time"),
                symbol: "sun.max"
            ),
            Self(
                step: .exercise,
                title: text("Exercise"),
                subtitle: text("How big a role do exercise, sports and physical activity play in your life?"),
                lowLabel: text("Small role"),
                highLabel: text("Big role"),
                symbol: "sun.max"
            ),
            Self(
                step: .travel,
                title: text("Travel"),
                subtitle: text("Do you prefer staying close to home, or do you love to travel often?"),
                lowLabel: text("Travel little"),
                highLabel: text("Travel often"),
                symbol: "sun.max"
            ),
            Self(
                step: .travelStyle,
                title: text("Travel style"),
                subtitle: text("Do you travel simply, such as camping or backpacking, or do you choose comfort and luxury?"),
                lowLabel: text("Simple"),
                highLabel: text("Comfort and luxury"),
                symbol: "sun.max"
            ),
        ]),
        Section(title: text("Social life and privacy"), questions: [
            Self(
                step: .socialPlans,
                title: text("Social plans"),
                subtitle: text("Do you prefer few social commitments, or enjoy a full social calendar?"),
                lowLabel: text("Few plans"),
                highLabel: text("Full calendar"),
                symbol: "person.2"
            ),
            Self(
                step: .familyRole,
                title: text("Family"),
                subtitle: text("Do you see your family now and then, or are you closely involved in each other’s daily lives?"),
                lowLabel: text("Now and then"),
                highLabel: text("Closely involved"),
                symbol: "person.2"
            ),
            Self(
                step: .celebrations,
                title: text("Celebrations"),
                subtitle: text("Do you keep birthdays and special occasions small, or do you go all out?"),
                lowLabel: text("Keep it small"),
                highLabel: text("Go all out"),
                symbol: "person.2"
            ),
            Self(
                step: .exPartnerContact,
                title: text("Contact with ex-partners"),
                subtitle: text("Are you comfortable with friendly contact with ex-partners, or prefer as little contact as possible?"),
                lowLabel: text("Friendly contact"),
                highLabel: text("Minimal contact"),
                symbol: "person.2"
            ),
            Self(
                step: .relationshipPrivacy,
                title: text("Privacy in a relationship"),
                subtitle: text("Do you like keeping things such as your phone and calendar to yourself, or can your partner see and know everything?"),
                lowLabel: text("Own privacy"),
                highLabel: text("Share everything"),
                symbol: "person.2"
            ),
            Self(
                step: .socialMediaSharing,
                title: text("Sharing your relationship online"),
                subtitle: text("Do you prefer keeping your relationship private, or sharing it visibly on social media?"),
                lowLabel: text("Keep private"),
                highLabel: text("Share openly"),
                symbol: "person.2"
            ),
        ]),
        Section(title: text("Character and choices"), questions: [
            Self(
                step: .punctuality,
                title: text("Keeping time"),
                subtitle: text("Do you usually arrive around the agreed time, or are you always right on time?"),
                lowLabel: text("Roughly on time"),
                highLabel: text("Always punctual"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .weeklyPlanning,
                title: text("Weekly planning"),
                subtitle: text("Do you like leaving your week open to spontaneous plans, or planning it in advance?"),
                lowLabel: text("Spontaneous"),
                highLabel: text("Planned ahead"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .decisionMaking,
                title: text("Making decisions"),
                subtitle: text("Do you decide quickly and intuitively, or take time to think things through?"),
                lowLabel: text("Quick and intuitive"),
                highLabel: text("Carefully considered"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .newExperiences,
                title: text("New experiences"),
                subtitle: text("Do you enjoy familiar, comfortable experiences, or actively seek novelty and adventure?"),
                lowLabel: text("Familiar"),
                highLabel: text("Adventurous"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .takingInitiative,
                title: text("Taking the lead"),
                subtitle: text("Do you happily leave plans and choices to the other person, or prefer to take the lead yourself?"),
                lowLabel: text("Follow"),
                highLabel: text("Take the lead"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .workAmbition,
                title: text("Work and ambition"),
                subtitle: text("Does work mainly support your life, or are career and growth major goals?"),
                lowLabel: text("Work supports life"),
                highLabel: text("Career and growth"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .personalStyle,
                title: text("Clothing and style"),
                subtitle: text("Do you dress mainly for comfort, or do you put a lot of care into style and appearance?"),
                lowLabel: text("Comfortable"),
                highLabel: text("Style-conscious"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .spirituality,
                title: text("Spirituality"),
                subtitle: text("Do you look at life mainly in a rational, down-to-earth way, or are you spiritually minded?"),
                lowLabel: text("Rational"),
                highLabel: text("Spiritual"),
                symbol: "slider.horizontal.3"
            ),
        ]),
        Section(title: text("Life together and future"), questions: [
            Self(
                step: .futurePlanning,
                title: text("Planning the future"),
                subtitle: text("Do you prefer taking a relationship one phase at a time, or making plans far ahead?"),
                lowLabel: text("One phase at a time"),
                highLabel: text("Far ahead"),
                symbol: "house"
            ),
            Self(
                step: .hostingGuests,
                title: text("Guests at home"),
                subtitle: text("Is your home mainly a quiet place for yourself, or is the door always open to guests?"),
                lowLabel: text("Rarely guests"),
                highLabel: text("Often guests"),
                symbol: "house"
            ),
            Self(
                step: .pets,
                title: text("Pets"),
                subtitle: text("Do you prefer living without pets, or are animals truly part of your life?"),
                lowLabel: text("No pets"),
                highLabel: text("Part of the family"),
                symbol: "house"
            ),
            Self(
                step: .homeTidiness,
                title: text("Home and tidiness"),
                subtitle: text("Are you comfortable with a lived-in home, or is a tidy home important to you?"),
                lowLabel: text("Lived-in home"),
                highLabel: text("Tidy home"),
                symbol: "house"
            ),
            Self(
                step: .sharedResponsibilities,
                title: text("Dividing tasks"),
                subtitle: text("Do you like clearly dividing chores and admin, or doing most of it together?"),
                lowLabel: text("Clearly divided"),
                highLabel: text("Do it together"),
                symbol: "house"
            ),
            Self(
                step: .foodChoices,
                title: text("Food"),
                subtitle: text("Do taste and convenience guide your food choices, or do you mainly choose consciously and healthily?"),
                lowLabel: text("Taste and ease"),
                highLabel: text("Mindful and healthy"),
                symbol: "house"
            ),
            Self(
                step: .diningOut,
                title: text("Cooking and eating out"),
                subtitle: text("Do you mostly cook and eat at home, or do you often eat out?"),
                lowLabel: text("Cook at home"),
                highLabel: text("Eat out"),
                symbol: "house"
            ),
            Self(
                step: .spendingMoney,
                title: text("Spending money"),
                subtitle: text("Do you enjoy spending spontaneously, or prefer planning expenses and saving?"),
                lowLabel: text("Enjoy spontaneously"),
                highLabel: text("Plan and save"),
                symbol: "house"
            ),
        ]),
        ]
    }
}

extension ProfileCreationStep {
    var compatibilityQuestion: CompatibilityScaleQuestion? {
        CompatibilityScaleQuestion.question(for: self)
    }
}
