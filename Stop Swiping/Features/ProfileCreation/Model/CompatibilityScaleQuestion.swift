import Foundation

/// The groups the 1–5 questions are shown and scored in. The raw values are
/// stored with every match, so they never change; new groups are added.
enum CompatibilityCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case dailyRhythm, homeLife, socialLife, contact, character, feelings, closeness

    var id: String { rawValue }

    /// The section title, in the current language.
    var title: String {
        CompatibilityScaleQuestion.sections.first { $0.category == self }?.title ?? rawValue
    }
}

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
        let category: CompatibilityCategory
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

    private static let catalogs: [AppLanguage: Catalog] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map { ($0, Catalog(language: $0)) }
    )

    private static var catalog: Catalog {
        // Read the observable setting even on a cache hit so visible text
        // still refreshes immediately when the app language changes.
        catalogs[AppLanguageSettings.shared.language]!
    }

    static var aloneTime: Self { catalog.byStep[.aloneTime]! }
    static var all: [Self] { catalog.questions }
    static var sections: [Section] { catalog.sections }
    /// Navigation order is independent of the current display language.
    static let orderedSteps: [ProfileCreationStep] = catalogs[.english]!.questions.map(\.step)

    static func question(for step: ProfileCreationStep) -> Self? {
        catalog.byStep[step]
    }

    /// The category a question belongs to, whatever the display language.
    static func category(for step: ProfileCreationStep) -> CompatibilityCategory? {
        categoryByStep[step]
    }

    private static let categoryByStep: [ProfileCreationStep: CompatibilityCategory] = Dictionary(
        uniqueKeysWithValues: catalogs[.english]!.sections.flatMap { section in
            section.questions.map { ($0.step, section.category) }
        }
    )

    private static func makeSections(language: AppLanguage) -> [Section] {
        func text(_ message: AppLocalizedMessage) -> String {
            AppLocalization.string(message, language: language)
        }
        return [
        Section(category: .dailyRhythm, title: text("Daily rhythm and free time"), questions: [
            Self(
                step: .dailyRhythm,
                title: text("Daily rhythm"),
                subtitle: text("Do you come alive in the evening, or are you at your best early in the morning?"),
                lowLabel: text("Night owl"),
                highLabel: text("Early bird"),
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
                step: .screenTime,
                title: text("Screen time"),
                subtitle: text("How much of your free time goes to series, games and your phone?"),
                lowLabel: text("Very little"),
                highLabel: text("A lot"),
                symbol: "sun.max"
            ),
            Self(
                step: .exercise,
                title: text("Exercise"),
                subtitle: text("How big a role do sports and exercise play in your life?"),
                lowLabel: text("Small role"),
                highLabel: text("Big role"),
                symbol: "sun.max"
            ),
            Self(
                step: .nightlife,
                title: text("Parties and nightlife"),
                subtitle: text("Do you happily skip parties and festivals, or do you love going out?"),
                lowLabel: text("Rarely out"),
                highLabel: text("Often out"),
                symbol: "sun.max"
            ),
            Self(
                step: .competitiveness,
                title: text("Winning"),
                subtitle: text("Do you play games just for fun, or do you really want to win?"),
                lowLabel: text("Just for fun"),
                highLabel: text("Play to win"),
                symbol: "sun.max"
            ),
            Self(
                step: .travelStyle,
                title: text("Travel style"),
                subtitle: text("On holiday, do you keep it simple with a tent or a backpack, or do you go for comfort and luxury?"),
                lowLabel: text("Tent and backpack"),
                highLabel: text("Comfort and luxury"),
                symbol: "sun.max"
            ),
        ]),
        Section(category: .homeLife, title: text("Home and household"), questions: [
            Self(
                step: .hostingGuests,
                title: text("Guests at home"),
                subtitle: text("Is your home mainly a quiet place for yourself, or is the door always open to guests?"),
                lowLabel: text("Rarely guests"),
                highLabel: text("Often guests"),
                symbol: "house"
            ),
            Self(
                step: .cooking,
                title: text("Cooking"),
                subtitle: text("Do you love being cooked for, or are you the chef in the kitchen?"),
                lowLabel: text("Being cooked for"),
                highLabel: text("Chef in the kitchen"),
                symbol: "house"
            ),
            Self(
                step: .pets,
                title: text("Pets"),
                subtitle: text("Would you rather live without pets, or do animals belong in your home?"),
                lowLabel: text("No pets"),
                highLabel: text("Part of the family"),
                symbol: "house"
            ),
            Self(
                step: .homeTidiness,
                title: text("Home and tidiness"),
                subtitle: text("Is a bit of mess at home fine with you, or do you like everything neat and tidy?"),
                lowLabel: text("A bit messy"),
                highLabel: text("Neat and tidy"),
                symbol: "house"
            ),
            Self(
                step: .foodChoices,
                title: text("Food"),
                subtitle: text("Do you eat whatever is tasty and easy, or do you pay attention to eating healthy?"),
                lowLabel: text("Tasty and easy"),
                highLabel: text("Healthy choices"),
                symbol: "house"
            ),
            Self(
                step: .spendingMoney,
                title: text("Spending money"),
                subtitle: text("Do you easily spend money on fun things, or do you prefer to plan and save?"),
                lowLabel: text("Spend and enjoy"),
                highLabel: text("Plan and save"),
                symbol: "house"
            ),
        ]),
        Section(category: .socialLife, title: text("Family and social life"), questions: [
            Self(
                step: .familyRole,
                title: text("Family"),
                subtitle: text("Do you see your family now and then, or are you very close and often in touch?"),
                lowLabel: text("Now and then"),
                highLabel: text("Very close"),
                symbol: "person.2"
            ),
            Self(
                step: .socialPlans,
                title: text("Social plans"),
                subtitle: text("Do you like having few social plans, or do you prefer a full calendar?"),
                lowLabel: text("Few plans"),
                highLabel: text("Full calendar"),
                symbol: "person.2"
            ),
            Self(
                step: .currentAffairs,
                title: text("News"),
                subtitle: text("Do you hardly follow the news, or do you keep up with it every day?"),
                lowLabel: text("Hardly at all"),
                highLabel: text("Every day"),
                symbol: "person.2"
            ),
            Self(
                step: .celebrations,
                title: text("Celebrations"),
                subtitle: text("Do you keep birthdays and special days small, or do you go all out?"),
                lowLabel: text("Keep it small"),
                highLabel: text("Go all out"),
                symbol: "person.2"
            ),
            Self(
                step: .othersOpinion,
                title: text("What others think"),
                subtitle: text("Are you hardly bothered by what others think of you, or does it matter quite a lot to you?"),
                lowLabel: text("Not bothered"),
                highLabel: text("Matters to me"),
                symbol: "person.2"
            ),
        ]),
        Section(category: .contact, title: text("Contact and conversation"), questions: [
            Self(
                step: .talkativeness,
                title: text("Quiet or talkative"),
                subtitle: text("Are you naturally on the quiet side, or do you love to talk about anything and everything?"),
                lowLabel: text("Quiet"),
                highLabel: text("Talkative"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .humor,
                title: text("Humour"),
                subtitle: text("Is your humour mostly dry and subtle, or silly and goofy?"),
                lowLabel: text("Dry and subtle"),
                highLabel: text("Silly and goofy"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .texting,
                title: text("Keeping in touch"),
                subtitle: text("When you are apart, is a message or call now and then enough, or do you like to hear from each other all day?"),
                lowLabel: text("Now and then"),
                highLabel: text("All day"),
                symbol: "bubble.left.and.bubble.right"
            ),
            Self(
                step: .communicationStyle,
                title: text("Communication style"),
                subtitle: text("Do you choose your words carefully, or do you just say what you think?"),
                lowLabel: text("Tactful"),
                highLabel: text("Direct"),
                symbol: "bubble.left.and.bubble.right"
            ),
        ]),
        Section(category: .character, title: text("Character and choices"), questions: [
            Self(
                step: .punctuality,
                title: text("Keeping time"),
                subtitle: text("Do you usually arrive roughly on time, or are you always exactly on time?"),
                lowLabel: text("Roughly on time"),
                highLabel: text("Always on time"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .newExperiences,
                title: text("New experiences"),
                subtitle: text("Do you love what is familiar, or are you always looking for something new?"),
                lowLabel: text("Familiar"),
                highLabel: text("Adventurous"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .perfectionism,
                title: text("Perfectionism"),
                subtitle: text("Are you happy once something is good enough, or does it really have to be perfect?"),
                lowLabel: text("Good enough"),
                highLabel: text("Perfect"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .takingInitiative,
                title: text("Taking the lead"),
                subtitle: text("Do you happily let others make the plans, or do you prefer to take the lead?"),
                lowLabel: text("Follow"),
                highLabel: text("Take the lead"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .decisionMaking,
                title: text("Making decisions"),
                subtitle: text("Do you make decisions quickly, or do you take your time to weigh things up?"),
                lowLabel: text("Quickly"),
                highLabel: text("Take my time"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .workAmbition,
                title: text("Work and ambition"),
                subtitle: text("Do you mainly work to live, or are career and growth important goals for you?"),
                lowLabel: text("Work to live"),
                highLabel: text("Career and growth"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .rules,
                title: text("Rules"),
                subtitle: text("Do you stick to the rules, or do you bend them when they seem pointless?"),
                lowLabel: text("Rules are rules"),
                highLabel: text("Happy to bend them"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .pride,
                title: text("Modest or proud"),
                subtitle: text("Do you keep your successes to yourself, or do you proudly share them?"),
                lowLabel: text("Modest"),
                highLabel: text("Proud"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .weeklyPlanning,
                title: text("Weekly planning"),
                subtitle: text("Do you like keeping your week open for spontaneous plans, or do you plan it in advance?"),
                lowLabel: text("Spontaneous"),
                highLabel: text("Planned ahead"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .personalStyle,
                title: text("Clothing and style"),
                subtitle: text("Do you dress mainly for comfort, or do you put a lot of care into your style?"),
                lowLabel: text("Comfort first"),
                highLabel: text("Stylish"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .headOrHeart,
                title: text("Head or heart"),
                subtitle: text("When making important choices, do you mostly follow your head, or your heart?"),
                lowLabel: text("Head"),
                highLabel: text("Heart"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .patience,
                title: text("Patience"),
                subtitle: text("Are you patient, or do you want things to happen right away?"),
                lowLabel: text("Patient"),
                highLabel: text("Right away"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .spirituality,
                title: text("Spirituality"),
                subtitle: text("Do you see life mainly in a rational way, or are you spiritually minded?"),
                lowLabel: text("Rational"),
                highLabel: text("Spiritual"),
                symbol: "slider.horizontal.3"
            ),
            Self(
                step: .boundaries,
                title: text("Setting boundaries"),
                subtitle: text("Do you find it hard to say no, or do you set your boundaries easily?"),
                lowLabel: text("Hard to say no"),
                highLabel: text("Say no easily"),
                symbol: "slider.horizontal.3"
            ),
        ]),
        Section(category: .feelings, title: text("Feelings and conflict"), questions: [
            Self(
                step: .optimism,
                title: text("Optimism"),
                subtitle: text("Do you tend to see what could go wrong, or do you trust that things will work out?"),
                lowLabel: text("See the risks"),
                highLabel: text("It will work out"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .stressContact,
                title: text("Contact during stress"),
                subtitle: text("When you are stressed, do you first need some space, or do you look for support from your partner?"),
                lowLabel: text("Space first"),
                highLabel: text("Seek support"),
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
                step: .setbacks,
                title: text("Setbacks"),
                subtitle: text("When something goes wrong, do you shake it off quickly, or does it stay with you for a while?"),
                lowLabel: text("Shake it off"),
                highLabel: text("Stays with me"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .listeningAndSolutions,
                title: text("Solve or listen"),
                subtitle: text("When someone tells you about a problem, do you jump straight to solutions, or do you listen first?"),
                lowLabel: text("Solve it"),
                highLabel: text("Listen first"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .makingUp,
                title: text("Making up"),
                subtitle: text("After an argument, do you wait for the other person, or are you usually the first to make up?"),
                lowLabel: text("Wait for them"),
                highLabel: text("Make the first move"),
                symbol: "bolt.heart"
            ),
            Self(
                step: .emotionalExpression,
                title: text("Showing emotions"),
                subtitle: text("Do you keep your feelings to yourself, or can people see right away how you feel?"),
                lowLabel: text("Keep them to myself"),
                highLabel: text("Open book"),
                symbol: "bolt.heart"
            ),
        ]),
        Section(category: .closeness, title: text("Closeness and space"), questions: [
            Self(
                step: .aloneTime,
                title: text("Time for yourself"),
                subtitle: text("How much time do you need for yourself, apart from your partner?"),
                lowLabel: text("Little time alone"),
                highLabel: text("Lots of time alone"),
                symbol: "heart"
            ),
            Self(
                step: .publicAffection,
                title: text("Affection in public"),
                subtitle: text("Do you keep affection for at home, or do you also like to show it in public?"),
                lowLabel: text("Only at home"),
                highLabel: text("In public too"),
                symbol: "heart"
            ),
            Self(
                step: .partnerSocializing,
                title: text("Including your partner"),
                subtitle: text("Do you each keep your own social life, or do you like to join each other often?"),
                lowLabel: text("Separate"),
                highLabel: text("Often together"),
                symbol: "heart"
            ),
            Self(
                step: .physicalAffection,
                title: text("Physical affection"),
                subtitle: text("How much touch, cuddling and physical closeness do you need in a relationship?"),
                lowLabel: text("Now and then"),
                highLabel: text("Lots of closeness"),
                symbol: "heart"
            ),
            Self(
                step: .relationshipPrivacy,
                title: text("Privacy in a relationship"),
                subtitle: text("Do you like to keep things like your phone and calendar to yourself, or can your partner see everything?"),
                lowLabel: text("Own privacy"),
                highLabel: text("Share everything"),
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
            Self(
                step: .romanticGestures,
                title: text("Romance"),
                subtitle: text("Do you like to keep love simple, or do you dream of big romantic gestures and surprises?"),
                lowLabel: text("Keep it simple"),
                highLabel: text("Hopeless romantic"),
                symbol: "heart"
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
