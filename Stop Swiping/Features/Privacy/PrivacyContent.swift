import Foundation

/// NL/EN privacy copy. The approval screens show short points first; the
/// sections hold the complete terms the user agrees to. Changing the meaning
/// of any approval text requires bumping `PrivacyConsentKind.version`.
enum PrivacyContent {
    struct Point: Hashable {
        let symbol: String
        let title: String
        let text: String
    }

    struct Section: Hashable {
        let title: String
        let body: String
    }

    struct Approval {
        let title: String
        let points: [Point]
        let sections: [Section]
        let acknowledgement: String
    }

    static func approval(_ kind: PrivacyConsentKind, language: AppLanguage) -> Approval {
        switch (kind, language) {
        case (.profile, .english):
            profileEN
        case (.matching, .english):
            matchingEN
        case (.profile, .dutch):
            profileNL
        case (.matching, .dutch):
            matchingNL
        }
    }

    static func policy(language: AppLanguage) -> String {
        switch language {
        case .english: policyEN
        case .dutch: policyNL
        }
    }

    // MARK: - Profile

    private static let profileEN = Approval(
        title: "Please read!",
        points: [
            Point(symbol: "iphone",
                  title: "Stays on your iPhone",
                  text: "Your profile is stored on your phone. Manual matching goes from phone to phone, never through our server."),
            Point(symbol: "chart.bar",
                  title: "Scores, not answers",
                  text: "When you match, you both see a score per category and how much it counts, plus basic details such as name, age and religion. Your answers to the questions stay hidden."),
            Point(symbol: "pin",
                  title: "Fixed at that moment",
                  text: "A match keeps the result from that moment. Later edits don't change it, and we can't recall screenshots."),
            Point(symbol: "icloud",
                  title: "Backup in your own iCloud",
                  text: "With an account, your profile and saved matches are backed up encrypted to your own iCloud. We can't see them."),
            Point(symbol: "sparkles",
                  title: "Automatic matching is separate",
                  text: "We'll ask your permission for that later.")
        ],
        sections: [
            Section(title: "Storage on your phone",
                    body: "Your answers, importance ratings, preferences, dealbreakers and saved matches are stored on your iPhone. Depending on your settings, they may also be included in your Apple device backup, which is governed by Apple's terms."),
            Section(title: "Backup in your iCloud",
                    body: "If you create an account, we back up your profile, photos and saved matches to your own iCloud, end-to-end encrypted. We have no access to it. The backup doesn't make your profile visible and doesn't sign you up for matching. Signing in with Apple or Google runs through our provider Supabase."),
            Section(title: "How manual matching works",
                    body: "You match by scanning someone's QR code or by holding your phones together. Whoever scans a QR code sees the match, so only show yours to people you want to match with. A code stops working after 24 hours. Phone to phone, you both have to start it. Neither way goes through our server."),
            Section(title: "What the other person sees",
                    body: "A score for each category of questions, how much each category counts, the total score, and which of each other's requirements aren't met. Plus your basic details: name, age, area and distance, height, gender, who you're looking for, religion, languages, children and use of alcohol, tobacco and drugs. Phone to phone, your photo is included if you've turned that on. Your answers to individual questions and how important each one is to you are never shown."),
            Section(title: "Information already shared",
                    body: "A match saves the result once. Later edits, new questions or a new calculation don't change it. The other person can take screenshots; we can't remove copies kept outside the app."),
            Section(title: "Security",
                    body: "Your profile travels sealed to the other phone, which works out the result and doesn't keep your answers. The seal keeps your answers unreadable in the app, in QR readers and on our website, but someone who takes the app apart could open it. We don't sell your information or use your answers for advertising."),
            Section(title: "Deleting",
                    body: "You can delete saved matches one by one; they then disappear from your phone and your iCloud backup. Deleting your profile removes everything from your phone and your backup. Your rights are set out in the Privacy Policy; you can also contact us via [PRIVACY_CONTACT]."),
            Section(title: "Automatic matching",
                    body: "Automatic matching stores and compares your answers on our server. We only do this with your separate, explicit consent.")
        ],
        acknowledgement: "I understand how my profile is stored and what someone I match with gets to see."
    )

    private static let profileNL = Approval(
        title: "Even lezen!",
        points: [
            Point(symbol: "iphone",
                  title: "Blijft op je iPhone",
                  text: "Je profiel staat op je telefoon. Handmatig matchen gaat van telefoon naar telefoon, nooit via onze server."),
            Point(symbol: "chart.bar",
                  title: "Scores, geen antwoorden",
                  text: "Bij een match zien jullie per categorie een score en hoe zwaar die weegt, plus basisgegevens zoals naam, leeftijd en geloof. Je antwoorden op de vragen blijven verborgen."),
            Point(symbol: "pin",
                  title: "Vastgelegd op dat moment",
                  text: "Een match houdt de uitkomst van dat moment. Latere wijzigingen veranderen die niet, en screenshots kunnen we niet terughalen."),
            Point(symbol: "icloud",
                  title: "Back-up in je eigen iCloud",
                  text: "Met een account komen je profiel en bewaarde matches versleuteld in je eigen iCloud. Wij kunnen er niet bij."),
            Point(symbol: "sparkles",
                  title: "Automatisch matchen is apart",
                  text: "Daarvoor vragen we later apart toestemming.")
        ],
        sections: [
            Section(title: "Opslag op je telefoon",
                    body: "Je antwoorden, wegingen, voorkeuren, breekpunten en bewaarde matches staan op je iPhone. Afhankelijk van je instellingen komen ze ook in je Apple-reservekopie terecht; daarvoor gelden de voorwaarden van Apple."),
            Section(title: "Back-up in je iCloud",
                    body: "Maak je een account aan, dan zetten we je profiel, foto's en bewaarde matches end-to-end versleuteld in je eigen iCloud. Wij kunnen er niet bij. De back-up maakt je profiel niet zichtbaar en meldt je niet aan voor matching. Inloggen met Apple of Google loopt via onze dienstverlener Supabase."),
            Section(title: "Zo werkt handmatig matchen",
                    body: "Je matcht door iemands QR-code te scannen of jullie telefoons bij elkaar te houden. Wie een QR-code scant, ziet de match; laat de jouwe dus alleen zien aan mensen met wie je wilt matchen. Een code werkt 24 uur. Van telefoon naar telefoon moeten jullie het allebei starten. Geen van beide gaat via onze server."),
            Section(title: "Wat de ander ziet",
                    body: "Per categorie vragen een score en hoe zwaar die weegt, de totaalscore en aan welke eisen van elkaar jullie niet voldoen. Daarnaast je basisgegevens: naam, leeftijd, woonplaats en afstand, lengte, gender, wie je zoekt, geloof, talen, kinderen en gebruik van alcohol, tabak en drugs. Van telefoon naar telefoon gaat ook je foto mee als je dat hebt aangezet. Je antwoorden op losse vragen en hoe belangrijk je elke vraag vindt, zijn nooit te zien."),
            Section(title: "Eerder gedeelde gegevens",
                    body: "Een match legt de uitkomst één keer vast. Latere wijzigingen, nieuwe vragen of een nieuwe berekening veranderen daar niets aan. De ander kan screenshots maken; kopieën buiten de app kunnen wij niet verwijderen."),
            Section(title: "Beveiliging",
                    body: "Je profiel gaat verzegeld naar de andere telefoon. Die rekent de uitkomst uit en bewaart je antwoorden niet. Het zegel houdt je antwoorden onleesbaar in de app, in QR-lezers en op onze website, maar wie de app uit elkaar haalt, kan het openen. We verkopen je gegevens niet en gebruiken je antwoorden niet voor advertenties."),
            Section(title: "Verwijderen",
                    body: "Bewaarde matches verwijder je één voor één; ze verdwijnen dan van je telefoon en uit je iCloud-back-up. Verwijder je je profiel, dan gaat alles van je telefoon en uit je back-up. Je rechten staan in de Privacyverklaring; je kunt ons ook bereiken via [PRIVACYCONTACT]."),
            Section(title: "Automatisch matchen",
                    body: "Bij automatisch matchen bewaren en vergelijken we je antwoorden op onze server. Dat doen we alleen met je aparte, uitdrukkelijke toestemming.")
        ],
        acknowledgement: "Ik begrijp hoe mijn profiel wordt opgeslagen en wat iemand met wie ik match te zien krijgt."
    )

    // MARK: - Automatic matching

    private static let matchingEN = Approval(
        title: "Automatic matching",
        points: [
            Point(symbol: "server.rack",
                  title: "Compared on our server",
                  text: "To find matches, we store your answers, importance ratings and dealbreakers on our server. They include sensitive topics: religion, sexuality and alcohol, tobacco and drugs."),
            Point(symbol: "person.2",
                  title: "Shared when you match",
                  text: "When you match, you both immediately see each other's photo, basic details and a score per category. Your answers stay hidden. You don't approve each match first."),
            Point(symbol: "pin",
                  title: "Fixed at that moment",
                  text: "Scores don't change after you match. Your edits only count for new matches."),
            Point(symbol: "power",
                  title: "Turn it off anytime",
                  text: "Your matching profile is then removed from our server. What a match has already seen stays with them."),
            Point(symbol: "lock",
                  title: "Private stays private",
                  text: "Chats are end-to-end encrypted. We don't sell your information or use it for advertising.")
        ],
        sections: [
            Section(title: "What we use",
                    body: "Your matching profile: all answers, importance ratings, preferences, dealbreakers and basic details, your photos, and the technical data needed to compare profiles. We store it with our provider Supabase. This includes special categories of personal data: your religion or worldview, your gender and the genders you're interested in (which reveal your sexual orientation), your wishes around sex and intimacy, and how often you use alcohol, tobacco and drugs. The photo check runs on your phone; we only receive whether it passed."),
            Section(title: "How matching works",
                    body: "We first check dealbreakers and requirements in both directions. Then we calculate a score for each category from your answers and importance ratings; together they make up the total score. A match is only created when all requirements are met. The score is a calculation, not a prediction of relationship success."),
            Section(title: "What a match sees",
                    body: "Your photo and basic details: name, age, area and distance, height, gender, who you're looking for, religion, languages, children and use of alcohol, tobacco and drugs. Plus a score per category, how much each category counts, and the total score. Your answers to individual questions and how important each one is to you are never shown. By turning on matching you agree to this in advance; we don't ask again for each match."),
            Section(title: "Fixed scores",
                    body: "When a match is created, the result is saved once. Later edits don't change it, so an older score may differ from your current answers. New matches use your latest information. Your match keeps the photo they were shown, also after the match ends."),
            Section(title: "Security",
                    body: "Data is protected in transit and at rest, and access is restricted. We keep account details apart from matching data where possible. Because our server has to compare your answers, this processing is not end-to-end encrypted."),
            Section(title: "Turning matching off",
                    body: "Your matching profile and photos are removed from our server straight away. During an active match they stay until that match ends. If you don't open the app for 6 months, you're taken out of matching automatically. Existing matches and what they've seen don't disappear. Your iCloud backup isn't affected."),
            Section(title: "Chats and reports",
                    body: "Chats are end-to-end encrypted; we only process what delivery requires, such as account IDs and timestamps. Messages are kept for up to 12 months, also after a match ends. If you add messages to a report yourself, we can review that content."),
            Section(title: "Withdrawal and your rights",
                    body: "You can withdraw your consent at any time by turning off automatic matching. This stops further processing but doesn't make earlier processing unlawful. You can exercise your privacy rights via [PRIVACY_CONTACT]. The providers we use are listed in the Privacy Policy.")
        ],
        acknowledgement: "I explicitly consent to my matching profile, including sensitive answers about my religion, sexuality and substance use, being stored and automatically compared on the server to find matches, and to each match automatically seeing my photo, basic details and scores per category. I can withdraw this consent at any time; what a match has already seen stays with them."
    )

    private static let matchingNL = Approval(
        title: "Automatisch matchen",
        points: [
            Point(symbol: "server.rack",
                  title: "Vergeleken op onze server",
                  text: "Om matches te vinden bewaren we je antwoorden, wegingen en breekpunten op onze server. Daar zitten gevoelige onderwerpen tussen: geloof, seksualiteit en alcohol, tabak en drugs."),
            Point(symbol: "person.2",
                  title: "Gedeeld bij een match",
                  text: "Bij een match zien jullie meteen elkaars foto, basisgegevens en per categorie een score. Je antwoorden blijven verborgen. Je keurt niet elke match vooraf goed."),
            Point(symbol: "pin",
                  title: "Vastgelegd op dat moment",
                  text: "Scores veranderen niet meer na een match. Je wijzigingen tellen alleen voor nieuwe matches."),
            Point(symbol: "power",
                  title: "Altijd uit te zetten",
                  text: "Je matchingprofiel verdwijnt dan van onze server. Wat een match al heeft gezien, blijft bij die persoon."),
            Point(symbol: "lock",
                  title: "Privé blijft privé",
                  text: "Chats zijn end-to-end versleuteld. We verkopen je gegevens niet en gebruiken ze niet voor advertenties.")
        ],
        sections: [
            Section(title: "Welke gegevens",
                    body: "Je matchingprofiel: alle antwoorden, wegingen, voorkeuren, breekpunten en basisgegevens, je foto's en de technische gegevens die nodig zijn om te vergelijken. We bewaren dit bij onze dienstverlener Supabase. Daaronder vallen bijzondere persoonsgegevens: je geloof of levensovertuiging, je gender en de genders waarin je geïnteresseerd bent (waaruit je seksuele voorkeur blijkt), je wensen rond seks en intimiteit, en hoe vaak je alcohol, tabak en drugs gebruikt. De fotocontrole gebeurt op je telefoon; wij krijgen alleen te horen of die gelukt is."),
            Section(title: "Hoe matching werkt",
                    body: "Eerst controleren we breekpunten en eisen, in beide richtingen. Daarna berekenen we per categorie een score uit je antwoorden en wegingen; samen vormen die de totaalscore. Alleen als aan alle eisen is voldaan, ontstaat een match. De score is een rekenuitkomst, geen voorspelling van een geslaagde relatie."),
            Section(title: "Wat een match ziet",
                    body: "Je foto en basisgegevens: naam, leeftijd, woonplaats en afstand, lengte, gender, wie je zoekt, geloof, talen, kinderen en gebruik van alcohol, tabak en drugs. Daarnaast per categorie een score, hoe zwaar elke categorie weegt en de totaalscore. Je antwoorden op losse vragen en hoe belangrijk je elke vraag vindt, zijn nooit te zien. Door matching aan te zetten geef je hier vooraf toestemming voor; we vragen het niet per match opnieuw."),
            Section(title: "Vaste scores",
                    body: "Bij een match leggen we de uitkomst één keer vast. Latere wijzigingen veranderen die niet, dus een oude score kan afwijken van je huidige antwoorden. Nieuwe matches gebruiken je nieuwste gegevens. De foto die je match te zien kreeg, blijft ook na het einde van de match bij die persoon."),
            Section(title: "Beveiliging",
                    body: "Gegevens zijn beveiligd tijdens verzending en opslag, en toegang is beperkt. Waar mogelijk houden we accountgegevens gescheiden van matchinggegevens. Omdat onze server je antwoorden moet vergelijken, is deze verwerking niet end-to-end versleuteld."),
            Section(title: "Matching uitzetten",
                    body: "Je matchingprofiel en foto's worden meteen van onze server verwijderd. Tijdens een lopende match blijven ze staan tot die match voorbij is. Open je de app 6 maanden niet, dan doe je automatisch niet meer mee. Bestaande matches en wat zij hebben gezien, verdwijnen niet. Je iCloud-back-up blijft zoals hij is."),
            Section(title: "Chats en meldingen",
                    body: "Chats zijn end-to-end versleuteld; we verwerken alleen wat nodig is voor aflevering, zoals account-ID's en tijdstippen. Berichten bewaren we maximaal 12 maanden, ook nadat een match is beëindigd. Voeg je zelf berichten toe aan een melding, dan kunnen wij die inhoud bekijken."),
            Section(title: "Intrekken en je rechten",
                    body: "Je kunt je toestemming altijd intrekken door automatisch matchen uit te zetten. Dat stopt verdere verwerking, maar maakt eerdere verwerking niet onrechtmatig. Je privacyrechten oefen je uit via [PRIVACYCONTACT]. Welke dienstverleners we gebruiken, staat in de Privacyverklaring.")
        ],
        acknowledgement: "Ik geef uitdrukkelijk toestemming om mijn matchingprofiel, inclusief gevoelige antwoorden over mijn geloof, seksualiteit en middelengebruik, op de server op te slaan en automatisch te vergelijken om matches te vinden, en om iedere match automatisch mijn foto, basisgegevens en scores per categorie te laten zien. Ik kan deze toestemming altijd intrekken; wat een match al heeft gezien, blijft bij die persoon."
    )

    private static let policyEN = #"""
# Privacy Policy — [APP_NAME]

**Version:** [VERSION_NUMBER]  
**Effective date:** [DATE]  
**Last updated:** [DATE]  
**Privacy contact:** [PRIVACY_EMAIL]  
**Public URL:** [PRIVACY_POLICY_URL]


## 1. Who is responsible for your data?

[LEGAL_ENTITY_NAME], located at [POSTAL_ADDRESS], [POSTCODE_AND_CITY], [COUNTRY], registered under [COMPANY_REGISTRATION_NUMBER], is the controller of personal data processed in [APP_NAME] as described in this policy (“we”, “us”, or “the app”).

You can contact us at [GENERAL_CONTACT_EMAIL], or send privacy requests to [PRIVACY_EMAIL]. If a data protection officer has been appointed, you may contact them at [DPO_CONTACT_OR_NOT_APPLICABLE].

## 2. Who can use the app?

[APP_NAME] is intended for people aged 18 or over. Minors may not use the service. We use [AGE_ASSURANCE_APPROACH] to support this age restriction. If we discover that a minor has an account, we follow [UNDERAGE_ACCOUNT_PROCEDURE].

## 3. What personal data do we process?

The data we process depends on the features you choose.

### 3.1 Local profile
You can answer questions and build a profile on your iPhone. This can include up to [QUESTION_COUNT; INTENDED: 50] answers scored 1–5, importance ratings of 1–5, dealbreakers, preferences, and other information you provide. These data are stored locally on your device. Depending on your settings, they may also be included in an Apple device backup. Manual matching (QR code or phone to phone) happens between the two devices and never goes through our server. Unless you enable automatic matching, we do not send your matching profile to our server.

### 3.2 Account and identity data
If you create an account, we process [ACCOUNT_DATA, E.G. AUTH ID, EMAIL ADDRESS, LOGIN PROVIDER], relevant account status, and [ADDITIONAL_IDENTITY_INFORMATION]. Authentication data are handled by Supabase Auth and, where chosen, [THIRD_PARTY_SIGN_IN_PROVIDER]. Your profile name and photo may be stored separately so they can be shown to matches.

### 3.3 iCloud backup
If you create an account, your profile, photos and saved matches are backed up to your own iCloud account, end-to-end encrypted, so you can restore them on another device. We cannot access this backup. It does not enroll you in matching and is never visible to other users. Apple's terms apply to iCloud.

### 3.4 Automatic matching
If you expressly enable automatic matching, we store your matching profile on our server for as long as matching is on: answers, importance ratings, dealbreakers, preferences, basic details, photos, profile version, matching status, and information necessary to find candidates and calculate scores. The photo check runs on your device; we only record whether it passed. Your answers may reveal health information, religious beliefs, sexual orientation or other special-category personal data.

### 3.5 Matches
A match shows each person a score per question category, the weight of each category, the total score and, for manual matches, which requirements are not met, plus basic details: name, age, area and distance, height, gender, who they are looking for, religion, languages, children and use of alcohol, tobacco and drugs, and a photo where applicable. Answers to individual questions and their importance ratings are never shown. For a manual match, the profile travels sealed between the two devices; the receiving device calculates the result and keeps only what is shown. For an automatic match, we process the linked account identifiers, the match time and the fixed scores; the partner's photo is shown by our server only during an active match, and the recipient's device keeps a copy.

The sealed profile (in a QR code, between two phones, and as the match card on our server) is encrypted with a key built into the app, because two phones must be able to read each other's profile without our server. The seal keeps answers out of sight in the app, in QR readers, on our website and in our database, but it does not protect against someone who takes the app apart. That is why a QR code expires after 24 hours, screens never show answers to individual questions, and we do not open match cards.

### 3.6 Chats and communications metadata
Message content is end-to-end encrypted. Each message is encrypted on the sender's phone for the recipient's phone and for the sender's own copy (HPKE with X25519 and ChaCha20-Poly1305, RFC 9180). The keys stay on the phone and are not included in any backup. The keys of a conversation do not change while it lasts, so someone who gains access to an unlocked phone with that conversation's key could read its history; you can compare a security code with your match to check that no one is in between. We process encrypted messages and, where necessary, metadata such as participating account IDs, delivery states and timestamps. We cannot read the content of messages delivered normally. If someone voluntarily submits messages with a safety report, we can process the content they have submitted.

### 3.7 Technical and safety data
To keep the service secure and available and prevent misuse, we process the necessary [IP ADDRESS, APP VERSION, DEVICE/SESSION IDENTIFIERS, ERROR AND SECURITY LOGS, REPORTS AND BLOCKS; ADJUST TO REAL USE]. We minimize log contents and do not log complete matching answers, decryption keys or readable chat content.

### 3.8 Other features
[DESCRIBE ANY ANALYTICS, CRASH REPORTING, PAYMENT PROVIDERS, SUBSCRIPTIONS, NOTIFICATIONS, LOCATION OR MARKETING, OR CONFIRM THEY ARE NOT USED]. If push notifications are enabled, the relevant platform services process a push token and delivery metadata; readable private-message content is not included in push notifications.

## 4. For what purposes and on what legal bases do we use data?

| Processing activity | Purpose | GDPR legal basis |
| --- | --- | --- |
| Local profile and core features, to the extent processed by us | Let you create and use your profile | Performance of a contract, Art. 6(1)(b), where applicable |
| Account management and sign-in | Provide and secure your account | Performance of a contract, Art. 6(1)(b) |
| iCloud backup | Restore your profile and saved matches | [SELECT AND JUSTIFY: CONSENT ART. 6(1)(a) OR CONTRACT ART. 6(1)(b)] |
| Manual matching between two devices | Show the match you start | [SELECT AND JUSTIFY: ART. 6(1)(a) OR 6(1)(b)] and, if required, a relevant Art. 9 GDPR exception |
| Automatic matching and automatic sharing with matches | Find compatible people, calculate scores and show matches to each other | Explicit consent, Art. 6(1)(a); for special-category data, Art. 9(2)(a) |
| E2EE chat and delivery | Enable communication between matches | Performance of a contract, Art. 6(1)(b) |
| Essential security and abuse investigations | Prevent and respond to incidents | Legitimate interests, Art. 6(1)(f), following a balancing test; with an additional condition for special-category data where required |
| Mandatory legal records | Comply with applicable law | Legal obligation, Art. 6(1)(c) |
| [OTHER PROCESSING] | [PURPOSE] | [LEGAL BASIS] |

Consent is voluntary, specific and withdrawable for future processing relying on it. Creating an account does not enable automatic matching. We assess in advance whether explicit consent and any other GDPR requirements are suitable and sufficient for processing special-category data.

## 5. How do automatic matching and compatibility percentages work?

Our matching service compares profiles of users who have enabled automatic matching. First, it checks dealbreakers and mandatory criteria in both directions. It then compares numerical answers question by question, taking each participant's importance ratings into account, and shows the result as a score per category; together these make up the total score. The exact method for the weighted percentage is [FINAL FORMULA, NORMALIZATION, TREATMENT OF UNANSWERED QUESTIONS AND MATCH THRESHOLD].

A match is created only when the criteria are met. The scores and details shared with both parties are fixed at the time of matching and are not automatically changed by later edits. The percentage represents calculated overlap, not a guarantee or prediction of relationship success.

This automated assessment determines which participants qualify for matches and consequently see each other's scores and details. Assess whether it can have legal or similarly significant effects: [ARTICLE 22 GDPR ASSESSMENT AND FINDING]. You can ask questions about the method or an outcome via [MATCHING_EXPLANATION_CONTACT]. Where required by the GDPR, we provide applicable rights and safeguards relating to automated decision-making.

## 6. With whom do we share personal data?

We disclose personal data only for the stated purposes:

- **Other users:** following a manual match you start or automatic matching to which you have expressly consented. They see the scores and details described above and may retain copies themselves.
- **Supabase:** to provide database hosting, authentication, storage, application functions and related technical services under applicable agreements.
- **[OTHER PROCESSORS INCLUDING PUSH, LOGGING, EMAIL, KMS OR HOSTING PROVIDERS]:** only for specified services under suitable contractual protections.
- **Competent authorities:** if legally required or otherwise supported by an applicable lawful basis.

We do not sell profile and matching information to advertisers or data brokers and do not use questionnaire answers for targeted advertising. We do not send matching answers to external AI providers for model training [VERIFY ACTUAL IMPLEMENTATION].

## 7. Where do we process data and do we transfer it outside the EEA?

The primary Supabase project region is [EXACT SUPABASE REGION, E.G. eu-central-1, FRANKFURT, GERMANY]. Locations of application functions, logs, storage/caching, support and any additional providers are [LIST OF REGIONS]. The primary database region does not necessarily mean that all processing or transfers stay within the EEA.

Where personal data are transferred outside the EEA, we use [APPLICABLE TRANSFER MECHANISM, E.G. ADEQUACY DECISION OR STANDARD CONTRACTUAL CLAUSES AND SUPPLEMENTARY MEASURES] where necessary. Information about the applicable safeguards is available through [PRIVACY_EMAIL].

## 8. How do we keep data secure?

We use appropriate technical and organizational measures, including encrypted connections, encryption at rest, access controls, separation of account and matching functions, secured authentication, restricted administrative permissions, backup management, and security reviews. Where practical, identifying data are separated from matching records and pseudonymous identifiers are used. A pseudonymous profile is not anonymous while it can be linked back to an account.

The matching service must be able to process necessary answers during scoring. Matching-profile processing is therefore not end-to-end encrypted against our entire system. Ordinary chat content is end-to-end encrypted, so our servers cannot read it. No security measure can eliminate every risk.

## 9. How long do we keep personal data?

| Data category | Retention rule |
| --- | --- |
| Local profile | Until you delete the profile or app data from your device, subject to external device backups |
| Account information | While the account exists; removed when you delete your account. After 12 months without app activity only the sign-in itself remains (to sign in again and keep purchases) |
| iCloud backup | In your own iCloud until you delete saved matches or your profile; we have no access |
| Matching profile and photos | While matching is enabled; removed immediately when you turn it off (during an active match, once it ends), with any leftovers removed within a day. After 6 months without app activity you leave the matching pool; after 12 months the profile and photos are removed |
| Match scores and match records | The match (both account IDs, the fixed scores, dates and how it ended) and keyed hashes of both sign-in identities, so the same two people are never matched again, also after deleting and recreating an account: until 5 years after the match ended. Match cards, chat keys and read positions: 12 months after the match ended, or as soon as both people deleted the match |
| Encrypted E2EE message content | Up to 12 months after sending, also after a match ends |
| Technical logs and metadata | No more than [NUMBER_OF_DAYS], except for security investigations |
| Evidence of consent | [RETENTION NEEDED FOR ACCOUNTABILITY AND LIMITATION PERIODS] |
| Safety reports and blocks | The written explanation: 12 months. The report itself (reason, date and a keyed hash of the reported person's sign-in identity), which counts towards a block or ban, also for a new account with the same Apple or Google ID: 5 years after it was filed. A ban ends once the oldest of its three reports is older than 5 years |
| Backups and deleted copies | Rotated out under [MAXIMUM_BACKUP_RETENTION AND ROTATION] |
| Mandatory tax or legal records | As required under [LEGAL RETENTION PERIOD] |

Once you disable matching, your profile is no longer used to create new matches. Information already shown to a match cannot automatically be retrieved. When you request deletion, we also assess copies retained under our control; they are not kept indefinitely without a lawful reason.

## 10. What choices and rights do you have?

You may decline or later disable matching without losing your local profile. Your iCloud backup stays under your own control. Under the conditions of the GDPR, you have rights of access, rectification, erasure, restriction, portability and objection, and a right to withdraw consent. Additional rights may apply to automated decision-making.

Submit a request via [IN-APP PRIVACY REQUEST PATH] or [PRIVACY_EMAIL]. We may carry out necessary verification and ordinarily respond within one month, subject to lawful extensions. Withdrawal does not affect processing that was lawful before withdrawal. We cannot guarantee deletion of copies independently kept by recipients.

If you can create an account, you can also request deletion in the app at [DELETE ACCOUNT PATH].

## 11. Minors, safety and abuse

The service is for adults aged 18 or over. Users can block another person or report inappropriate behavior at [BLOCK_AND_REPORT_PATH]. Our staff cannot normally read E2EE message contents. A reporting user may, however, voluntarily provide relevant messages for review. We handle safety reports through [SAFETY_REPORTING_PROCESS_AND_CONTACT].

## 12. Changes to this policy

We may update this policy as the app, our providers or applicable laws change. The latest version is at [PRIVACY_POLICY_URL]. We inform users of material changes through [NOTICE_METHOD]. Where new consent is required, we ask for it before the relevant processing begins.

## 13. Complaints

For questions or complaints, contact [PRIVACY_EMAIL]. You may also lodge a complaint with the Dutch Data Protection Authority (Autoriteit Persoonsgegevens) at https://autoriteitpersoonsgegevens.nl or with another competent European supervisory authority.
"""#

    private static let policyNL = #"""
# Privacyverklaring — [APPNAAM]

**Versie:** [VERSIENUMMER]  
**Ingangsdatum:** [DATUM]  
**Laatste wijziging:** [DATUM]  
**Contact:** [PRIVACY_E-MAIL]  
**Openbaar adres:** [URL_PRIVACYVERKLARING]


## 1. Wie is verantwoordelijk?

[OFFICIËLE_BEDRIJFSNAAM], gevestigd aan [POSTADRES], [POSTCODE_EN_PLAATS], [LAND], ingeschreven onder [KVK_OF_REGISTRATIENUMMER], is de verwerkingsverantwoordelijke voor de hieronder omschreven verwerking van persoonsgegevens in [APPNAAM] (hierna: “wij” of “de app”).

Je kunt ons bereiken via [ALGEMEEN_CONTACTADRES] en voor privacyverzoeken via [PRIVACY_E-MAIL]. Onze functionaris voor gegevensbescherming, indien aangesteld, is bereikbaar via [CONTACT_FG_OF_NIET_VAN_TOEPASSING].

## 2. Voor wie is de app bedoeld?

[APPNAAM] is bedoeld voor personen van 18 jaar en ouder. Personen jonger dan 18 mogen de dienst niet gebruiken. We vragen [OMSCHRIJVING_LEEFTIJDSCONTROLE] om deze leeftijdsgrens te handhaven. Wanneer we vaststellen dat een minderjarige een account heeft, handelen we volgens [PROCEDURE_MINDERJARIGEN].

## 3. Welke persoonsgegevens verwerken we?

Welke gegevens we verwerken hangt af van de functies die je gebruikt.

### 3.1 Lokaal profiel
Je kunt op je iPhone vragen beantwoorden en een profiel opbouwen. Dit kan bestaan uit maximaal [AANTAL_VRAGEN; BEOGEN: 50] antwoorden met scores van 1 tot 5, belangrijkheidswegingen van 1 tot 5, breekpunten, voorkeuren en andere door jou ingevulde profielgegevens. Deze informatie wordt lokaal op je toestel opgeslagen. Afhankelijk van je instellingen kunnen gegevens ook in een reservekopie van Apple terechtkomen. Handmatig matchen (QR-code of telefoon naar telefoon) gebeurt tussen de twee toestellen en gaat nooit via onze server. Zonder automatische matching sturen we je matchingprofiel niet naar onze server.

### 3.2 Account- en identiteitsgegevens
Als je een account aanmaakt, verwerken we [ACCOUNTGEGEVENS: BIJV. AUTH-ID, E-MAILADRES, INLOGPROVIDER], relevante accountstatussen en [AANVULLENDE_IDENTITEITSGEGEVENS]. Auth-gegevens worden verwerkt via Supabase Auth en, indien gekozen, [INLOGPROVIDER]. Profielnaam en profielfoto kunnen afzonderlijk worden opgeslagen voor het zichtbaar maken van matches.

### 3.3 iCloud-back-up
Als je een account aanmaakt, komen je profiel, foto's en bewaarde matches end-to-end versleuteld in je eigen iCloud, zodat je ze op een ander toestel kunt herstellen. Wij hebben geen toegang tot deze back-up. Ze meldt je niet aan voor matching en is nooit zichtbaar voor andere gebruikers. Voor iCloud gelden de voorwaarden van Apple.

### 3.4 Automatische matching
Als je automatische matching uitdrukkelijk inschakelt, bewaren we je matchingprofiel op onze server zolang matching aanstaat: antwoorden, wegingen, breekpunten, voorkeuren, basisgegevens, foto's, profielversie, matchingstatus en de gegevens die nodig zijn om kandidaten te vinden en scores te berekenen. De fotocontrole gebeurt op je toestel; wij leggen alleen vast of die gelukt is. De antwoorden kunnen informatie onthullen over bijvoorbeeld gezondheid, religie, seksuele oriëntatie of andere bijzondere persoonsgegevens.

### 3.5 Matches
Bij een match ziet ieder per categorie vragen een score, hoe zwaar elke categorie weegt, de totaalscore en, bij handmatige matches, aan welke eisen niet wordt voldaan. Daarnaast basisgegevens: naam, leeftijd, woonplaats en afstand, lengte, gender, wie iemand zoekt, geloof, talen, kinderen en gebruik van alcohol, tabak en drugs, en waar van toepassing een foto. Antwoorden op losse vragen en de bijbehorende wegingen zijn nooit te zien. Bij een handmatige match gaat het profiel verzegeld van toestel naar toestel; het ontvangende toestel rekent de uitkomst uit en bewaart alleen wat getoond wordt. Bij een automatische match verwerken we de gekoppelde account-ID’s, de matchdatum en de vastgelegde scores; de foto van de ander toont onze server alleen tijdens een lopende match, en het toestel van de ontvanger bewaart een kopie.

Het verzegelde profiel (in een QR-code, tussen twee telefoons en als matchkaart op onze server) is versleuteld met een sleutel die in de app zit, omdat twee telefoons elkaars profiel zonder onze server moeten kunnen lezen. Het zegel houdt antwoorden uit het zicht in de app, in QR-lezers, op onze website en in onze database, maar beschermt niet tegen iemand die de app uit elkaar haalt. Daarom verloopt een QR-code na 24 uur, tonen schermen nooit antwoorden op losse vragen en openen wij matchkaarten niet.

### 3.6 Chats en communicatiegegevens
Chatinhoud is end-to-end versleuteld. Elk bericht wordt op de telefoon van de afzender versleuteld voor de telefoon van de ontvanger en voor de eigen kopie van de afzender (HPKE met X25519 en ChaCha20-Poly1305, RFC 9180). De sleutels blijven op de telefoon en gaan in geen enkele back-up mee. De sleutels van een gesprek wisselen niet zolang het gesprek loopt: wie toegang krijgt tot een ontgrendelde telefoon met de sleutel van dat gesprek, kan de geschiedenis ervan lezen. Met een veiligheidscode kun je met je match controleren dat niemand ertussen zit. Wij verwerken versleutelde berichten en, voor zover noodzakelijk, metadata zoals betrokken account-ID’s, afleverstatussen en tijdstippen. Wij kunnen de inhoud van normaal verzonden berichten niet lezen. Wanneer iemand chatinhoud vrijwillig bij een melding meestuurt, kunnen wij die aangeleverde inhoud wel verwerken.

### 3.7 Technische gegevens en veiligheid
Voor beveiliging, beschikbaarheid en misbruikbestrijding verwerken we voor zover nodig [IP-ADRES, APP-VERSIE, APPARAAT-/SESSIE-ID, FOUT- EN BEVEILIGINGSLOGS, MELDINGEN EN BLOKKADES; EXACT AANPASSEN]. We beperken de inhoud van logs en bewaren daarin geen volledige matchingantwoorden, decryptiesleutels of chatberichten in leesbare vorm.

### 3.8 Overige functies
[OMSCHRIJF EVENTUELE ANALYTICS, CRASHREPORTING, BETAALDIENSTEN, ABONNEMENTEN, NOTIFICATIES, LOCATIE OF MARKETING, OF VERMELD DAT DEZE NIET WORDEN GEBRUIKT]. Als pushnotificaties zijn ingeschakeld, verwerken de betrokken platformdiensten een apparaat-/pushtoken en aflevermetadata; we tonen geen leesbare privéberichtinhoud in pushberichten.

## 4. Waarom en op welke rechtsgrond verwerken we gegevens?

| Verwerking | Doel | Rechtsgrond AVG |
| --- | --- | --- |
| Lokaal profiel en basisbediening, voor zover verwerking door ons plaatsvindt | Je profiel kunnen maken en gebruiken | Uitvoering van de overeenkomst, art. 6 lid 1(b), voor zover van toepassing |
| Accountbeheer en inloggen | Je account beschikbaar houden en beveiligen | Uitvoering van de overeenkomst, art. 6 lid 1(b) |
| iCloud-back-up | Je profiel en bewaarde matches kunnen herstellen | [KIES EN ONDERBOUW: TOESTEMMING ART. 6(1)(a) OF OVEREENKOMST ART. 6(1)(b)] |
| Handmatig matchen tussen twee toestellen | De match tonen die je zelf start | [KIES EN ONDERBOUW: ART. 6(1)(a) OF 6(1)(b)] en waar noodzakelijk een uitzondering uit art. 9 AVG |
| Automatische matching en automatisch delen met matches | Compatibele personen vinden, scores berekenen en matches aan elkaar tonen | Uitdrukkelijke toestemming, art. 6 lid 1(a), en voor bijzondere persoonsgegevens art. 9 lid 2(a) |
| E2EE-chat en berichtaflevering | Communicatie tussen matches | Uitvoering van de overeenkomst, art. 6 lid 1(b) |
| Beveiliging en noodzakelijk misbruikonderzoek | Incidenten voorkomen en behandelen | Gerechtvaardigd belang, art. 6 lid 1(f), na belangenafweging; waar nodig aanvullende grondslag voor bijzondere gegevens |
| Wettelijke administratieve verplichtingen | Aan wettelijke verplichtingen voldoen | Wettelijke verplichting, art. 6 lid 1(c) |
| [EVENTUELE OVERIGE VERWERKING] | [DOEL] | [GRONDSLAG] |

Toestemming is vrijwillig, specifiek en kan voor toekomstige verwerking op die grond worden ingetrokken. Een account schakelt automatische matching niet vanzelf in. Als we bijzondere persoonsgegevens gebruiken, beoordelen we vooraf of uitdrukkelijke toestemming en andere AVG-vereisten passend en voldoende zijn.

## 5. Hoe werken automatische matches en matchpercentages?

Onze matchingservice vergelijkt de profielgegevens van gebruikers die automatische matching hebben ingeschakeld. Eerst controleren we breekpunten en noodzakelijke criteria in beide richtingen. Vervolgens vergelijken we per vraag de verschillen tussen de numerieke antwoorden, rekening houdend met de opgegeven belangrijkheidswegingen, en tonen we de uitkomst als score per categorie; samen vormen die de totaalscore. De methode voor het gewogen percentage is [OMSCHRIJVING DEFINITIEVE FORMULE, MAXIMUMAFWIJKING, OMGANG MET ONBEANTWOORDE VRAGEN EN DREMPELWAARDE].

Een match ontstaat alleen als de ingestelde criteria zijn gehaald. De scores en gegevens die beide personen te zien krijgen, worden op de matchdatum vastgelegd en wijzigen niet automatisch bij latere profielaanpassingen. De score is een rekenkundige overeenkomst, geen garantie of voorspelling van relatiesucces.

We gebruiken deze geautomatiseerde beoordeling om binnen de app te bepalen wie voor een match in aanmerking komt en wie elkaars scores en gegevens te zien krijgt. De beslissing heeft [BEOORDEEL OF ER SPRAKE KAN ZIJN VAN RECHTSGEVOLGEN OF VERGELIJKBAAR AANZIENLIJKE GEVOLGEN ONDER ART. 22 AVG]. Je kunt vragen stellen over de matchingmethode of een uitkomst via [CONTACT_MATCHING_UITLEG]. Waar de AVG dit vereist, bieden we de toepasselijke rechten en waarborgen bij geautomatiseerde besluitvorming.

## 6. Met wie delen we persoonsgegevens?

We delen persoonsgegevens alleen voor de hieronder omschreven doelen:

- **Andere gebruikers:** uitsluitend bij een handmatige match die je zelf start of bij automatische matching die je uitdrukkelijk hebt ingeschakeld. Zij zien dan de scores en gegevens zoals hierboven beschreven; zij kunnen zelf kopieën bewaren.
- **Supabase:** voor onze database, authenticatie, opslag, applicatiefuncties en technische dienstverlening op basis van de toepasselijke afspraken.
- **[OVERIGE VERWERKERS, INCLUSIEF PUSH-, LOG-, E-MAIL-, KMS- OF HOSTINGDIENSTEN]:** uitsluitend voor de benoemde functies en volgens passende overeenkomsten.
- **Bevoegde instanties:** indien we daartoe wettelijk verplicht zijn of op basis van een geldige rechtsgrond.

Wij verkopen je profiel- en matchinggegevens niet aan adverteerders of datahandelaren en gebruiken je matchingantwoorden niet voor gerichte advertenties. We delen je matchingantwoorden niet met externe AI-aanbieders voor modeltraining [CONTROLEER FEITELIJKE IMPLEMENTATIE].

## 7. Waar worden gegevens verwerkt en gaan ze naar buiten de EER?

De primaire Supabase-projectregio is [CONCRETE SUPABASE-REGIO, BIJV. eu-central-1, FRANKFURT, DUITSLAND]. De locatie van appfuncties, logging, opslag/caching, support en eventuele andere dienstverleners is [OVERZICHT REGIO'S]. De gekozen databaseregio betekent niet automatisch dat geen enkele verwerking of doorgifte buiten de EER plaatsvindt.

Voor eventuele doorgifte buiten de EER gebruiken we waar nodig [TOEPASSELIJK DOORGIFTEMECHANISME, BIJV. ADEQUAATHEIDSBESLUIT OF STANDAARDCONTRACTBEPALINGEN MET AANVULLENDE MAATREGELEN]. Een kopie van of informatie over deze waarborgen is verkrijgbaar via [PRIVACY_E-MAIL].

## 8. Hoe beschermen we gegevens?

We gebruiken passende technische en organisatorische maatregelen, zoals versleutelde verbindingen, encryptie van opgeslagen gegevens, toegangscontrole, gescheiden functies voor account- en matchinggegevens, beveiligde authenticatie, beperkte beheerrechten, back-upbeheer en beveiligingscontroles. Profilering- en identiteitsgegevens worden waar praktisch mogelijk gepseudonimiseerd. Een pseudoniem profiel is niet anoniem zolang het aan een account te koppelen is.

De matchingservice moet noodzakelijke antwoorden tijdens de berekening kunnen verwerken. De matchingprofielen zijn daarom niet end-to-end versleuteld ten opzichte van ons gehele systeem. De inhoud van gewone chatberichten is wél end-to-end versleuteld; onze servers kunnen die inhoud niet lezen. Geen enkele beveiligingsmaatregel kan ieder risico volledig uitsluiten.

## 9. Hoe lang bewaren we gegevens?

| Gegevens | Bewaarregel |
| --- | --- |
| Lokaal profiel | Tot je dit op je toestel verwijdert of de appgegevens wist, behoudens externe toestelback-ups |
| Accountgegevens | Zolang het account bestaat; verwijderd als je je account verwijdert. Na 12 maanden zonder app-activiteit blijft alleen de inlog zelf bestaan (om weer in te loggen en aankopen te behouden) |
| iCloud-back-up | In je eigen iCloud tot je bewaarde matches of je profiel verwijdert; wij hebben geen toegang |
| Matchingprofiel en foto's | Zolang matching aanstaat; meteen verwijderd als je het uitzet (tijdens een lopende match zodra die voorbij is), restanten binnen een dag. Na 6 maanden zonder app-activiteit doe je niet meer mee aan matching; na 12 maanden worden profiel en foto's verwijderd |
| Matchscores en matchgegevens | De match (beide account-ID's, de vastgelegde scores, data en hoe hij eindigde) en hashes met een geheime sleutel van beide inlogidentiteiten, zodat dezelfde twee mensen nooit opnieuw gematcht worden, ook niet na het verwijderen en opnieuw aanmaken van een account: tot 5 jaar na het einde van de match. Matchkaarten, chatsleutels en leesposities: 12 maanden na het einde van de match, of zodra jullie allebei de match hebben verwijderd |
| E2EE-versleutelde berichtinhoud | Maximaal 12 maanden na verzending, ook nadat een match is beëindigd |
| Technische logs en metadata | Maximaal [AANTAL_DAGEN], behoudens incidentonderzoek |
| Toestemmingsbewijs | [BEWAARTERMIJN TER VERANTWOORDING EN VERJARING] |
| Veiligheidsmeldingen en blokkades | De toelichting: 12 maanden. De melding zelf (reden, datum en een hash met een geheime sleutel van de inlogidentiteit van wie gemeld is), die meetelt voor een blokkade of ban, ook bij een nieuw account met hetzelfde Apple- of Google-ID: 5 jaar na de melding. Een ban vervalt zodra de oudste van de drie meldingen ouder is dan 5 jaar |
| Back-ups en verwijderde kopieën | Uit roulatie volgens [MAXIMALE BACK-UPRETENTIE EN ROTATIE] |
| Fiscale/andere wettelijk vereiste gegevens | Volgens [WETTELIJKE BEWAARTERMIJN] |

Als je matching uitschakelt, komen er geen nieuwe matches tot stand op basis van dat profiel. Wat een match al heeft gezien, is niet automatisch terug te halen. Wanneer een gebruiker om verwijdering verzoekt, beoordelen we ook de kopieën die wij zelf binnen de dienst bewaren; die blijven niet zonder geldige reden onbeperkt beschikbaar.

## 10. Welke keuzes en rechten heb je?

Je kunt matching weigeren of later uitschakelen zonder je lokale profiel kwijt te raken. Je iCloud-back-up blijft in je eigen beheer. Je hebt, onder de voorwaarden van de AVG, recht op inzage, rectificatie, verwijdering, beperking, overdraagbaarheid en bezwaar; je hebt ook het recht om toestemming in te trekken. Voor geautomatiseerde besluitvorming kunnen aanvullende rechten gelden.

Dien je verzoek in via [IN-APP PAD VOOR PRIVACYVERZOEKEN] of [PRIVACY_E-MAIL]. We kunnen noodzakelijke verificatie vragen en reageren in beginsel binnen één maand, behoudens wettelijk toegestane verlenging. Intrekking verandert niets aan verwerking die vóór de intrekking rechtmatig plaatsvond. Kopieën die ontvangers buiten onze controle hebben bewaard, kunnen we niet gegarandeerd verwijderen.

Als je een account kunt aanmaken, kun je dat ook binnen de app laten verwijderen via [PAD ACCOUNT VERWIJDEREN].

## 11. Minderjarigen, veiligheid en misbruik

De app is 18+. Gebruikers kunnen een andere gebruiker blokkeren en ongewenst gedrag melden via [PAD_BLOKKEREN_EN_MELDEN]. Onze medewerkers kunnen de inhoud van normaal E2EE-verkeer niet lezen. Een gebruiker kan er wel voor kiezen relevante berichten met een melding aan te leveren. We behandelen veiligheidsmeldingen volgens [PROCEDURE_EN_CONTACTPUNT].

## 12. Wijzigingen in deze verklaring

We kunnen deze verklaring bijwerken als de app, onze dienstverleners of wetgeving veranderen. De actuele versie staat op [URL_PRIVACYVERKLARING]. We informeren gebruikers over wezenlijke wijzigingen via [MELDINGSKANAAL]. Als een wijziging nieuwe toestemming vereist, vragen we die voordat de betreffende verwerking start.

## 13. Klachten

Heb je vragen of klachten, neem dan contact op via [PRIVACY_E-MAIL]. Je kunt ook een klacht indienen bij de Autoriteit Persoonsgegevens (Nederland) via https://autoriteitpersoonsgegevens.nl of bij een andere bevoegde Europese toezichthouder.
"""#
}
